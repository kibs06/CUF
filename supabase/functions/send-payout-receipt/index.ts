// supabase/functions/send-payout-receipt/index.ts
//
// Supabase Edge Function: tell a seller their payout has been sent — a push to
// their devices and an email receipt to their inbox.
//
// Called by: the admin portal, immediately after `mark_payout_paid` returns
// success for a batch. Fire-and-forget from the portal's point of view: the
// transfer is recorded either way, so this function reports what it delivered
// instead of failing the admin's action.
//
// Delivery: Gmail SMTP through `_shared/smtp.ts` (the same channel as the
// order receipt, approval and replacement mails), and FCM through
// `_shared/push.ts`. No third-party provider.
//
// Secrets: GMAIL_SENDER, GMAIL_APP_PASSWORD, FCM_SERVICE_ACCOUNT_KEY,
// FIREBASE_PROJECT_ID (already set for the other senders). SUPABASE_URL /
// SUPABASE_SERVICE_ROLE_KEY are provided by the platform.
//
// Authorization: the caller must be an admin (checked with `is_admin()` on a
// client carrying their own JWT), or present the service-role key. The gateway
// JWT check alone proves nothing — the anon key is also a JWT.
//
// Idempotent: a batch that already carries `payout_notice_sent_at` is skipped
// unless `force: true`, so a retried portal request cannot mail twice. Until
// migration 20261119190000 is applied that column is absent; the read uses
// `select('*')` and the stamp is skipped with a warning, exactly like the
// replacement notice handles its own stamp.
//
// Deploy: supabase functions deploy send-payout-receipt

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SmtpClient } from "../_shared/smtp.ts";
import { sendPushToUser } from "../_shared/push.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface PayoutRequest {
  payout_id?: string;
  /** Answers a secrets/boot check instead of sending anything. */
  ping?: boolean;
  /** Re-send even though the notice stamp is already set. */
  force?: boolean;
  /** Build the message but send nothing. */
  dry_run?: boolean;
}

