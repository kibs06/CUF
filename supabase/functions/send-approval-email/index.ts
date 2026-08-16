// supabase/functions/send-approval-email/index.ts
//
// Supabase Edge Function: Email a seller when an admin approves or rejects
// their seller application.
//
// Called by: Flutter admin console (OrderProvider.approveSeller/rejectSeller)
// and the admin-portal React app (useApproveApplication/useRejectApplication)
// — fire-and-forget via Supabase.functions.invoke right after the
// profiles.seller_status update succeeds. The in-app notification is handled
// separately by the DB trigger `trg_notify_on_seller_approved` (migration
// 20260816150000_add_seller_approval_notification.sql); this function covers
// the email channel so the seller hears about the decision even when they're
// not inside the app.
//
// Delivery: Gmail SMTP (smtp.gmail.com:465, implicit TLS) using an App
// Password — NO third-party email provider, NO domain ownership, NO DNS
// records, NO payment. Just a dedicated Gmail account the app owns.
//
// The SMTP client is self-contained (raw SMTP over Deno.connectTls) because
// the old deno.land/x/smtp module used Deno.writeAll, which no longer exists
// on the Deno 2 runtime Supabase Edge Functions run. No dependencies here.
//
// Environment secrets required:
//   - GMAIL_SENDER: the app's Gmail address, e.g. cufmai.marketplace@gmail.com
//   - GMAIL_APP_PASSWORD: a 16-char App Password for that account
//     (Google Account → Security → 2-Step Verification → App passwords).
//     The App Password replaces the real password; the Gmail password itself
//     must NEVER be stored here.
//
// Deploy: supabase functions deploy send-approval-email --no-verify-jwt

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ---------------------------------------------------------------------------
// Minimal SMTP client (Gmail over TLS, AUTH LOGIN). No third-party modules.
// ---------------------------------------------------------------------------

