// supabase/functions/send-replacement-notice/index.ts
//
// Supabase Edge Function: email a customer that the store approved a product
// replacement for their order.
//
// Called by: the seller app, right after `resolveReturn(approve: true)`
// succeeds — fire-and-forget, like the receipt mailer. The in-app notice and
// the push already come from `updateOrderStatus`; this covers the inbox, so a
// customer who is not in the app still learns the swap was approved.
//
// Delivery: Gmail SMTP through `_shared/smtp.ts` — the same channel as the
// receipt, approval and lockout mails. No third-party provider.
//
// Secrets: GMAIL_SENDER, GMAIL_APP_PASSWORD (already set for the other
// senders); SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are provided by the
// platform.
//
// Authorization: the caller's JWT must belong to the store that owns the
// order, or to an admin. The service-role key is trusted outright (server-side
// callers). `verify_jwt` alone proves nothing — the anon key is also a JWT —
// so the ownership check below is the real gate.
//
// Idempotent: an order that already carries `replacement_notice_emailed_at` is
// skipped unless `force: true`, so a retried call cannot mail twice.
//
// Deploy: supabase functions deploy send-replacement-notice

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SmtpClient } from "../_shared/smtp.ts";
import { sendPushToUser } from "../_shared/push.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

/// The columns this function reads off `orders`. Declared here because the
/// select list is built at runtime (the stamp column is optional), which leaves
/// the client's inferred row type empty.
interface NoticeOrderRow {
  id: string;
  store_id: string;
  customer_id: string;
  replacement_method?: string | null;
  replacement_tracking_number?: string | null;
  replacement_shipping_fee?: number | null;
  replacement_fee_status?: string | null;
  replacement_notice_emailed_at?: string | null;
  shipping_address?: {
    barangay?: string;
    city_municipality?: string;
  } | null;
  delivery_address?: string | null;
  customer_email?: string | null;
}

interface NoticeRequest {
  order_id?: string;
  /** `true` answers a secrets/boot check instead of sending anything. */
  ping?: boolean;
  /** Re-send even though the notice stamp is already set. */
  force?: boolean;
  /** Build the message but send nothing. */
  dry_run?: boolean;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const money = (value: number) =>
  "₱" + value.toFixed(2).replace(/\.00$/, "");

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Which stage failed, reported in the 500 body — the seller's app shows it.
  let step = "parse";
  try {
    const payload = (await req.json().catch(() => ({}))) as NoticeRequest;
    const orderId = (payload.order_id ?? "").trim();
    if (!orderId && payload.ping) {
      // Boot check: proves the function started and its secrets resolve,
      // without touching an order.
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
    if (!orderId) return json({ error: "order_id is required" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const gmailSender = Deno.env.get("GMAIL_SENDER") ?? "";
    const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD") ?? "";
    if (!gmailSender || !gmailAppPassword) {
      return json({ error: "GMAIL_SENDER / GMAIL_APP_PASSWORD are not set" }, 500);
    }

    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });

    // ── Who is asking ───────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    const isServiceCall = token.length > 0 && token === serviceKey;

    let callerId: string | null = null;
    if (!isServiceCall) {
      const { data: caller, error: callerError } = await supabase.auth.getUser(
        token,
      );
      if (callerError || !caller?.user) {
        return json({ error: "Not authenticated" }, 401);
      }
      callerId = caller.user.id;
    }

    // A client that carries the CALLER'S token — RLS and `public.is_admin()`
    // evaluate against their session. The service-role client above has no
    // session, so `is_admin()` there is always false and every admin would be
    // rejected.
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const userClient = isServiceCall || !anonKey
      ? null
      : createClient(supabaseUrl, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: { Authorization: `Bearer ${token}` } },
      });

    step = "order_read";
    // `select *`: naming optional columns (replacement_*, customer_email, …)
    // makes the WHOLE read 500 on a database that hasn't applied the latest
    // migration, while the app's own approve path tolerates that lag. Every
    // field below is read defensively instead.
    //
    // Callers read the order through their OWN client, so RLS (store owner or
    // admin) decides whether the row is visible at all. The service-role
    // client is used only for server-side callers.
    const reader = userClient ?? supabase;
    const { data: orderData, error: orderError } = await reader
      .from("orders")
      .select("*")
      .eq("id", orderId)
      .maybeSingle();