interface PayoutRow {
  id: string;
  store_id: string;
  period_date?: string | null;
  gross_amount?: number | null;
  delivery_fees?: number | null;
  platform_fee?: number | null;
  net_amount?: number | null;
  order_count?: number | null;
  status?: string | null;
  paid_at?: string | null;
  paid_reference?: string | null;
  payout_notice_sent_at?: string | null;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const money = (value: number) =>
  "₱" + value.toFixed(2).replace(/\.00$/, "");

/** "2026-11-18" → "November 18, 2026"; anything unexpected passes through. */
function longDate(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return iso;
  const months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  const month = months[Number(m[2]) - 1] ?? m[2];
  return `${month} ${Number(m[3])}, ${m[1]}`;
}

function shortDate(iso: string): string {
  const dt = new Date(iso);
  if (Number.isNaN(dt.getTime())) return iso;
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  const h24 = dt.getHours();
  const h = h24 % 12 === 0 ? 12 : h24 % 12;
  const mm = String(dt.getMinutes()).padStart(2, "0");
  return `${months[dt.getMonth()]} ${dt.getDate()}, ${dt.getFullYear()} · ${h}:${mm} ${
    h24 >= 12 ? "PM" : "AM"
  }`;
}

/**
 * `profiles.payout_details` holds what `encodePayoutDetails` wrote in the
 * seller app — JSON `{ number, name }`, or (older rows) a bare string. Read it
 * defensively: a malformed value must not stop the receipt.
 */
function readPayoutAccount(raw: string | null | undefined): {
  number: string;
  name: string;
} {
  const text = (raw ?? "").trim();
  if (!text) return { number: "", name: "" };
  try {
    const parsed = JSON.parse(text) as { number?: unknown; name?: unknown };
    return {
      number: typeof parsed.number === "string" ? parsed.number.trim() : "",
      name: typeof parsed.name === "string" ? parsed.name.trim() : "",
    };
  } catch {
    return { number: text, name: "" };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Which stage failed, reported in the 500 body — the portal shows it.
  let step = "parse";
  try {
    const payload = (await req.json().catch(() => ({}))) as PayoutRequest;
    const payoutId = (payload.payout_id ?? "").trim();

    if (!payoutId && payload.ping) {
      return json({
        ok: true,
        ping: true,
        gmail: Boolean(
          Deno.env.get("GMAIL_SENDER") && Deno.env.get("GMAIL_APP_PASSWORD"),
        ),
        fcm: Boolean(
          Deno.env.get("FCM_SERVICE_ACCOUNT_KEY") &&
            Deno.env.get("FIREBASE_PROJECT_ID"),
        ),
      });
    }
    if (!payoutId) return json({ error: "payout_id is required" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const gmailSender = Deno.env.get("GMAIL_SENDER") ?? "";
    const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD") ?? "";

    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });

    // ── Who is asking ───────────────────────────────────────────────
    const token = (req.headers.get("Authorization") ?? "")
      .replace(/^Bearer\s+/i, "")
      .trim();
    const isServiceCall = token.length > 0 && token === serviceKey;

    if (!isServiceCall) {
      if (!token) return json({ error: "Not authenticated" }, 401);
      if (!anonKey) return json({ error: "SUPABASE_ANON_KEY is not set" }, 500);

      // A client carrying the CALLER'S token, so `is_admin()` evaluates against
      // their session. The service-role client has no session, and
      // `is_admin()` there is always false.
      const userClient = createClient(supabaseUrl, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: { Authorization: `Bearer ${token}` } },
      });

      const { data: caller, error: callerError } = await userClient.auth
        .getUser(token);
      if (callerError || !caller?.user) {
        return json({ error: "Not authenticated" }, 401);
      }

      const { data: isAdmin, error: adminError } = await userClient.rpc(
        "is_admin",
      );
      if (adminError) {
        return json(
          { error: "Could not verify admin access", step: "auth" },
          500,
        );
      }
      if (isAdmin !== true) {
        return json({ error: "Only admins can send payout receipts" }, 403);
      }
    }

    step = "payout_read";
    // `select *`: naming `payout_notice_sent_at` makes the whole read 500 on a
    // database that has not applied 20261119190000 yet.
    const { data: payoutData, error: payoutError } = await supabase
      .from("seller_payouts")
      .select("*")
      .eq("id", payoutId)
      .maybeSingle();

    if (payoutError) {
      return json({ error: payoutError.message, step: "payout_read" }, 500);
    }
    const payout = payoutData as unknown as PayoutRow | null;
    if (!payout) return json({ error: "Payout not found" }, 404);
    if (payout.status !== "paid") {
      return json({ error: "Only a paid batch can be receipted" }, 400);
    }

    const hasStampColumn = Object.prototype.hasOwnProperty.call(
      payout,
      "payout_notice_sent_at",
    );
    if (payout.payout_notice_sent_at && !payload.force) {
      return json({ ok: true, skipped: "already_sent" });
    }

    step = "owner_read";
    const { data: store } = await supabase
      .from("stores")
      .select("*")
      .eq("id", payout.store_id)
      .maybeSingle();

    const ownerId = (store?.owner_id as string | undefined) ?? "";
    if (!ownerId) {
      return json({ error: "This store has no owner to notify" }, 400);
    }

    const { data: owner } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", ownerId)
      .maybeSingle();

    let email = ((owner?.email as string | undefined) ?? "").trim();
    if (!email) {
      // Last resort: the address on the auth account.
      try {
        const { data: authUser } = await supabase.auth.admin.getUserById(
          ownerId,
        );
        email = (authUser?.user?.email ?? "").trim();
      } catch (e) {
        console.warn("[PayoutReceipt] auth email lookup failed:", e);
      }
    }

    const ownerName = ((owner?.full_name as string | undefined) ?? "").trim() ||
      "there";
    const storeName = (store?.name as string | undefined) ?? "Your store";
    const account = readPayoutAccount(
      owner?.payout_details as string | undefined,
    );

    // ── The receipt ─────────────────────────────────────────────────
    const net = Number(payout.net_amount ?? 0);
    const gross = Number(payout.gross_amount ?? 0);
    const delivery = Number(payout.delivery_fees ?? 0);
    const commission = Number(payout.platform_fee ?? 0);
    const orders = Number(payout.order_count ?? 0);
    const periodIso = (payout.period_date ?? "").toString().slice(0, 10);
    const period = periodIso ? longDate(periodIso) : "your latest batch";
    const reference = (payout.paid_reference ?? "").toString().trim();
    const paidAt = (payout.paid_at ?? "").toString();

    const subject = `Payout sent — ${money(net)} for ${period}`;
    const destination = account.number
      ? `${account.number}${account.name ? ` · ${account.name}` : ""}`
      : "your saved GCash account";

    const html = `<!doctype html>
<html>
<body style="margin:0;padding:0;background:#F5F0E6;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F5F0E6;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #D9D0C7;">
        <tr><td style="background:#4F6B35;padding:28px 32px;">
          <h1 style="margin:0;color:#FFFFFF;font-size:22px;">Your payout has been sent</h1>
        </td></tr>
        <tr><td style="padding:28px 32px;color:#3B2314;font-size:15px;line-height:1.6;">
          <p>Hi ${ownerName},</p>
          <p>CUFMAI has transferred <strong>${money(net)}</strong> to <strong>${storeName}</strong> for <strong>${period}</strong>.</p>
          <p style="margin:20px 0;padding:16px 18px;background:#F7F3EA;border-radius:12px;">
            <span style="display:block;font-size:12px;letter-spacing:.08em;color:#6B5C4E;">AMOUNT SENT</span>
            <span style="display:block;font-size:26px;font-weight:bold;color:#4F6B35;margin-top:2px;">${money(net)}</span>
            <span style="display:block;font-size:13px;color:#6B5C4E;margin-top:6px;">To ${destination}</span>
            ${reference ? `<span style="display:block;font-size:13px;color:#6B5C4E;margin-top:2px;">Transfer reference: <strong>${reference}</strong></span>` : ""}
            ${paidAt ? `<span style="display:block;font-size:13px;color:#6B5C4E;margin-top:2px;">Sent ${shortDate(paidAt)}</span>` : ""}
          </span>
          </p>
          <p><strong>How this batch was worked out</strong></p>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:14px;color:#3B2314;">
            <tr><td style="padding:6px 0;">Gross sales (${orders} order${orders === 1 ? "" : "s"})</td><td align="right" style="padding:6px 0;">${money(gross)}</td></tr>
            <tr><td style="padding:6px 0;">Delivery fees</td><td align="right" style="padding:6px 0;">− ${money(delivery)}</td></tr>
            <tr><td style="padding:6px 0;">Platform commission</td><td align="right" style="padding:6px 0;">− ${money(commission)}</td></tr>
            <tr><td style="padding:10px 0;border-top:1px solid #E6DED2;font-weight:bold;">Net payout</td><td align="right" style="padding:10px 0;border-top:1px solid #E6DED2;font-weight:bold;">${money(net)}</td></tr>
          </table>
          <p>Keep this email as your receipt. The same batch and its reference are listed under <strong>Earnings → payout history</strong> in the seller app.</p>
          <p style="margin-top:24px;color:#6B5C4E;font-size:13px;">Money did not arrive? Reply to this email or message the CUFMAI team with the transfer reference above.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;

    if (payload.dry_run) {
      return json({
        ok: true,
        dry_run: true,
        to: email,
        subject,
        net,
        store: storeName,
      });
    }

    // ── Email ───────────────────────────────────────────────────────
    // Each channel runs on its own: a missing inbox must not stop the push,
    // and a mail failure must not hide a delivered notification.
    step = "email";
    let emailSent = false;
    let emailReason: string | null = null;
    if (!gmailSender || !gmailAppPassword) {
      emailReason = "email_not_configured";
    } else if (!email) {
      emailReason = "no_email";
    } else {
      const smtp = new SmtpClient();
      try {
        await smtp.connectTLS({
          hostname: "smtp.gmail.com",
          port: 465,
          username: gmailSender,
          password: gmailAppPassword,
        });
        await smtp.send({ from: gmailSender, to: email, subject, html });
        emailSent = true;
      } catch (e) {
        console.error("[PayoutReceipt] SMTP send failed:", e);
        emailReason = "smtp_failed";
      } finally {
        try {
          await smtp.close();
        } catch (_) {
          // The connection may never have opened; nothing left to close.
        }
      }
    }

    // ── Push ────────────────────────────────────────────────────────
    step = "push";
    let pushSuccess = 0;
    let pushError: string | null = null;
    let devices = 0;
    try {
      const { count } = await supabase
        .from("device_tokens")
        .select("fcm_token", { count: "exact", head: true })
        .eq("customer_id", ownerId);
      devices = count ?? 0;

      const push = await sendPushToUser(
        supabase,
        ownerId,
        {
          title: "Payout sent",
          body: `${money(net)} for ${period} is on its way to your GCash` +
            (reference ? ` — ref ${reference}` : "") + ". Tap to see the batch.",
        },
        {
          type: "payouts",
          referenceId: payout.id,
          screen: "seller_earnings",
        },
      );
      pushSuccess = push.successCount;
    } catch (e) {
      console.error("[PayoutReceipt] push failed:", e);
      pushError = String(e);
    }

    // ── Bell entry ──────────────────────────────────────────────────
    // The push is one swipe away from gone; this row is what keeps the receipt
    // findable in the seller's Notification Center, the same way order and
    // replacement notices are. `reference_id` is the payout, so the row taps
    // through to Earnings. `type: 'payout'` arrives with migration
    // 20261119200000; before that the table's check constraint refuses the
    // insert — reported, never allowed to fail the receipt.
    step = "in_app";
    let inAppInserted = false;
    let inAppReason: string | null = null;
    try {
      const { error: inAppError } = await supabase
        .from("seller_notifications")
        .insert({
          store_id: payout.store_id,
          type: "payout",
          title: "Payout sent",
          body: `${money(net)} for ${period} was sent to your GCash` +
            (reference ? ` — ref ${reference}` : "") + ".",
          reference_id: payout.id,
        });
      if (inAppError) {
        console.warn("[PayoutReceipt] bell entry skipped:", inAppError.message);
        inAppReason = inAppError.code === "23514"
          ? "the bell entry needs migration 20261119200000"
          : inAppError.message;
      } else {
        inAppInserted = true;
      }
    } catch (e) {
      console.error("[PayoutReceipt] bell entry failed:", e);
      inAppReason = String(e);
    }

    // Stamp last, and only when the mail actually went out: a failed send must
    // not look like a delivered receipt, and two concurrent sends must not
    // overwrite each other.
    step = "stamp";
    if (emailSent && hasStampColumn) {
      const { error: stampError } = await supabase
        .from("seller_payouts")
        .update({ payout_notice_sent_at: new Date().toISOString() })
        .eq("id", payout.id)
        .is("payout_notice_sent_at", null);
      if (stampError) {
        console.warn("[PayoutReceipt] stamp skipped:", stampError.message);
      }
    } else if (!hasStampColumn) {
      console.warn(
        "[PayoutReceipt] no stamp column — migration 20261119190000 not applied; duplicate sends are possible.",
      );
    }

    console.log(
      `[PayoutReceipt] payout ${payout.id}: email=${
        emailSent ? email : emailReason
      }, push=${pushSuccess}/${devices} device(s)`,
    );
    return json({
      ok: emailSent || pushSuccess > 0 || inAppInserted,
      to: emailSent ? email : null,
      email: { sent: emailSent, reason: emailReason },
      push: {
        success_count: pushSuccess,
        devices,
        error: pushError,
      },
      in_app: { inserted: inAppInserted, reason: inAppReason },
    });
  } catch (error) {
    console.error("[PayoutReceipt] Error:", error);
    return json({ error: String(error), step }, 500);
  }
});
