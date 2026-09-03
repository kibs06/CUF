// ══════════════════════════════════════════════════════════════════
// gcash-webhook — PayMongo webhook for online GCash payments
//
// Public endpoint (deploy with --no-verify-jwt; PayMongo calls it with
// a signature, not a Supabase JWT).
//
// HARD REQUIREMENTS (task brief §3 — all enforced here):
//   • Signature verification is MANDATORY on every request — the
//     Paymongo-Signature header is HMAC-verified before ANY DB write.
//     There is no bypass flag anywhere.
//   • Idempotent: payment_webhook_events.paymongo_event_id is UNIQUE.
//     First INSERT wins; duplicate deliveries are no-ops. A delivery
//     that previously failed processing (status='failed') is re-claimed
//     so PayMongo retries can actually recover.
//   • Amount integrity: the charged amount (centavos) must equal
//     payment_intents.amount (order total + Model B fee, computed
//     server-side at creation). Mismatch → payment_conflict, never a
//     silent accept.
//   • The order is finalized (order_items inserted → stock decremented
//     by the existing trigger, status → pending) ONLY on a confirmed
//     paid event.
//   • A paid order is NEVER deleted. Stock/amount/late-payment problems
//     land in status='payment_conflict' for manual review.
//
// Events handled:
//   • checkout_session.payment.paid  (primary — Checkout Sessions API)
//   • payment.paid / payment.failed  (defensive — same webhook may be
//     subscribed to both; the idempotency gate + state guards make the
//     second arrival a no-op)
//   Unknown event types are logged (append-only) and acknowledged —
//   never silently ignored. Expiry/timeout is handled by the DB sweep
//   (payment_intents.expires_at) and the app-side poll, not this hook.
//
// Env: PAYMONGO_WEBHOOK_SECRET (required, whsk_…), SUPABASE_URL,
//      SUPABASE_SERVICE_ROLE_KEY
// ══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, rateLimitedResponse } from "../_shared/rate_limit.ts";
import {
  verifyWebhookSignature,
  parseWebhookEvent,
  resourceAttrs,
  extractPaymentId,
  extractPaymentIntentId,
  extractAmountCents,
  extractPaymongoFeePesos,
  extractGcashReference,
  fetchCheckoutSessionById,
  normalizeSize,
  resolveInventorySize,
} from "../_shared/paymongo.ts";
import { sendPushToUser } from "../_shared/push.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

// Row shapes for the tables we touch. The repo has no generated DB types,
// so supabase-js infers `null` for maybeSingle() — these explicit shapes
// keep every property access type-safe and self-documenting.
interface PiRow {
  id: string;
  order_id: string;
  amount: number;
  status: string;
  checkout_session_id?: string | null;
  paymongo_payment_intent_id?: string | null;
}

interface OrderRow {
  id: string;
  status: string;
  payment_status: string;
  total_amount: number;
  items_snapshot: any[] | null;
  cancellation_reason: string | null;
  customer_id: string;
  store_id: string;
  gcash_fee_amount?: number;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // T6: additional per-IP layer on top of the HMAC signature check.
  // 600/min per IP never trips PayMongo's real deliveries/retries but
  // caps scripted hammering that would otherwise burn CPU parsing junk.
  const rl = await checkRateLimit(req, "gcash-webhook", 600);
  if (!rl.allowed) return rateLimitedResponse(rl, corsHeaders);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const webhookSecret = Deno.env.get("PAYMONGO_WEBHOOK_SECRET") ?? "";
  const supabase = createClient(supabaseUrl, serviceKey);

  if (!webhookSecret) {
    console.error("[WEBHOOK] PAYMONGO_WEBHOOK_SECRET is not configured — refusing to process.");
    return json(500, { error: "server not configured" });
  }

  // ── 1. Signature verification (mandatory, no bypass) ────────────
  const rawBody = await req.text();
  const signatureHeader = req.headers.get("Paymongo-Signature") ?? "";

