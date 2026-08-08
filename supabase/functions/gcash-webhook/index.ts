// ══════════════════════════════════════════════════════════════════
// gcash-webhook — PayMongo webhook for online GCash payments
//
// Public endpoint (deploy with --no-verify-jwt; PayMongo calls it with
// a signature, not a Supabase JWT).
//
// HARD REQUIREMENTS (task brief §2):
//   • Signature verification is MANDATORY on every request — the
//     Paymongo-Signature header is HMAC-verified before ANY DB write.
//     There is no bypass flag anywhere.
//   • Idempotent: payment_webhook_events.paymongo_event_id is UNIQUE.
//     First INSERT wins; duplicate deliveries are no-ops. A delivery
//     that previously failed processing (status='failed') is re-claimed
//     so PayMongo retries can actually recover.
//   • The order is finalized (order_items inserted → stock decremented
//     by the existing trigger, status → pending) ONLY on payment.paid.
//   • A paid order is NEVER deleted. Stock/amount conflicts land in
//     status='payment_conflict' for manual review.
//
// Events handled: payment.paid, payment.failed. Unknown event types are
// logged (append-only) and acknowledged — never silently ignored.
//
// Env: PAYMONGO_WEBHOOK_SECRET (required, whsk_…), SUPABASE_URL,
//      SUPABASE_SERVICE_ROLE_KEY
// ══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  verifyWebhookSignature,
  parseWebhookEvent,
  normalizeSize,
  resolveInventorySize,
} from "../_shared/paymongo.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}



serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

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
    try {
      await supabase.from("payment_webhook_events").insert({
        paymongo_event_id: `rej-${crypto.randomUUID()}`,
        event_type: event.type || "unknown",
        status: "rejected_signature",
        redacted_payload: event.redacted,
      });
    } catch (e) {
      console.error("[WEBHOOK] could not log rejection:", e?.message ?? e);
    }
    return json(401, { error: "invalid signature" });
  }

  // ── 2. Idempotency gate: first INSERT wins; 'failed' rows re-claim ─
  const { data: claimed } = await supabase
    .from("payment_webhook_events")
    .insert({
      paymongo_event_id: event.id,
      event_type: event.type,
      status: "processing",
      livemode: event.livemode,
      redacted_payload: event.redacted,
    })
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
  try {
    const attrs = event.data.attributes;
    const paymentId: string = event.data.id; // pay_xxx
    const paymentIntentId: string =
      (attrs?.payment_intent?.id as string) ?? (attrs?.payment_intent_id as string) ?? "";

    if (!paymentIntentId) {
      await markEvent("ignored_unknown", { payment_intent_id: null });
      console.error("[WEBHOOK] No payment intent id on event", event.id, event.type);
      return json(200, { ok: true });
    }

    const { data: pi, error: piErr } = await supabase
      .from("payment_intents")
      .select("id, order_id, amount, status")
      .eq("paymongo_payment_intent_id", paymentIntentId)
      .maybeSingle();
    if (piErr) {
      console.error("[WEBHOOK] payment_intents lookup failed:", piErr.message);
      await markEvent("failed", { payment_intent_id: paymentIntentId });
      return json(500, { error: "lookup failed" }); // retryable
    }
    if (!pi) {
      await markEvent("ignored_unknown", { payment_intent_id: paymentIntentId });
      console.warn("[WEBHOOK] No payment_intents row for PI", paymentIntentId);
      return json(200, { ok: true });
    }

    const { data: order, error: orderErr } = await supabase
      .from("orders")
      .select("id, status, payment_status, total_amount, items_snapshot, cancellation_reason")
      .eq("id", pi.order_id)
      .maybeSingle();
    if (orderErr || !order) {
      console.error("[WEBHOOK] order lookup failed:", orderErr?.message ?? "not found");
      await markEvent("failed", { payment_intent_id: paymentIntentId, order_id: pi.order_id });
      return json(500, { error: "order lookup failed" }); // retryable
    }

    switch (event.type) {
      case "payment.paid": {
        // ── Amount integrity (§7.7) — never silently accept ─────────
        const chargedCentavos = Number(attrs?.amount ?? 0);
        const expectedCentavos = Math.round(Number(order.total_amount) * 100);
        if (chargedCentavos !== expectedCentavos) {
          console.error(
            `[WEBHOOK] AMOUNT MISMATCH order=${order.id} charged=${chargedCentavos} expected=${expectedCentavos}`,
          );
          await supabase.from("orders").update({
            status: "payment_conflict",
            payment_status: "paid",
            cancellation_reason: "Amount mismatch",
            cancellation_details:
              `Payment confirmed for ₱${(chargedCentavos / 100).toFixed(2)} but order total is ₱${Number(order.total_amount).toFixed(2)}. Manual review required.`,
          }).eq("id", order.id);
          await supabase.from("payment_intents")
            .update({ status: "succeeded", paid_at: new Date().toISOString() })
            .eq("id", pi.id);
          await markEvent("amount_mismatch", { order_id: order.id, payment_intent_id: paymentIntentId });
          return json(200, { ok: true });
        }

        // ── State race (§7.5): order must still be awaiting payment ─
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
          await markEvent("ignored_stale", { order_id: order.id, payment_intent_id: paymentIntentId });
          return json(200, { ok: true });
        }

        // ── Finalize: materialize order_items (decrements stock via the
        //    existing trigger). DIFF-BASED and idempotent: we insert only
        //    the snapshot items not already present for this order, so a
        //    retry after a crash mid-materialization fills the gap instead
        //    of either under-filling (skip-all) or double-decrementing
        //    (insert-all). A paid order is NEVER deleted (§7.6). ────────
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
          const { error: piUpdErr } = await supabase.from("payment_intents")
            .update({ status: "succeeded", paid_at: new Date().toISOString() })
            .eq("id", pi.id);
          if (piUpdErr) {
            console.error("[WEBHOOK] payment_intents -> succeeded update failed:", piUpdErr.message);
          }
          await markEvent("stock_conflict", { order_id: order.id, payment_intent_id: paymentIntentId });
          return json(200, { ok: true });
        }

        // Already-materialized (product_id|normalized_size) keys.
        // CRITICAL: this query must succeed — if it fails transiently and
        // we treat the order as empty, every snapshot item would be
        // re-inserted and stock double-decremented. Retry instead.
        const { data: existingRows, error: existingErr } = await supabase
          .from("order_items")
          .select("product_id, size")
          .eq("order_id", order.id);
        if (existingErr) {
          console.error("[WEBHOOK] order_items lookup failed:", existingErr.message);
          await markEvent("failed", { order_id: order.id, payment_intent_id: paymentIntentId });
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
          const { data: invRows, error: invErr } = await supabase
            .from("inventory")
            .select("product_id, size, stock")
            .in("product_id", productIds)
            .gt("stock", 0);
          if (invErr) {
            // Transient lookup failure — retryable, NOT a stock conflict.
            console.error("[WEBHOOK] inventory lookup failed:", invErr.message);
            await markEvent("failed", { order_id: order.id, payment_intent_id: paymentIntentId });
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
          const { error: piUpdErr } = await supabase.from("payment_intents")
            .update({ status: "succeeded", paid_at: new Date().toISOString() })
            .eq("id", pi.id);
          if (piUpdErr) {
            console.error("[WEBHOOK] payment_intents -> succeeded update failed:", piUpdErr.message);
          }
          const reservedDetail =
            `${conflictDetail} (${insertedCount} of ${snapshot.length} items were reserved before this failure)`.slice(0, 500);
          await supabase.from("orders").update({
            status: "payment_conflict",
            payment_status: "paid",
            cancellation_reason: "Stock unavailable after payment",
            cancellation_details: reservedDetail,
          }).eq("id", order.id);
          await markEvent("stock_conflict", { order_id: order.id, payment_intent_id: paymentIntentId });
          return json(200, { ok: true });
        }

        // ── Success: order enters the normal seller pipeline ────────
        const { error: updErr } = await supabase.from("orders").update({
          status: "pending",
          payment_status: "paid",
          gcash_transaction_id: paymentId,            // reuse attempt-#2 column
          payment_verified_at: new Date().toISOString(), // reuse attempt-#2 column
        }).eq("id", order.id);
        if (updErr) {
          console.error("[WEBHOOK] failed to finalize order:", updErr.message);
          await markEvent("failed", { order_id: order.id, payment_intent_id: paymentIntentId });
          return json(500, { error: "finalize failed" }); // retryable
        }
        const { error: piUpdErr } = await supabase.from("payment_intents")
          .update({ status: "succeeded", paid_at: new Date().toISOString() })
          .eq("id", pi.id);
        if (piUpdErr) {
          // Order is paid and finalized; only the audit mirror failed.
          console.error("[WEBHOOK] payment_intents -> succeeded update failed:", piUpdErr.message);
        }
        await markEvent("processed", { order_id: order.id, payment_intent_id: paymentIntentId });
        console.log(`[WEBHOOK] payment.paid processed — order ${order.id} paid & finalized ✓`);
        return json(200, { ok: true });
      }

      case "payment.failed": {
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
            await markEvent("failed", { order_id: order.id, payment_intent_id: paymentIntentId });
            return json(500, { error: "cancel failed" }); // retryable
          }
          await supabase.from("payment_intents")
            .update({ status: "failed" })
            .eq("id", pi.id);
          await markEvent("processed", { order_id: order.id, payment_intent_id: paymentIntentId });
          console.log(`[WEBHOOK] payment.failed processed — order ${order.id} cancelled`);
        } else {
          await markEvent("ignored_stale", { order_id: order.id, payment_intent_id: paymentIntentId });
        }
        return json(200, { ok: true });
      }

      default:
        // Never silently ignore unknown events — log for visibility.
        await markEvent("ignored_unknown", { order_id: order.id, payment_intent_id: paymentIntentId });
        console.warn("[WEBHOOK] Unhandled event type:", event.type);
        return json(200, { ok: true });
    }
  } catch (e) {
    // Unexpected failure — mark 'failed' so a PayMongo retry can re-claim
    // and reprocess (state guards keep reprocessing safe), and return 500.
    console.error("[WEBHOOK] Unexpected processing error:", e?.message ?? e);
    await markEvent("failed", {});
    return json(500, { error: "processing failed" });
  }
});