    const order = orderData as unknown as NoticeOrderRow | null;
    // The stamp column arrives with 20261119160000; its absence only means
    // there is nothing to dedupe on.
    const hasStampColumn = order !== null &&
      Object.prototype.hasOwnProperty.call(order, "replacement_notice_emailed_at");

    if (orderError) {
      return json({ error: orderError.message, step: "order_read" }, 500);
    }
    if (!order) return json({ error: "Order not found" }, 404);

    // Store details come from the service client (name/location are needed for
    // the copy); authorization is the check below, not the read.
    const { data: store } = await supabase
      .from("stores")
      .select("*")
      .eq("id", order.store_id)
      .maybeSingle();

    if (!isServiceCall) {
      const ownsStore = store?.owner_id === callerId;
      let isAdmin = false;
      if (!ownsStore) {
        // Caller-scoped client: `is_admin()` reads auth.uid() from this JWT.
        const { data: isAdminData, error: adminError } = userClient
          ? await userClient.rpc("is_admin")
          : { data: null, error: null };
        if (adminError) {
          console.warn(
            "[ReplacementNotice] is_admin() unavailable:",
            adminError.message,
          );
        }
        isAdmin = isAdminData === true;
      }
      if (!ownsStore && !isAdmin) {
        return json({ error: "Only the store can send this notice" }, 403);
      }
    }

    if (order.replacement_notice_emailed_at && !payload.force) {
      return json({ ok: true, skipped: "already_sent" });
    }

    step = "customer_read";
    // ── Customer + items ────────────────────────────────────────────
    // How many phones this customer has registered — reported to the seller so
    // "no push arrived" can be told apart from "the customer has no device".
    const { count: deviceCount } = await supabase
      .from("device_tokens")
      .select("fcm_token", { count: "exact", head: true })
      .eq("customer_id", order.customer_id);

    const { data: customer } = await supabase
      .from("profiles")
      .select("full_name, email")
      .eq("id", order.customer_id)
      .maybeSingle();

    // The address the till recorded for this order wins (it is the one the
    // customer typed at checkout); then the account email; then the auth user.
    // `customer_email` comes from the row we already read, so a database
    // without that column simply skips it.
    const orderEmail = (order.customer_email ?? "").trim();

    let email = orderEmail ||
      ((customer?.email as string | undefined) ?? "").trim();
    if (!email) {
      // Last resort: the address on the auth account. A customer can sign up
      // with a phone and still have an email that never reached `profiles`.
      try {
        const { data: authUser } = await supabase.auth.admin.getUserById(
          order.customer_id,
        );
        email = (authUser?.user?.email ?? "").trim();
      } catch (e) {
        console.warn("[ReplacementNotice] auth email lookup failed:", e);
      }
    }

    const name = ((customer?.full_name as string | undefined) ?? "").trim() ||
      "there";

    const { data: items } = await supabase
      .from("order_items")
      .select("quantity, unit_price, products(name)")
      .eq("order_id", orderId);

    const itemLines = (items ?? []).map((row) => {
      const product = row.products as { name?: string } | null;
      const qty = Number(row.quantity ?? 1);
      return `${qty}× ${product?.name ?? "Item"}`;
    });

    const shortId = orderId.slice(0, 8);
    const tri = (order.replacement_tracking_number as string | undefined) ??
      `CUF-RPL-${shortId.toUpperCase()}`;
    const method = (order.replacement_method as string | undefined) ?? "";
    const fee = Number(order.replacement_shipping_fee ?? 0);
    const storeName = (store?.name as string | undefined) ?? "the store";
    const storeLocation = (store?.location as string | undefined) ?? "";

    const address = order.shipping_address as
      | { barangay?: string; city_municipality?: string }
      | null;
    const addressLabel = [address?.barangay, address?.city_municipality]
      .filter(Boolean)
      .join(", ") || (order.delivery_address as string | undefined) || "";