  let event: ReturnType<typeof parseWebhookEvent>;
  try {
    event = parseWebhookEvent(rawBody);
  } catch {
    return json(400, { error: "unparseable body" });
  }

  if (!(await verifyWebhookSignature(rawBody, signatureHeader, webhookSecret))) {
    console.error("[WEBHOOK] Invalid signature — rejecting");
    // Audit the rejection. The key is SYNTHETIC (never the real event id)
    // so a failed/forged delivery can never occupy the idempotency key of
    // a legitimate retry of the same event.
    // Spam cap: log at most 100 rejections per hour so an attacker
    // hammering bad signatures can't fill the audit table forever.
    try {
      const { count } = await (supabase
        .from("payment_webhook_events")
        .select("id", { count: "exact", head: true })
        .eq("status", "rejected_signature")
        .gte("received_at", new Date(Date.now() - 3600_000).toISOString()) as any);
      if ((count ?? 0) < 100) {
        await supabase.from("payment_webhook_events").insert({
          paymongo_event_id: `rej-${crypto.randomUUID()}`,
          event_type: event.type || "unknown",
          status: "rejected_signature",
          redacted_payload: event.redacted,
        });
      }
    } catch (e) {
      console.error("[WEBHOOK] could not log rejection:", (e as any)?.message ?? e);
    }
    return json(401, { error: "invalid signature" });
  }

  // ── 2. Idempotency gate: first INSERT wins; 'failed' rows re-claim ─
  // (the insert chain is cast to `any` for the repo's untyped schema —
  //  runtime behavior is identical to the typed form)
  const { data: claimed } = await (supabase
    .from("payment_webhook_events")
    .insert({
      paymongo_event_id: event.id,
      event_type: event.type,
      status: "processing",
      livemode: event.livemode,
      redacted_payload: event.redacted,
    }) as any)
    .onConflict("paymongo_event_id")
    .select("id, status")
    .maybeSingle();

  let proceed = !!claimed;
  if (!claimed) {
    const { data: existing } = await supabase
      .from("payment_webhook_events")
      .select("id, status")
      .eq("paymongo_event_id", event.id)
      .maybeSingle();
    if (existing && existing.status === "failed") {
      // Previous attempt crashed mid-processing — allow the retry to
      // reprocess. State guards below make reprocessing safe.
      await supabase
        .from("payment_webhook_events")
        .update({ status: "processing" })
        .eq("id", existing.id);
      proceed = true;
      console.log("[WEBHOOK] Re-claiming previously failed event:", event.id);
    }
  }
  if (!proceed) {
    // Duplicate delivery (PayMongo retries) — already processed.
    console.log("[WEBHOOK] Duplicate event, ignoring:", event.id);
    return json(200, { ok: true, duplicate: true });
  }

  const markEvent = async (
    status: string,
    extra: Record<string, unknown> = {},
  ) => {
    await supabase
      .from("payment_webhook_events")
      .update({ status, processed_at: new Date().toISOString(), ...extra })
      .eq("paymongo_event_id", event.id);
  };