/** Base64-encode an ASCII string (SMTP credentials are ASCII). */
function b64(input: string): string {
  const bytes = new TextEncoder().encode(input);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

/** RFC 2047 encoded-word for non-ASCII subjects (e.g. the 🎉 emoji). */
function encodeSubject(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return "=?UTF-8?B?" + btoa(binary) + "?=";
}

class SmtpClient {
  private conn!: Deno.Conn;
  private reader!: Deno.Reader;
  private buffer = new Uint8Array(0);

  async connectTLS(
    opts: { hostname: string; port: number; username: string; password: string }
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

    // AUTH LOGIN (Gmail accepts it with an App Password).
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

  /** Send an email. `html` is the UTF-8 HTML body; subject may contain emoji. */
  async send(opts: {
    from: string;
    to: string;
    subject: string;
    html: string;
  }): Promise<void> {
    const mail = await this.command(`MAIL FROM:<${opts.from}>`);
    if (!/^250/.test(mail)) throw new Error("MAIL FROM rejected: " + mail);

    const rcpt = await this.command(`RCPT TO:<${opts.to}>`);
    if (!/^250/.test(rcpt)) throw new Error("RCPT TO rejected: " + rcpt);

    const data = await this.command("DATA");
    if (!/^354/.test(data)) throw new Error("DATA rejected: " + data);

    // Build the raw message. Body is base64 so UTF-8 (incl. emoji) is safe.
    const bodyB64 = b64(opts.html).replace(/(.{76})/g, "$1\r\n");
    const message =
      `From: CUFMAI <${opts.from}>\r\n` +
      `To: <${opts.to}>\r\n` +
      `Subject: ${encodeSubject(opts.subject)}\r\n` +
      "MIME-Version: 1.0\r\n" +
      "Content-Type: text/html; charset=UTF-8\r\n" +
      "Content-Transfer-Encoding: base64\r\n" +
      "\r\n" +
      bodyB64 +
      "\r\n.\r\n";

    await this.rawWrite(message);
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

  // -- internals -------------------------------------------------------------

  private async rawWrite(text: string): Promise<void> {
    await this.conn.write(new TextEncoder().encode(text));
  }

  private async command(cmd: string): Promise<string> {
    await this.rawWrite(cmd + "\r\n");
    // Collect multi-line replies (e.g. EHLO's 250-... blocks).
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

// ---------------------------------------------------------------------------
// Edge function handler
// ---------------------------------------------------------------------------

interface ApprovalEmailPayload {
  userId: string;
  outcome: "approved" | "rejected";
  rejectionReason?: string;
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload: ApprovalEmailPayload = await req.json();

    if (!payload.userId || !payload.outcome) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: userId, outcome" }),
        { status: 400, headers: corsHeaders }
      );
    }

    const gmailSender = Deno.env.get("GMAIL_SENDER");
    const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");
    if (!gmailSender || !gmailAppPassword) {
      console.error(
        "[ApprovalEmail] Missing GMAIL_SENDER / GMAIL_APP_PASSWORD secrets"
      );
      return new Response(
        JSON.stringify({ error: "Email service not configured" }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Look up the applicant's email + name with the service role key.
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("email, full_name")
      .eq("id", payload.userId)
      .maybeSingle();

    if (profileError) {
      console.error("[ApprovalEmail] Profile lookup error:", profileError);
      return new Response(
        JSON.stringify({ error: "Profile lookup failed" }),
        { status: 500, headers: corsHeaders }
      );
    }

    const email = profile?.email;
    if (!email) {
      console.error(
        `[ApprovalEmail] No email on profile for user=${payload.userId}`
      );
      return new Response(
        JSON.stringify({ error: "Profile has no email" }),
        { status: 404, headers: corsHeaders }
      );
    }

    const name = profile?.full_name ?? "there";
    const isApproved = payload.outcome === "approved";

    const subject = isApproved
      ? "You're approved! Your CUFMAI seller application was accepted 🎉"
      : "Update on your CUFMAI seller application";

    const html = isApproved
      ? `<!doctype html>
<html>
<body style="margin:0;padding:0;background:#F5F0E6;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F5F0E6;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #D9D0C7;">
        <tr><td style="background:#3B2314;padding:28px 32px;">
          <h1 style="margin:0;color:#FFFFFF;font-size:22px;">Welcome to the CUFMAI marketplace!</h1>
        </td></tr>
        <tr><td style="padding:28px 32px;color:#3B2314;font-size:15px;line-height:1.6;">
          <p>Hi ${name},</p>
          <p>Great news — your seller application has been <strong>approved</strong>. You can now log in to the app and start selling to the Carcar community.</p>
          <p><strong>Next step:</strong> open the app, go to your seller dashboard, and set up your store (name, banner, and tags are already pre-filled from your application).</p>
          <p style="margin-top:24px;color:#6B5C4E;font-size:13px;">Questions? Reach out to the CUFMAI team through the app.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`
      : `<!doctype html>
<html>
<body style="margin:0;padding:0;background:#F5F0E6;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F5F0E6;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #D9D0C7;">
        <tr><td style="background:#D64545;padding:28px 32px;">
          <h1 style="margin:0;color:#FFFFFF;font-size:22px;">Update on your application</h1>
        </td></tr>
        <tr><td style="padding:28px 32px;color:#3B2314;font-size:15px;line-height:1.6;">
          <p>Hi ${name},</p>
          <p>Thank you for applying to sell on the CUFMAI marketplace. After careful review, we're unable to approve your application at this time.</p>
          ${
            payload.rejectionReason
              ? `<p><strong>Reason:</strong> ${payload.rejectionReason}</p>`
              : ""
          }
          <p>You can review the requirements and re-apply through the app.</p>
          <p style="margin-top:24px;color:#6B5C4E;font-size:13px;">Questions? Reach out to the CUFMAI team through the app.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;

    const client = new SmtpClient();
    try {
      await client.connectTLS({
        hostname: "smtp.gmail.com",
        port: 465,
        username: gmailSender,
        password: gmailAppPassword,
      });
      await client.send({
        from: gmailSender,
        to: email,
        subject,
        html,
      });
    } finally {
      await client.close();
    }

    console.log(
      `[ApprovalEmail] Sent ${payload.outcome} email to ${email} (user=${payload.userId})`
    );

    return new Response(JSON.stringify({ ok: true }), {
      headers: corsHeaders,
    });
  } catch (e) {
    console.error("[ApprovalEmail] Error:", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
