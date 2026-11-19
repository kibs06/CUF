// supabase/functions/_shared/smtp.ts
//
// The project's Gmail over TLS sender, with attachments.
//
// `send-approval-email` and `send-lockout-email` each carry their own copy of
// this SMTP client (raw AUTH LOGIN over Deno.connectTls), because Supabase
// Edge Functions run Deno 2 and the old deno.land/x/smtp module does not. Both
// of those copies send a single text/html part. The order receipt needs the
// same channel plus a PDF, so the protocol code lives here once, with the
// multipart branch added, and new senders use this module.
//
// Why Gmail SMTP rather than a transactional provider: the account already
// exists, GMAIL_SENDER / GMAIL_APP_PASSWORD are already set as function
// secrets (2026-11), and an App Password sends to any recipient without a
// verified domain. A provider would mean a new key, a DNS/domain verification
// step, and a second delivery path to keep alive for the same handful of
// messages.
//
// Secrets: GMAIL_SENDER (the app's own Gmail address), GMAIL_APP_PASSWORD (a
// 16-character App Password for it — never the account password).

/** A file to attach to the message, already in memory. */
export interface SmtpAttachment {
  filename: string;
  contentType: string;
  bytes: Uint8Array;
}

/** Base64-encode bytes, chunked so a large PDF cannot blow the call stack. */
export function b64Bytes(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/** Base64-encode an ASCII string (SMTP credentials are ASCII). */
export function b64(input: string): string {
  return b64Bytes(new TextEncoder().encode(input));
}

/** RFC 2047 encoded-word, for subjects that carry emoji or a en dash. */
export function encodeSubject(text: string): string {
  return "=?UTF-8?B?" + b64(text) + "?=";
}

/** Wrap a base64 payload at 76 characters with CRLF, as MIME requires. */
function wrap76(value: string): string {
  return value.replace(/(.{76})/g, "$1\r\n");
}

export class SmtpClient {
  private conn!: Deno.Conn;
  // `Deno.Reader` was removed from the Deno 2 typings; a `Deno.Conn` provides
  // the same `read(Uint8Array)` signature this client uses.
  private reader!: Deno.Conn;
  private buffer = new Uint8Array(0);

  async connectTLS(
    opts: { hostname: string; port: number; username: string; password: string },
  ): Promise<void> {
    this.conn = await Deno.connectTls({
      hostname: opts.hostname,
      port: opts.port,
    });
    this.reader = this.conn;

    const greeting = await this.readLine();
    if (!greeting.startsWith("220")) {
      throw new Error("SMTP greeting failed: " + greeting);
    }

    const ehlo = await this.command("EHLO cufmai.app");
    if (!/^250/.test(ehlo)) {
      throw new Error("EHLO rejected: " + ehlo);
    }

    const authPrompt = await this.command("AUTH LOGIN");
    if (!/^334/.test(authPrompt)) {
      throw new Error("AUTH LOGIN not offered: " + authPrompt);
    }
    const userPrompt = await this.command(b64(opts.username));
    if (!/^334/.test(userPrompt)) {
      throw new Error("AUTH LOGIN username rejected: " + userPrompt);
    }
    const passPrompt = await this.command(b64(opts.password));
    if (!/^235/.test(passPrompt)) {
      throw new Error("AUTH LOGIN password rejected: " + passPrompt);
    }
  }

  /**
   * Send one message. `html` is the body; `attachments` ride along as
   * multipart/mixed parts. Every part is base64, so the body's dot-stuffing
   * rules and non-ASCII text are moot.
   */
  async send(opts: {
    from: string;
    to: string;
    subject: string;
    html: string;
    attachments?: SmtpAttachment[];
  }): Promise<void> {
    const mail = await this.command(`MAIL FROM:<${opts.from}>`);
    if (!/^250/.test(mail)) throw new Error("MAIL FROM rejected: " + mail);

    const rcpt = await this.command(`RCPT TO:<${opts.to}>`);
    if (!/^250/.test(rcpt)) throw new Error("RCPT TO rejected: " + rcpt);

    const data = await this.command("DATA");
    if (!/^354/.test(data)) throw new Error("DATA rejected: " + data);

    const attachments = opts.attachments ?? [];
    const headers =
      `From: CUFMAI <${opts.from}>\r\n` +
      `To: <${opts.to}>\r\n` +
      `Subject: ${encodeSubject(opts.subject)}\r\n` +
      "MIME-Version: 1.0\r\n";

    let message: string;
    if (attachments.length === 0) {
      message = headers +
        "Content-Type: text/html; charset=UTF-8\r\n" +
        "Content-Transfer-Encoding: base64\r\n" +
        "\r\n" +
        wrap76(b64(opts.html)) +
        "\r\n";
    } else {
      // Stable-ish boundary: no crypto needed, just something the payloads
      // cannot contain.
      const boundary = "cufmai-mixed-" +
        Date.now().toString(36) + "-" + Math.random().toString(36).slice(2);
      message = headers +
        `Content-Type: multipart/mixed; boundary="${boundary}"\r\n` +
        "\r\n" +
        "--" + boundary + "\r\n" +
        "Content-Type: text/html; charset=UTF-8\r\n" +
        "Content-Transfer-Encoding: base64\r\n" +
        "\r\n" +
        wrap76(b64(opts.html)) +
        "\r\n";

      for (const file of attachments) {
        message += "--" + boundary + "\r\n" +
          `Content-Type: ${file.contentType}; name="${file.filename}"\r\n` +
          "Content-Transfer-Encoding: base64\r\n" +
          `Content-Disposition: attachment; filename="${file.filename}"\r\n` +
          "\r\n" +
          wrap76(b64Bytes(file.bytes)) +
          "\r\n";
      }
      message += "--" + boundary + "--\r\n";
    }

    // The terminating dot goes on its own line, after the last part.
    await this.rawWrite(message + ".\r\n");
    const done = await this.readLine();
    if (!/^250/.test(done)) throw new Error("DATA send failed: " + done);
  }

  async close(): Promise<void> {
    try {
      await this.command("QUIT");
    } catch (_) {
      // ignore — best effort
    }
    try {
      this.conn.close();
    } catch (_) {
      // already closed
    }
  }

  private async rawWrite(text: string): Promise<void> {
    await this.conn.write(new TextEncoder().encode(text));
  }

  private async command(cmd: string): Promise<string> {
    await this.rawWrite(cmd + "\r\n");
    let line = await this.readLine();
    let last = line;
    while (line.length >= 4 && line[3] === "-") {
      line = await this.readLine();
      last = line;
    }
    return last;
  }

  private async readLine(): Promise<string> {
    while (true) {
      const nl = this.buffer.indexOf(0x0a);
      if (nl !== -1) {
        const line = new TextDecoder()
          .decode(this.buffer.slice(0, nl))
          .replace(/\r$/, "");
        this.buffer = this.buffer.slice(nl + 1);
        return line;
      }
      const chunk = new Uint8Array(4096);
      const n = await this.reader.read(chunk);
      if (n === null) throw new Error("SMTP connection closed unexpectedly");
      const merged = new Uint8Array(this.buffer.length + n);
      merged.set(this.buffer);
      merged.set(chunk.subarray(0, n), this.buffer.length);
      this.buffer = merged;
    }
  }
}