  // ── 3. Processing. Unexpected errors mark the event 'failed' and
  //    return 500 so PayMongo retries (the re-claim above lets them in).
  // auditCtx accumulates lookup context for the outer catch (retry
  // fidelity) and must live OUTSIDE the try for the catch to see it.
  const auditCtx: Record<string, unknown> = {};
  try {
    const attrs = resourceAttrs(event);
    let paymentId: string = extractPaymentId(event);
    let paymentIntentId: string = extractPaymentIntentId(event);
    let chargedCents: number = extractAmountCents(event);
    const checkoutSessionId: string =
      event.data.type === "checkout_session" ? event.data.id : "";

    // ── Fallback enrichment: if a checkout_session event doesn't embed
    //    the payment/payment_intent (some payloads omit them), retrieve
    //    the session server-side — PayMongo's documented rollback path.
    //    If retrieval fails, keep going; the amount check below will fail
    //    loudly (payment_conflict) instead of silently accepting. ─────
    if (event.data.type === "checkout_session" && checkoutSessionId &&
        (!paymentId || !paymentIntentId || !chargedCents)) {
      try {
        const session = await fetchCheckoutSessionById(checkoutSessionId);
        const first: any = session.payments?.[0];
        if (!paymentId && first?.id) paymentId = first.id as string;
        if (!paymentIntentId && session.paymentIntentId) {
          paymentIntentId = session.paymentIntentId;
        }
        if (!chargedCents && first?.attributes?.amount) {
          chargedCents = Number(first.attributes.amount);
        }
        console.log("[WEBHOOK] Enriched checkout session", checkoutSessionId);
      } catch (e) {
        console.error(
          "[WEBHOOK] checkout session retrieval failed (fallback):",
          (e as any)?.message ?? e,
        );
      }
    }

    if (paymentIntentId) auditCtx.payment_intent_id = paymentIntentId;
    if (checkoutSessionId) auditCtx.checkout_session_id = checkoutSessionId;

    // ── Admin-view enrichment: persist PayMongo's ACTUAL fee and the GCash
    //    reference for this payment (migration 20260810000000). Only stored
    //    when present — never a fabricated estimate; on retries the spread
    //    of an empty object leaves previously stored values untouched. ─────
    const paymongoFeeAmount = extractPaymongoFeePesos(event);
    const gcashReference = extractGcashReference(event);
    const feeFields = {
      ...(paymongoFeeAmount != null ? { paymongo_fee_amount: paymongoFeeAmount } : {}),
      ...(gcashReference != null ? { gcash_reference_number: gcashReference } : {}),
    };

    // ── Locate the payment_intents row: by checkout session id first,
    //    then by the (possibly backfilled) PayMongo payment intent id. ─
    let query = supabase
      .from("payment_intents")
      .select("id, order_id, amount, status");
    if (checkoutSessionId) {
      query = query.eq("checkout_session_id", checkoutSessionId);
    } else if (paymentIntentId) {
      query = query.eq("paymongo_payment_intent_id", paymentIntentId);
    } else {
      console.error("[WEBHOOK] No checkout session or payment intent id on event", event.id, event.type);
      await markEvent("ignored_unknown");
      return json(200, { ok: true });
    }
    const { data: rawPi, error: piErr } = await query.maybeSingle();
    let pi = (rawPi as PiRow | null);
    if (piErr) {
      console.error("[WEBHOOK] payment_intents lookup failed:", piErr.message);
      await markEvent("failed", { payment_intent_id: paymentIntentId || null });
      return json(500, { error: "lookup failed" }); // retryable
    }
    if (!pi) {
      // If we only had the cs_ id, try the payment intent id too.
      if (checkoutSessionId && paymentIntentId) {
        const { data: byPi } = await supabase
          .from("payment_intents")
          .select("id, order_id, amount, status")
          .eq("paymongo_payment_intent_id", paymentIntentId)
          .maybeSingle();
        const winnerPi = (byPi as PiRow | null);
        if (winnerPi) {
          // Backfill the cs_ reference for future events.
          await supabase
            .from("payment_intents")
            .update({ checkout_session_id: checkoutSessionId })
            .eq("id", winnerPi.id);
          pi = winnerPi;
        }
      }
    }
    if (!pi) {
      await markEvent("ignored_unknown", {
        payment_intent_id: paymentIntentId || null,
        checkout_session_id: checkoutSessionId || null,
      });
      console.warn("[WEBHOOK] No payment_intents row for event", event.id, event.type);
      return json(200, { ok: true });
    }

    // Backfill the PayMongo payment intent id (Checkout Sessions only
    // reveals it post-payment) — makes payment.paid retries find this row.
    if (paymentIntentId && pi.paymongo_payment_intent_id !== paymentIntentId) {
      await supabase
        .from("payment_intents")
        .update({ paymongo_payment_intent_id: paymentIntentId })
        .eq("id", pi.id);
    }

    const { data: rawOrder, error: orderErr } = await supabase
      .from("orders")
      .select("id, status, payment_status, total_amount, items_snapshot, cancellation_reason")
      .eq("id", pi.order_id)
      .maybeSingle();
    const order = (rawOrder as OrderRow | null);
    if (orderErr || !order) {
      console.error("[WEBHOOK] order lookup failed:", orderErr?.message ?? "not found");
      auditCtx.order_id = pi.order_id;
      await markEvent("failed", { payment_intent_id: paymentIntentId || null, order_id: pi.order_id });
      return json(500, { error: "order lookup failed" }); // retryable
    }
    auditCtx.order_id = order.id;

    // ── Event dispatch ────────────────────────────────────────────
    if (event.type === "payment.paid" || event.type === "checkout_session.payment.paid") {
      // ── Amount integrity (§3.4 / §8.7) — never silently accept ────
      const expectedCentavos = Math.round(Number(pi.amount) * 100);
      if (!chargedCents || chargedCents !== expectedCentavos) {
        console.error(
          `[WEBHOOK] AMOUNT MISMATCH order=${order.id} charged=${chargedCents} expected=${expectedCentavos}`,
        );
        await supabase.from("orders").update({
          status: "payment_conflict",
          payment_status: "paid",
          cancellation_reason: "Amount mismatch",
          cancellation_details:
            `Payment confirmed for ₱${(chargedCents / 100).toFixed(2)} but the checkout was for ₱${Number(pi.amount).toFixed(2)}. Manual review required.`,
        }).eq("id", order.id);
        await supabase.from("payment_intents")
          .update({ status: "succeeded", paid_at: new Date().toISOString(), ...feeFields })
          .eq("id", pi.id);
        await markEvent("amount_mismatch", { order_id: order.id, payment_intent_id: paymentIntentId || null });
        return json(200, { ok: true });
      }

      // ── State race (§8.5): order must still be awaiting payment ──
      if (order.status !== "awaiting_payment") {
        if (order.status === "cancelled" || order.status === "payment_conflict") {
          // Money arrived after we expired/failed the order.
          console.error("[WEBHOOK] Payment received for non-awaiting order", order.id, order.status);
          await supabase.from("orders").update({
            status: "payment_conflict",
            payment_status: "paid",
            cancellation_reason: order.cancellation_reason || "Late payment",
            cancellation_details:
              "Payment confirmed after the order was already cancelled/expired. Manual refund check required.",
          }).eq("id", order.id);
        }
        await markEvent("ignored_stale", { order_id: order.id, payment_intent_id: paymentIntentId || null });
        return json(200, { ok: true });
      }

      // ── Finalize: materialize order_items (decrements stock via the
      //    existing trigger). DIFF-BASED and idempotent: we insert only
      //    the snapshot items not already present for this order, so a
      //    retry after a crash mid-materialization fills the gap instead
      //    of either under-filling (skip-all) or double-decrementing
      //    (insert-all). A paid order is NEVER deleted (§8.6). ────────
      const snapshot: any[] = Array.isArray(order.items_snapshot)
        ? order.items_snapshot
        : [];
      if (snapshot.length === 0) {
        // Captured charge with no item data — honest terminal flag for
        // manual review, not a silent ack.
        console.error("[WEBHOOK] No items_snapshot on paid order", order.id);
        await supabase.from("orders").update({
          status: "payment_conflict",
          payment_status: "paid",
          cancellation_reason: "Missing order items after payment",
          cancellation_details: "Payment confirmed but the order has no items_snapshot. Manual review required.",
        }).eq("id", order.id);
        await supabase.from("payment_intents")
          .update({ status: "succeeded", paid_at: new Date().toISOString(), ...feeFields })
          .eq("id", pi.id);
        await markEvent("stock_conflict", { order_id: order.id, payment_intent_id: paymentIntentId || null });
        return json(200, { ok: true });
      }

      // Already-materialized (product_id|normalized_size) keys.
      // CRITICAL: this query must succeed — if it fails transiently and
      // we treat the order as empty, every snapshot item would be
      // re-inserted and stock double-decremented. Retry instead.
      const { data: rawExisting, error: existingErr } = await supabase
        .from("order_items")
        .select("product_id, size")
        .eq("order_id", order.id);
      const existingRows = (rawExisting as { product_id: string; size: string }[] | null);
      if (existingErr) {
        console.error("[WEBHOOK] order_items lookup failed:", existingErr.message);
        await markEvent("failed", { order_id: order.id, payment_intent_id: paymentIntentId || null });
        return json(500, { error: "order_items lookup failed" }); // retryable
      }
      const existingKeys = new Set(
        (existingRows ?? []).map(
          (r: any) => `${r.product_id}|${normalizeSize(r.size ?? "")}`,
        ),
      );
      const missing = snapshot.filter(
        (i) => !existingKeys.has(`${i.product_id}|${normalizeSize(i.size ?? "")}`),
      );

      let insertedCount = 0;
      let stockOk = true;
      let conflictDetail = "";
      if (missing.length > 0) {
        const productIds = [...new Set(missing.map((i) => i.product_id as string))];
        const { data: rawInv, error: invErr } = await supabase
          .from("inventory")
          .select("product_id, size, stock")
          .in("product_id", productIds)
          .gt("stock", 0);
        const invRows = (rawInv as { product_id: string; size: string; stock: number }[] | null);
        if (invErr) {
          // Transient lookup failure — retryable, NOT a stock conflict.
          console.error("[WEBHOOK] inventory lookup failed:", invErr.message);
          await markEvent("failed", { order_id: order.id, payment_intent_id: paymentIntentId || null });
          return json(500, { error: "inventory lookup failed" });
        }
        const invByProduct = new Map<string, { size: string; stock: number }[]>();
        for (const row of invRows ?? []) {
          const list = invByProduct.get(row.product_id) ?? [];
          list.push({ size: row.size, stock: row.stock });
          invByProduct.set(row.product_id, list);
        }

        for (const item of missing) {
          const size = resolveInventorySize(
            invByProduct.get(item.product_id as string) ?? [],
            item.size ?? "",
          );
          if (size === null) {
            stockOk = false;
            conflictDetail = `Size "${item.size}" of ${item.product_name ?? item.product_id} is no longer in stock.`;
            break;
          }
          const { error: insErr } = await supabase.from("order_items").insert({
            order_id: order.id,
            product_id: item.product_id,
            size,
            quantity: Number(item.quantity),
            unit_price: Number(item.unit_price),
          });
          if (insErr) {
            stockOk = false;
            conflictDetail = `Could not reserve ${item.product_name ?? item.product_id}: ${insErr.message}`;
            console.error("[WEBHOOK] order_items insert failed:", insErr.message);
            break;
          }
          insertedCount++;
        }
      } else {
        console.log("[WEBHOOK] order_items already fully materialized — no inserts needed", order.id);
      }

      if (!stockOk) {
        // Money was captured but stock is unavailable — manual review.
        // Payment status reflects reality (paid); order flagged.
        // Record how much was already reserved so a reviewer can
        // reconcile without extra queries.
        console.error("[WEBHOOK] STOCK CONFLICT after payment for order", order.id);
        await supabase.from("payment_intents")
          .update({ status: "succeeded", paid_at: new Date().toISOString(), ...feeFields })
          .eq("id", pi.id);
        const reservedDetail =
          `${conflictDetail} (${insertedCount} of ${snapshot.length} items were reserved before this failure)`.slice(0, 500);
        await supabase.from("orders").update({
          status: "payment_conflict",
          payment_status: "paid",
          cancellation_reason: "Stock unavailable after payment",
          cancellation_details: reservedDetail,
        }).eq("id", order.id);
        await markEvent("stock_conflict", { order_id: order.id, payment_intent_id: paymentIntentId || null });
        return json(200, { ok: true });
      }

      // ── Success: order enters the normal seller pipeline ────────
      const { error: updErr } = await supabase.from("orders").update({
        status: "pending",
        payment_status: "paid",
        gcash_transaction_id: paymentId || null,          // reuse attempt-#2 column
        payment_verified_at: new Date().toISOString(),    // reuse attempt-#2 column
      }).eq("id", order.id);
      if (updErr) {
        console.error("[WEBHOOK] failed to finalize order:", updErr.message);
        await markEvent("failed", { order_id: order.id, payment_intent_id: paymentIntentId || null });
        return json(500, { error: "finalize failed" }); // retryable
      }
      await supabase.from("payment_intents")
        .update({ status: "succeeded", paid_at: new Date().toISOString(), ...feeFields })
        .eq("id", pi.id);

      // ── Notifications (in-app + seller FCM push; fire-and-forget) ──
      await notifyPaid(supabase, order.id);

      await markEvent("processed", { order_id: order.id, payment_intent_id: paymentIntentId || null });
      console.log(`[WEBHOOK] ${event.type} processed — order ${order.id} paid & finalized ✓`);
      return json(200, { ok: true });
    }

    if (event.type === "payment.failed") {
      if (order.status === "awaiting_payment") {
        const { error: failErr } = await supabase.from("orders").update({
          status: "cancelled",
          payment_status: "failed",
          cancellation_reason: "Payment not completed",
          cancellation_details: "The GCash payment failed or was abandoned.",
          cancelled_at: new Date().toISOString(),
        }).eq("id", order.id);
        if (failErr) {
          console.error("[WEBHOOK] failed to cancel order:", failErr.message);
          await markEvent("failed", { order_id: order.id, payment_intent_id: paymentIntentId || null });
          return json(500, { error: "cancel failed" }); // retryable
        }
        await supabase.from("payment_intents")
          .update({ status: "failed" })
          .eq("id", pi.id);
        await notifyFailed(supabase, order.id);
        await markEvent("processed", { order_id: order.id, payment_intent_id: paymentIntentId || null });
        console.log(`[WEBHOOK] payment.failed processed — order ${order.id} cancelled`);
      } else {
        await markEvent("ignored_stale", { order_id: order.id, payment_intent_id: paymentIntentId || null });
      }
      return json(200, { ok: true });
    }

    // Unknown / other events (refunds, etc.) — log, never silently ignore.
    await markEvent("ignored_unknown", { order_id: order.id, payment_intent_id: paymentIntentId || null });
    console.warn("[WEBHOOK] Unhandled event type:", event.type, "for order", order.id);
    return json(200, { ok: true });
  } catch (e) {
    // Unexpected failure — mark 'failed' so a PayMongo retry can re-claim
    // and reprocess (state guards keep reprocessing safe), and return 500.
    console.error("[WEBHOOK] Unexpected processing error:", (e as any)?.message ?? e);
    await markEvent("failed", auditCtx);
    return json(500, { error: "processing failed" });
  }
});

