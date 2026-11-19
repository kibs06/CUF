// supabase/functions/send-order-receipt/index.ts
//
// Supabase Edge Function: email a customer their receipt when an online order
// is paid — no cashier, no phone, no Gmail composer.
//
// Called by: the pg_net trigger `trg_request_order_receipt` (migration
// 20261119110000), which fires when an online order's payment_status becomes
// 'paid'. A staff member can also invoke it for one order (the same JWT check
// applies, so it is a server-side call, not an app button).
//
// What it sends: the same A5 slip the POS prints (store header, receipt code,
// items, money breakdown, payment method, GCash reference) as a PDF
// attachment, plus an HTML body with the same facts for clients that show the
// message inline.
//
// Delivery: Gmail SMTP through the shared `_shared/smtp.ts` client — the same
// channel send-approval-email and send-lockout-email already use. No third
// party provider, no domain verification.
//
// Secrets required (already set for the other mail senders):
//   - GMAIL_SENDER        the app's Gmail address
//   - GMAIL_APP_PASSWORD  a 16-char App Password for it
//
// Authorization: two callers, one rule. The seller's app invokes it with the
// seller's own session — the same way the forgot-password and lockout mails are
// sent — and the function verifies that session, then requires the caller to
// own the order's store (or be an admin). The pg_net trigger presents the
// service-role key instead, which is trusted outright. The anon key is also a
// JWT, so `verify_jwt` alone proves nothing and the checks below are the real
// gate.
//
// Idempotent: an order that already carries `receipt_emailed_at` is skipped
// unless the caller passes `force: true`. That is what stops a retried trigger
// (or a curious caller) from mailing the customer twice.
//
// Failure is recorded, not lost (migration 20261119120000): every failed
// attempt calls `record_order_receipt_failure`, which counts it, keeps the
// reason and schedules the next try (5 min, 15 min, 1 h, 6 h). The SQL sweep
// `retry_order_receipt_emails` (pg_cron every five minutes, plus the payment
// trigger) picks it back up, so a Gmail outage delays the customer's receipt
// instead of cancelling it. A send never writes the failure itself, and the
// success stamp is still the only thing that stops a retry.
//
// Deploy: supabase functions deploy send-order-receipt
// (verify_jwt stays on — see config.toml.)

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SmtpClient } from "../_shared/smtp.ts";
import {
  buildOrderReceiptPdf,
  type ReceiptData,
  type ReceiptLine,
} from "./receipt_pdf.ts";
import {
  receiptFilename,
  receiptHtml,
  receiptSubject,
  receiptText,
} from "./receipt_email.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface ReceiptRequest {
  order_id?: string;
  /** Build the receipt but send nothing — used to check the PDF locally. */
  dry_run?: boolean;
  /** Re-send even though receipt_emailed_at is already set. */
  force?: boolean;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * The role claim of the bearer token. Only the service-role key may ask for a
 * receipt: the trigger sends it, and no app client does.
 */
/** The bearer token as sent, without the scheme. */
function bearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  return token || null;
}