    const deliveryBlock = method === "shipped"
      ? `<p>Your replacement will be <strong>delivered</strong>${
        addressLabel ? ` to ${addressLabel}` : ""
      }. Replacement reference: <strong>${tri}</strong>.</p>` +
        (fee > 0
          ? `<p>A fixed <strong>${money(fee)}</strong> replacement shipping fee applies inside Carcar City — pay it in <strong>cash to the courier</strong> when the replacement arrives. Nothing to send in advance.</p>`
          : "")
      : `<p>Bring the pair to <strong>${storeName}</strong>${
        storeLocation ? ` (${storeLocation})` : ""
      } and collect your replacement there after inspection. Addresses outside Carcar City are collected in store — no shipping.</p>`;

    const subject = `Your CUFMAI replacement — Order #${shortId}`;
    const html = `<!doctype html>
<html>
<body style="margin:0;padding:0;background:#F5F0E6;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F5F0E6;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #D9D0C7;">
        <tr><td style="background:#4F6B35;padding:28px 32px;">
          <h1 style="margin:0;color:#FFFFFF;font-size:22px;">Your replacement is approved</h1>
        </td></tr>
        <tr><td style="padding:28px 32px;color:#3B2314;font-size:15px;line-height:1.6;">
          <p>Hi ${name},</p>
          <p><strong>${storeName}</strong> approved a product replacement for your order <strong>#${shortId}</strong>. Approved returns are made good with a new pair — never a cash refund.</p>
          ${itemLines.length ? `<p><strong>Item${itemLines.length > 1 ? "s" : ""}:</strong><br>${itemLines.join("<br>")}</p>` : ""}
          ${deliveryBlock}
          <p>You can follow this on the order's tracking screen in the app, where the replacement reference and its status are shown.</p>
          <p style="margin-top:24px;color:#6B5C4E;font-size:13px;">Questions? Reach out to the store through the app.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;

    if (payload.dry_run) {
      return json({ ok: true, dry_run: true, to: email, subject, html });
    }

    step = "email";
    // ── Email ───────────────────────────────────────────────────────
    // Each channel runs on its own: a missing inbox must not stop the push,
    // and a mail failure must not hide a delivered notification.
    let emailSent = false;
    let emailReason: string | null = null;
    if (!email) {
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
        console.error("[ReplacementNotice] SMTP send failed:", e);
        emailReason = "smtp_failed";
      } finally {
        try {
          await smtp.close();
        } catch (_) {
          // The connection may never have opened; nothing left to close.
        }
      }
    }

    step = "push";
    // ── Push ────────────────────────────────────────────────────────
    // `success_count` is FCM's own answer (devices that accepted the message),
    // not a token count — the seller's snackbar reports exactly this number.
    let pushSuccess = 0;
    let pushError: string | null = null;
    try {
      const push = await sendPushToUser(
        supabase,
        order.customer_id,
        {
          title: "Replacement approved",
          body: `Order #${shortId} — your product is being replaced. Tap to see ` +
            `whether it ships or you collect it in store.`,
        },
        { type: "returns", referenceId: orderId, screen: "order_tracking" },
      );
      pushSuccess = push.successCount;
    } catch (e) {
      console.error("[ReplacementNotice] push failed:", e);
      pushError = String(e);
    }

    step = "stamp";
    // Stamp last: a failed send must not look like a delivered notice. Only
    // stamp when the mail actually went out, the read had the column, and it is
    // still empty — two concurrent sends must not overwrite each other.
    if (emailSent && hasStampColumn) {
      const { error: stampError } = await supabase
        .from("orders")
        .update({ replacement_notice_emailed_at: new Date().toISOString() })
        .eq("id", orderId)
        .is("replacement_notice_emailed_at", null);
      if (stampError) {
        console.warn("[ReplacementNotice] stamp skipped:", stampError.message);
      }
    } else if (!hasStampColumn) {
      console.warn(
        "[ReplacementNotice] no stamp column — migration 20261119160000 not applied; duplicate sends are possible.",
      );
    }

    console.log(
      `[ReplacementNotice] order ${orderId}: email=${emailSent ? email : emailReason}, ` +
        `push=${pushSuccess}/${deviceCount ?? 0} device(s)`,
    );
    return json({
      ok: emailSent || pushSuccess > 0,
      sent_to: emailSent ? email : null,
      email: { sent: emailSent, reason: emailReason },
      push: {
        success_count: pushSuccess,
        devices: deviceCount ?? 0,
        error: pushError,
      },
    });
  } catch (error) {
    console.error("[ReplacementNotice] Error:", error);
    return json({ error: String(error), step }, 500);
  }
});