// ────────────────────────────────────────────────────────────────
// NOTIFICATIONS (in-app rows + seller FCM push; a failure here must
// never fail the webhook's 200 ack after the order is paid). The
// seller push is deliberately AWAITED (not unawaited): an orphaned
// promise can be dropped when the isolate shuts down after the
// response — and a dropped push is exactly the silent gap this fixes.
// ────────────────────────────────────────────────────────────────

// Fire-and-forget notification helpers. The supabase client is typed as
// `any` deliberately: the repo has no generated Database types, and a
// notification insert failing must NEVER fail the webhook's 200 ack after
// the order is already paid.
async function notifyPaid(supabase: any, orderId: string): Promise<void> {
  try {
    const { data: rawOrder } = await supabase
      .from("orders")
      .select("customer_id, store_id, total_amount, gcash_fee_amount")
      .eq("id", orderId)
      .maybeSingle();
    const order = rawOrder as Partial<OrderRow> | null;
    if (!order || !order.customer_id || !order.store_id) return;
    const shortId = String(orderId).slice(-8);
    const total = Number(order.total_amount ?? 0);
    const fee = Number(order.gcash_fee_amount ?? 0);
    const title = "New paid order";
    const body =
      `Order #${shortId} — ₱${total.toFixed(2)} (incl. ₱${fee.toFixed(2)} GCash fee). Payment verified automatically.`;

    // Seller: a new PAID order entered the pipeline.
    await supabase.from("seller_notifications").insert({
      store_id: order.store_id,
      type: "new_order",
      title,
      body,
      reference_id: orderId,
    } as any);

    // Seller: FCM push to the store owner's devices. The in-app row above
    // is the live bell badge; this is the OS notification that fires while
    // the app is backgrounded/killed — the gap the cash-order path already
    // covers via the client-side send-notification-push trigger.
    // Fire-and-forget — a push failure must never fail the webhook's ack.
    await notifySellerPush(supabase, order.store_id, {
      title,
      body: `Order #${shortId} — ₱${total.toFixed(2)} paid. Tap to view.`,
      referenceId: orderId,
    });

    // Customer: payment confirmed.
    await supabase.from("notifications").insert({
      user_id: order.customer_id,
      order_id: orderId,
      category: "processing",
      title: "Payment confirmed",
      message: `Order #${shortId} — payment received via GCash. The store will start preparing your order.`,
    } as any);
  } catch (e) {
    console.error("[WEBHOOK] notifyPaid failed (non-fatal):", (e as any)?.message ?? e);
  }
}