function bearerRole(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(padded));
    return typeof payload?.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // The trigger identifies itself with the service-role key; a seller arrives
  // with their own session token.
  const token = bearerToken(req);
  const isServiceCall = bearerRole(req) === "service_role";
  if (!isServiceCall && !token) {
    return json({ error: "Missing bearer token" }, 401);
  }

  let payload: ReceiptRequest;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const orderId = (payload.order_id ?? "").trim();
  if (!orderId) {
    return json({ error: "Missing required field: order_id" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // Who is asking. A service-role call is the trigger (already authorized by the
  // dispatcher's own claim); anyone else must prove a real session here rather
  // than being trusted from an unverified token.
  let callerId: string | null = null;
  if (!isServiceCall) {
    const { data: caller, error: callerError } = await supabase.auth.getUser(
      token!,
    );
    if (callerError || !caller?.user) {
      return json({ error: "Invalid or expired session" }, 401);
    }
    callerId = caller.user.id;
  }

  /**
   * Books a failed attempt so the retry sweep can find the order again. The
   * error is kept verbatim (truncated) — it is the only thing that tells the
   * owner whether Gmail was down, the password rotated or the address bounced.
   * Never allowed to throw: a failure to record must not hide the failure.
   */
  const recordFailure = async (
    reason: string,
    retryable: boolean = true,
  ): Promise<void> => {
    try {
      const { error } = await supabase.rpc("record_order_receipt_failure", {
        p_order_id: orderId,
        p_error: reason.slice(0, 500),
        p_retryable: retryable,
      });
      if (error) {
        console.warn(
          "[OrderReceipt] Could not record the failed attempt:",
          error.message,
        );
      }
    } catch (e) {
      console.warn("[OrderReceipt] Could not record the failed attempt:", e);
    }
  };

  /**
   * Stamps the receipt and clears the retry state. Falls back to the plain
   * column update on a server that predates migration 20261119120000, so a
   * deployed function keeps working while that file is unapplied.
   */
  const recordSuccess = async (to: string): Promise<void> => {
    const stampDirectly = async () => {
      try {
        const { error } = await supabase
          .from("orders")
          .update({
            receipt_emailed_at: new Date().toISOString(),
            receipt_email_to: to,
          })
          .eq("id", orderId);
        if (error) {
          console.warn(
            "[OrderReceipt] Could not stamp receipt_emailed_at:",
            error.message,
          );
        }
      } catch (e) {
        console.warn("[OrderReceipt] Could not stamp receipt_emailed_at:", e);
      }
    };

    try {
      const { error } = await supabase.rpc("record_order_receipt_success", {
        p_order_id: orderId,
        p_to: to,
      });
      if (!error) return;
      // PGRST202 = no such function: the retry migration is not applied yet.
      if (
        error.code !== "PGRST202" &&
        !/does not exist|could not find/i.test(error.message)
      ) {
        console.warn("[OrderReceipt] Could not stamp the receipt:", error.message);
        return;
      }
      console.warn(
        "[OrderReceipt] Retry schema missing; stamping the order directly.",
      );
    } catch (e) {
      console.warn("[OrderReceipt] Could not stamp the receipt:", e);
    }
    await stampDirectly();
  };

  // ── the order ───────────────────────────────────────────────────
  const { data: order, error: orderError } = await supabase
    .from("orders")
    .select(
      "id, order_code, customer_id, store_id, status, payment_status, " +
        "payment_method, total_amount, subtotal_amount, discount_amount, " +
        "voucher_code, gcash_reference_number, created_at, fulfillment, " +
        "source, amount_tendered, change_amount, receipt_emailed_at",
    )
    .eq("id", orderId)
    .maybeSingle();

  if (orderError) {
    console.error("[OrderReceipt] Order lookup failed:", orderError.message);
    return json({ error: "Order lookup failed", detail: orderError.message }, 500);
  }
  if (!order) {
    return json({ error: `Order ${orderId} does not exist` }, 404);
  }

  // A seller may only email the customer of their own store. Admins keep the
  // same access they have everywhere else in the portal.
  if (callerId) {
    const { data: storeOwner } = await supabase
      .from("stores")
      .select("owner_id")
      .eq("id", order.store_id)
      .maybeSingle();
    let allowed = (storeOwner?.owner_id as string | undefined) === callerId;
    if (!allowed) {
      const { data: callerProfile } = await supabase
        .from("profiles")
        .select("role")
        .eq("id", callerId)
        .maybeSingle();
      allowed = callerProfile?.role === "admin";
    }
    if (!allowed) {
      return json(
        { error: "Only the store that made this sale can email its receipt" },
        403,
      );
    }
  }

  if (order.receipt_emailed_at && !payload.force) {
    return json({
      sent: false,
      reason: "already_sent",
      order_code: order.order_code,
    });
  }

  // customer_email arrives with migration 20261119110000. Read it on its own so
  // an un-migrated server only loses the override, not the whole receipt.
  let overrideEmail: string | null = null;
  try {
    const { data: emailRow } = await supabase
      .from("orders")
      .select("customer_email")
      .eq("id", orderId)
      .maybeSingle();
    overrideEmail = (emailRow as { customer_email?: string | null } | null)
      ?.customer_email ?? null;
  } catch (_) {
    overrideEmail = null;
  }

  const [{ data: store }, { data: customer }] = await Promise.all([
    supabase
      .from("stores")
      .select("name, location, owner_id")
      .eq("id", order.store_id)
      .maybeSingle(),
    order.customer_id
      ? supabase
        .from("profiles")
        .select("full_name, email")
        .eq("id", order.customer_id)
        .maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  const address = (overrideEmail ?? customer?.email ?? "").trim();
  if (!address) {
    return json({
      sent: false,
      reason: "no_email",
      order_code: order.order_code,
    });
  }

  // ── line items, with product names ──────────────────────────────
  const { data: items } = await supabase
    .from("order_items")
    .select("product_id, size, quantity, unit_price")
    .eq("order_id", orderId);

  const productIds = (items ?? [])
    .map((row: { product_id?: string }) => row.product_id)
    .filter((id): id is string => !!id);

  const names = new Map<string, string>();
  if (productIds.length > 0) {
    const { data: products } = await supabase
      .from("products")
      .select("id, name")
      .in("id", productIds);
    for (const product of products ?? []) {
      names.set(product.id as string, (product.name as string) ?? "");
    }
  }

  const lines: ReceiptLine[] = (items ?? []).map((row: Record<string, unknown>) => ({
    name: names.get(row.product_id as string) || "Item",
    size: (row.size ?? "").toString(),
    quantity: Number(row.quantity ?? 0),
    unitPrice: Number(row.unit_price ?? 0),
  }));

  // A till sale's receipt names the cashier, exactly as the printed slip does.
  // The order row carries no cashier column, so the store owner stands in —
  // the same name the POS receipt on screen shows.
  const isPosSale = (order.source ?? "").toString().toLowerCase() === "pos";
  let cashier = "";
  if (isPosSale && store?.owner_id) {
    const { data: ownerProfile } = await supabase
      .from("profiles")
      .select("full_name")
      .eq("id", store.owner_id as string)
      .maybeSingle();
    cashier = (ownerProfile?.full_name as string) ?? "";
  }

  // Only a till sale shows the cash lines, and only when money was actually
  // handed over: the column defaults to 0 on rows that never had a till.
  const tenderedRaw = isPosSale && order.amount_tendered != null
    ? Number(order.amount_tendered)
    : null;
  const amountTendered = tenderedRaw != null && tenderedRaw > 0
    ? tenderedRaw
    : null;
  const changeAmount = amountTendered != null && order.change_amount != null
    ? Number(order.change_amount)
    : null;

  const total = Number(order.total_amount ?? 0);
  const subtotal = order.subtotal_amount == null
    ? null
    : Number(order.subtotal_amount);
  const discount = order.discount_amount == null
    ? null
    : Number(order.discount_amount);

  const data: ReceiptData = {
    store: {
      name: (store?.name as string) ?? "CUFMAI",
      location: (store?.location as string) ?? "",
    },
    order: {
      orderCode:
        (order.order_code as string) ??
        String(order.id).slice(0, 8).toUpperCase(),
      createdAt: new Date(order.created_at as string),
      paymentMethod: (order.payment_method as string) ?? "",
      total,
      subtotal,
      discount,
      voucherCode: (order.voucher_code as string) ?? null,
      gcashReference: (order.gcash_reference_number as string) ?? null,
      fulfillment: (order.fulfillment as string) ?? "",
      source: isPosSale ? "pos" : "online",
      cashier,
      amountTendered,
      changeAmount,
    },
    lines,
    customerName: (customer?.full_name as string) ?? "",
    customerEmail: address,
  };

  // ── the receipt itself ──────────────────────────────────────────
  let pdf: Uint8Array;
  try {
    pdf = await buildOrderReceiptPdf(data);
  } catch (e) {
    console.error("[OrderReceipt] PDF build failed:", e);
    await recordFailure(
      `PDF build failed: ${e instanceof Error ? e.message : String(e)}`,
      isServiceCall,
    );
    return json({ error: "Could not build the receipt PDF" }, 500);
  }

  const subject = receiptSubject(data);
  const html = receiptHtml(data);

  if (payload.dry_run) {
    return json({
      sent: false,
      reason: "dry_run",
      to: address,
      order_code: data.order.orderCode,
      subject,
      pdf_bytes: pdf.byteLength,
      html_bytes: new TextEncoder().encode(html).byteLength,
      text_preview: receiptText(data).slice(0, 400),
      pdf_base64: btoa(String.fromCharCode(...pdf)),
    });
  }

  const gmailSender = Deno.env.get("GMAIL_SENDER");
  const gmailAppPassword = Deno.env.get("GMAIL_APP_PASSWORD");
  if (!gmailSender || !gmailAppPassword) {
    console.error("[OrderReceipt] Missing GMAIL_SENDER / GMAIL_APP_PASSWORD");
    await recordFailure(
      "GMAIL_SENDER / GMAIL_APP_PASSWORD are not configured for send-order-receipt",
      isServiceCall,
    );
    return json({
      sent: false,
      reason: "email_not_configured",
      order_code: data.order.orderCode,
    }, 500);
  }

  // One send at a time per order, whichever caller asked. The lease is the same
  // `receipt_email_sending_since` the SQL dispatcher takes, so a seller's tap
  // and a trigger dispatch cannot both mail the customer. A service-role call
  // already holds that lease (the dispatcher took it), so it is skipped here.
  if (!isServiceCall) {
    try {
      const staleBefore = new Date(Date.now() - 5 * 60 * 1000).toISOString();
      const { data: claimedRows, error: claimError } = await supabase
        .from("orders")
        .update({ receipt_email_sending_since: new Date().toISOString() })
        .eq("id", orderId)
        .is("receipt_emailed_at", null)
        .or(
          `receipt_email_sending_since.is.null,receipt_email_sending_since.lt.${staleBefore}`,
        )
        .select("id");
      if (!claimError && (!claimedRows || claimedRows.length === 0)) {
        return json({
          sent: false,
          reason: "in_flight",
          order_code: order.order_code,
        }, 409);
      }
    } catch (_) {
      // A server without the lease column (pre-20261119120000) sends anyway.
    }
  }

  const smtp = new SmtpClient();
  try {
    await smtp.connectTLS({
      hostname: "smtp.gmail.com",
      port: 465,
      username: gmailSender,
      password: gmailAppPassword,
    });
    await smtp.send({
      from: gmailSender,
      to: address,
      subject,
      html,
      attachments: [{
        filename: receiptFilename(data),
        contentType: "application/pdf",
        bytes: pdf,
      }],
    });
  } catch (e) {
    console.error("[OrderReceipt] SMTP send failed:", e);
    const detail = e instanceof Error ? e.message : String(e);
    // Recorded before answering. A trigger dispatch leaves the backoff armed
    // for the sweep; a seller's tap does not, because nothing would run that
    // sweep in a project without the Vault entries — the order shows the error
    // and the button sends again.
    await recordFailure(`SMTP send failed: ${detail}`, isServiceCall);
    return json({
      sent: false,
      reason: "smtp_failed",
      detail,
      order_code: data.order.orderCode,
    }, 502);
  } finally {
    await smtp.close();
  }

  // The stamp is what makes a retry a no-op. Losing it (an un-migrated server)
  // must not undo a send that already happened, so the failure is logged only.
  await recordSuccess(address);

  return json({
    sent: true,
    to: address,
    order_code: data.order.orderCode,
    pdf_bytes: pdf.byteLength,
  });
});
