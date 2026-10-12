// supabase/functions/send-lockout-email/index.ts
//
// Supabase Edge Function: Email the account owner when their account is
// locked due to too many failed login attempts. Also sends a push
// notification to all admin users so they are aware of the intrusion.
//
// Called by: Flutter app (auth_provider.dart) when the local lockout
// counter hits 5 failures. Fire-and-forget via Supabase.functions.invoke.
//
// Delivery:
//   - User: Gmail SMTP (same as send-approval-email)
//   - Admins: FCM push via shared sendPushToUser helper
//
// Environment secrets required:
//   - GMAIL_SENDER
//   - GMAIL_APP_PASSWORD
//   - FCM_SERVICE_ACCOUNT_KEY
//   - FIREBASE_PROJECT_ID
//
// Deploy: supabase functions deploy send-lockout-email --no-verify-jwt

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendPushToUser, corsHeaders } from "../_shared/push.ts";
import { checkRateLimit, rateLimitedResponse } from "../_shared/rate_limit.ts";

// ---------------------------------------------------------------------------
// Minimal SMTP client (reused from send-approval-email)
// ---------------------------------------------------------------------------

function b64(input: string): string {
  const bytes = new TextEncoder().encode(input);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

function encodeSubject(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return "=?UTF-8?B??" + btoa(binary) + "?=";
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
      // ignore
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

// ---------------------------------------------------------------------------
// Edge function handler
// ---------------------------------------------------------------------------

interface LockoutEmailPayload {
  email: string;
  device?: string; // e.g. "Samsung SM-S908B (Android 14)"
  ip?: string;     // e.g. "120.28.123.45"
  // Where the attempts came from, as the device resolved it: the place the
  // address resolves to, the formatted coordinate pair, and the network that
  // owns the address. Absent on any build that predates them, which is why
  // the address is resolved server-side below.
  location?: string;    // e.g. "Manila, National Capital Region, Philippines"
  coordinates?: string; // e.g. "14.6042° N, 120.9822° E"
  isp?: string;         // e.g. "Globe Telecom Inc. (AS132199)"
  latitude?: number;
  longitude?: number;
  report?: boolean; // true = user flagged this as unauthorized intrusion
}

// ---------------------------------------------------------------------------
// Where the attempt came from
// ---------------------------------------------------------------------------
// ⚠️ City-level at best. An IP address belongs to a network, not to a person:
// the lookup resolves to the city the address block is registered in — for a
// mobile pool, the carrier's hub, which can be a different city (sometimes a
// different region) from the one the device is physically in. Nothing derived
// here may be presented as a street address, and the mail says "approximate,
// city-level" next to it rather than leaving the reader to assume precision
// the data cannot support.
interface AttemptLocation {
  place: string;
  coordinates: string;
  network: string;
}

/// Resolves [ip] to an approximate location, or null.
///
/// Called only when the client sent nothing, which is the case for every
/// build that predates these fields — the account owner's mail is the surface
/// that matters most, so it must not depend on which APK happens to be
/// installed on the other end. A failed lookup, a rate limit, a timeout or a
/// malformed body all return null: this must never fail the mail.
async function lookupAttemptLocation(
  ip: string
): Promise<AttemptLocation | null> {
  try {
    const res = await fetch(`https://ipwho.is/${encodeURIComponent(ip)}`, {
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) return null;

    const body = await res.json();
    if (!body || body.success === false) return null;

    const parts: string[] = [];
    for (const part of [body.city, body.region, body.country]) {
      const value = typeof part === "string" ? part.trim() : "";
      if (!value) continue;
      // "Singapore, Singapore" is one place, not two.
      if (
        parts.length > 0 &&
        parts[parts.length - 1].toLowerCase() === value.toLowerCase()
      ) {
        continue;
      }
      parts.push(value);
    }

    const lat = typeof body.latitude === "number" ? body.latitude : null;
    const lon = typeof body.longitude === "number" ? body.longitude : null;
    const coordinates =
      lat !== null && lon !== null
        ? `${Math.abs(lat).toFixed(4)}° ${lat >= 0 ? "N" : "S"}, ` +
          `${Math.abs(lon).toFixed(4)}° ${lon >= 0 ? "E" : "W"}`
        : "";

    const connection = body.connection ?? {};
    const isp = typeof connection.isp === "string" ? connection.isp.trim() : "";
    const asn = typeof connection.asn === "number" ? `AS${connection.asn}` : "";
    const network = isp && asn ? `${isp} (${asn})` : isp || asn;

    if (!parts.length && !coordinates && !network) return null;
    return { place: parts.join(", "), coordinates, network };
  } catch (e) {
    console.log(`[LockoutEmail] Location lookup failed for ${ip}: ${e}`);
    return null;
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // T6: per-IP rate limit (30/min — lockout events are rare and
  // human-paced; this only trips scripted abuse).
  const rl = await checkRateLimit(req, "send-lockout-email", 30);
  if (!rl.allowed) return rateLimitedResponse(rl, corsHeaders);

  try {
    const payload: LockoutEmailPayload = await req.json();

    if (!payload.email) {
      return new Response(
        JSON.stringify({ error: "Missing required field: email" }),
        { status: 400, headers: corsHeaders }
      );
    }

    const gmailSender = Deno.env.get("GMAIL_SENDER");
    const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");
    if (!gmailSender || !gmailAppPassword) {
      console.error(
        "[LockoutEmail] Missing GMAIL_SENDER / GMAIL_APP_PASSWORD secrets"
      );
      return new Response(
        JSON.stringify({ error: "Email service not configured" }),
        { status: 500, headers: corsHeaders }
      );
    }

    const email = payload.email.trim().toLowerCase();
    const subject = "⚠️ Your CUFMAI account has been temporarily locked";

    // The client's own reading of the address wins when it has one (it looked
    // up the same address), and the address is resolved here when it did not.
    const clientPlace = (payload.location ?? "").trim();
    const clientCoordinates = (payload.coordinates ?? "").trim();
    const clientNetwork = (payload.isp ?? "").trim();
    const attemptLocation: AttemptLocation | null =
      clientPlace || clientCoordinates || clientNetwork
        ? {
            place: clientPlace,
            coordinates: clientCoordinates,
            network: clientNetwork,
          }
        : payload.ip
        ? await lookupAttemptLocation(payload.ip)
        : null;

    const html = `<!doctype html>
<html>
<body style="margin:0;padding:0;background:#F5F0E6;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F5F0E6;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #D9D0C7;">
        <tr><td style="background:#D64545;padding:28px 32px;">
          <h1 style="margin:0;color:#FFFFFF;font-size:22px;">🔒 Account Temporarily Locked</h1>
        </td></tr>
        <tr><td style="padding:28px 32px;color:#3B2314;font-size:15px;line-height:1.6;">
          <p>Hi there,</p>
          <p>We detected <strong>multiple failed login attempts</strong> on your CUFMAI account (<strong>${email}</strong>).</p>
          <p>To protect your account, it has been <strong>temporarily locked for 30 minutes</strong>.</p>

          ${
            (payload.device || payload.ip || attemptLocation)
              ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FEF2F2;border-radius:12px;border:1px solid #FECACA;margin:20px 0;">
            <tr><td style="padding:16px 20px;">
              <p style="margin:0 0 8px 0;font-size:14px;"><strong>📍 Attempt details:</strong></p>
              ${payload.device ? `<p style="margin:0 0 4px 0;font-size:13px;color:#6B5C4E;">Device: <strong>${payload.device}</strong></p>` : ""}
              ${
                attemptLocation?.place
                  ? `<p style="margin:0 0 4px 0;font-size:13px;color:#6B5C4E;">Location: <strong>${attemptLocation.place}</strong> <span style="color:#9A8C7E;">(approximate, city-level)</span></p>`
                  : ""
              }
              ${
                attemptLocation?.coordinates
                  ? `<p style="margin:0 0 4px 0;font-size:13px;color:#6B5C4E;">Coordinates: <span style="font-family:monospace;">${attemptLocation.coordinates}</span></p>`
                  : ""
              }
              ${
                attemptLocation?.network
                  ? `<p style="margin:0 0 4px 0;font-size:13px;color:#6B5C4E;">Network: ${attemptLocation.network}</p>`
                  : ""
              }
              ${payload.ip ? `<p style="margin:0;font-size:13px;color:#6B5C4E;">IP Address: <strong>${payload.ip}</strong></p>` : ""}
            </td></tr>
          </table>${
            attemptLocation?.place || attemptLocation?.coordinates
              ? `<p style="margin:0 0 20px 0;color:#9A8C7E;font-size:12px;">An IP address identifies a network, not a person: the location above is the city the address is registered in. A mobile connection can resolve to a different city than the device is actually in.</p>`
              : ""
          }`
              : ""
          }

          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FFF8F0;border-radius:12px;border:1px solid #E8DDD0;margin:20px 0;">
            <tr><td style="padding:16px 20px;">
              <p style="margin:0;font-size:14px;"><strong>What you can do:</strong></p>
              <ul style="margin:8px 0 0 0;padding-left:20px;font-size:14px;color:#6B5C4E;">
                <li>Wait 30 minutes and try again</li>
                <li>Use <strong>Forgot password?</strong> on the login screen to reset your password</li>
                <li>If this wasn't you, change your password immediately</li>
              </ul>
            </td></tr>
          </table>

          <p style="margin-top:20px;color:#6B5C4E;font-size:13px;">If you did not attempt to log in, your account may be at risk. Please reset your password as soon as possible.</p>
          <p style="color:#6B5C4E;font-size:13px;">— The CUFMAI Team</p>
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

    console.log(`[LockoutEmail] Sent lockout email to ${email}`);

    // ── Push notification to all admins ─────────────────────────
    // Query all admin profiles and send each a push notification
    // about the lockout so they are aware of the intrusion attempt.
    try {
      const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
      const supabase = createClient(supabaseUrl, supabaseServiceKey);

      const { data: admins } = await supabase
        .from("profiles")
        .select("id")
        .eq("role", "admin");

      if (admins && admins.length > 0) {
        const deviceDetail = [payload.device, payload.ip].filter(Boolean).join(" from ");
        const where = attemptLocation?.place
          ? ` near ${attemptLocation.place}`
          : "";
        const adminPushPromises = admins.map((admin) =>
          sendPushToUser(
            supabase,
            admin.id,
            {
              title: "🚨 Suspicious Login Detected",
              body: `Multiple failed login attempts on ${email}${where}${deviceDetail ? ". Device: " + deviceDetail : ""}. Account has been locked for 30 minutes.`,
            },
            {
              type: "lockout",
            }
          )
        );
        await Promise.allSettled(adminPushPromises);
        console.log(`[LockoutEmail] Notified ${admins.length} admin(s) via push`);
      }
    } catch (pushErr) {
      console.error("[LockoutEmail] Admin push notification failed:", pushErr);
      // Best-effort — email already sent
    }

    // ── Intrusion report ("This wasn't me") ────────────────────
    // If the user flagged this as unauthorized, create a report in the
    // reports table so admins can see it in the Reports section.
    if (payload.report) {
      try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
        const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
        const supabase = createClient(supabaseUrl, supabaseServiceKey);

        // Look up the user's profile to get their reporter_id
        const { data: profile } = await supabase
          .from("profiles")
          .select("id")
          .eq("email", email)
          .maybeSingle();

        if (profile) {
          const deviceDetail = [payload.device, payload.ip]
            .filter(Boolean)
            .join(" from ");

          const locationDetail = attemptLocation?.place
            ? `Approximate location: ${attemptLocation.place}` +
              (attemptLocation.coordinates
                ? ` (${attemptLocation.coordinates})`
                : "") +
              (attemptLocation.network ? `, ${attemptLocation.network}` : "") +
              `. City-level, from the IP address. `
            : "";

          await supabase.from("reports").insert({
            reporter_id: profile.id,
            reporter_role: "customer",
            type: "other",
            category: "account_issue",
            priority: "high",
            custom_details:
              `Unauthorized login attempt detected. ` +
              (deviceDetail ? `Suspicious device: ${deviceDetail}. ` : "") +
              locationDetail +
              `Account was locked after 5 failed attempts. User reports this was not them.`,
          });

          console.log(`[LockoutEmail] Intrusion report created for ${email}`);
        }
      } catch (reportErr) {
        console.error("[LockoutEmail] Report creation failed:", reportErr);
        // Best-effort — email + push already sent
      }
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: corsHeaders,
    });
  } catch (e) {
    console.error("[LockoutEmail] Error:", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