/// FCM push to a store owner's devices for a new paid order. Reuses the
/// exact shared helper (`sendPushToUser`) that the send-notification-push
/// edge function calls for cash orders, so the seller gets the OS
/// notification even when their app is in the background/killed.
///
/// Requires the FIREBASE_PROJECT_ID and FCM_SERVICE_ACCOUNT_KEY secrets
/// (set project-wide with `supabase secrets set` — shared by all edge
/// functions, so they are available here too). If they are ever missing,
/// sendPushToUser logs `[FCM] Missing Firebase configuration` and no-ops
/// with successCount 0 — check the webhook logs if a push is silent.
///
/// NOTE: the dormant gateway-free GCash RPCs (submit_gcash_proof) have
/// the same in-app-row-without-push gap. They are DORMANT (no wired UI
/// calls them for new orders), so left untouched — re-wire them with a
/// push here if that flow is ever revived.
async function notifySellerPush(
  supabase: any,
  storeId: string,
  opts: { title: string; body: string; referenceId: string },
): Promise<void> {
  try {
    const { data: rawStore } = await supabase
      .from("stores")
      .select("owner_id")
      .eq("id", storeId)
      .maybeSingle();
    const ownerId = (rawStore as { owner_id?: string } | null)?.owner_id;
    if (!ownerId) return;
    await sendPushToUser(
      supabase,
      ownerId,
      { title: opts.title, body: opts.body },
      {
        type: "new_order",
        referenceId: opts.referenceId,
        screen: "seller_order_detail",
      },
    );
  } catch (e) {
    console.error(
      "[WEBHOOK] seller push failed (non-fatal):",
      (e as any)?.message ?? e,
    );
  }
}

async function notifyFailed(supabase: any, orderId: string): Promise<void> {
  try {
    const { data: rawOrder } = await supabase
      .from("orders")
      .select("customer_id")
      .eq("id", orderId)
      .maybeSingle();
    const order = rawOrder as Partial<OrderRow> | null;
    if (!order || !order.customer_id) return;
    const shortId = String(orderId).slice(-8);
    await supabase.from("notifications").insert({
      user_id: order.customer_id,
      order_id: orderId,
      category: "returns",
      title: "Payment not completed",
      message: `Order #${shortId} — the GCash payment was not completed. No charge was made; you can place a new order anytime.`,
    } as any);
  } catch (e) {
    console.error("[WEBHOOK] notifyFailed failed (non-fatal):", (e as any)?.message ?? e);
  }
}
