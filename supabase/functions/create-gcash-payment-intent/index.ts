// ══════════════════════════════════════════════════════════════════
// create-gcash-payment-intent — online GCash checkout (step 1)
//
// Auth:        required (JWT) — the logged-in customer
// Input:       { idempotency_key, items:[{product_id,size,quantity}],
//                delivery_address?, shipping_address? }
// Behavior:
//   • NEVER trusts a client-supplied total. Stock is revalidated and the
//     total is recomputed server-side from current product prices +
//     the fixed ₱100 delivery fee.
//   • Creates the orders row in status='awaiting_payment' with an
//     items_snapshot — order_items are NOT inserted (stock untouched)
//     until the webhook confirms payment (defer-until-paid).
//   • Creates the PayMongo Payment Intent (gcash e-wallet) and returns
//     the redirect/checkout URL for the customer.
//   • Idempotent: an existing pending intent for this customer is
//     returned instead of creating a duplicate (double-tap / retry /
//     two devices can never create two charges).
// Output:     { order_id, payment_intent_id, checkout_url, client_key,
//               amount, expires_at }
//
// Env: PAYMONGO_SECRET_KEY (required), PUBLIC_RETURN_URL (deep link),
//      GCASH_PAYMENT_EXPIRY_MINUTES (default 30)
// ══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  createGcashRedirectPayment,
  resolveInventorySize,
} from "../_shared/paymongo.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

const DELIVERY_FEE = 100; // fixed, matches cart/checkout logic
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

/// Stable fingerprint of the raw cart items (sorted product_id:size:qty
/// joined by '|'), computed from the REQUEST (pre size-resolution) so the
/// same cart always yields the same fingerprint across calls.
function cartFingerprint(items: any[]): string {
  return items
    .map((i) => `${i.product_id}:${i.size ?? ""}:${i.quantity}`)
    .sort()
    .join("|");
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";

  // ── Auth: must be the logged-in customer ────────────────────────
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData?.user) {
    return json(401, { error: "Unauthorized" });
  }
  const userId = authData.user.id;

  // ── Parse + validate input ──────────────────────────────────────
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Invalid JSON body" });
  }

  const idempotencyKey: string = body?.idempotency_key ?? "";
  if (!UUID_RE.test(idempotencyKey)) {
    return json(400, { error: "idempotency_key must be a UUID" });
  }
  const items: any[] = Array.isArray(body?.items) ? body.items : [];
  if (items.length === 0) {
    return json(400, { error: "No items to order" });
  }
  for (const it of items) {
    if (!it?.product_id || !(it?.quantity > 0)) {
      return json(400, { error: "Each item needs a product_id and quantity > 0" });
    }
  }
  const deliveryAddress: string = body?.delivery_address ?? "";
  const shippingAddress = body?.shipping_address ?? null;

  const serviceClient = createClient(supabaseUrl, serviceKey);

  // ── Idempotency: active pending intent for this customer? ───────
  // Prevents double-charge for the same cart across devices/retries.
  const { data: activeIntents, error: activeErr } = await serviceClient
    .from("payment_intents")
    .select(
      "id, order_id, paymongo_payment_intent_id, client_key, checkout_url, amount, status, expires_at, items_fingerprint",
    )
    .eq("customer_id", userId)
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .limit(1);
  if (activeErr) {
    console.error("[CREATE-PI] active intent lookup failed:", activeErr.message);
    return json(500, { error: "Could not check for an existing checkout" });
  }
  const fingerprint = cartFingerprint(items);
  if (activeIntents && activeIntents.length > 0) {
    const pi = activeIntents[0];
    // Don't resurrect an intent whose payment window has already lapsed —
    // let a fresh checkout start; the sweep will expire the stale one.
    const expiresAt = new Date(pi.expires_at);
    if (expiresAt.getTime() > Date.now()) {
      if (pi.items_fingerprint === fingerprint) {
        console.log("[CREATE-PI] Returning existing pending intent for the same cart", pi.id);
        return json(200, {
          order_id: pi.order_id,
          payment_intent_id: pi.paymongo_payment_intent_id,
          checkout_url: pi.checkout_url,
          client_key: pi.client_key,
          amount: pi.amount,
          expires_at: pi.expires_at,
          already_exists: true,
        });
      }
      // Different cart → don't silently pay for the wrong items.
      console.log("[CREATE-PI] Active pending intent is for a different cart — refusing", pi.id);
      return json(409, {
        error: "You have an unfinished checkout for a different cart. Complete or cancel it before starting a new one.",
      });
    }
    console.log("[CREATE-PI] Existing intent expired — creating a fresh checkout", pi.id);
  }

  // ── Revalidate products + recompute the total server-side ───────
  const productIds = [...new Set(items.map((i) => i.product_id as string))];
  const { data: products, error: productsErr } = await userClient
    .from("products")
    .select("id, store_id, price, name")
    .in("id", productIds);
  if (productsErr) {
    console.error("[CREATE-PI] product lookup failed:", productsErr.message);
    return json(500, { error: "Could not verify products" });
  }
  if (!products || products.length !== productIds.length) {
    return json(409, { error: "Some items are no longer available. Please refresh your cart." });
  }
  const productById = new Map(products.map((p: any) => [p.id, p]));

  // ── Revalidate stock (server-side; no reservation, just a check) ─
  const { data: inventoryRows, error: invErr } = await userClient
    .from("inventory")
    .select("product_id, size, stock")
    .in("product_id", productIds)
    .gt("stock", 0);
  if (invErr) {
    console.error("[CREATE-PI] inventory lookup failed:", invErr.message);
    return json(500, { error: "Could not verify stock" });
  }
  const invByProduct = new Map<string, { size: string; stock: number }[]>();
  for (const row of inventoryRows ?? []) {
    const list = invByProduct.get(row.product_id) ?? [];
    list.push({ size: row.size, stock: row.stock });
    invByProduct.set(row.product_id, list);
  }

  const snapshot: any[] = [];
  let subtotal = 0;
  for (const it of items) {
    const product = productById.get(it.product_id as string);
    const productName: string = product?.name ?? "Product";
    const size = resolveInventorySize(invByProduct.get(it.product_id as string) ?? [], it.size ?? "");
    if (size === null) {
      return json(409, {
        error: `Size "${it.size}" is no longer available for ${productName}. Please update your cart.`,
      });
    }
    const unitPrice = Number(product.price ?? 0);
    const quantity = Number(it.quantity);
    subtotal += unitPrice * quantity;
    snapshot.push({
      product_id: it.product_id,
      product_name: productName,
      size,
      quantity,
      unit_price: unitPrice,
    });
  }
  const total = subtotal > 0 ? subtotal + DELIVERY_FEE : 0;

  // ── Create the order (awaiting_payment — no stock touched) ──────
  const firstProduct: any = productById.get(productIds[0]);
  const { data: orderRow, error: orderErr } = await serviceClient
    .from("orders")
    .insert({
      customer_id: userId,
      store_id: firstProduct.store_id,
      status: "awaiting_payment",
      fulfillment: "pickup",
      total_amount: total,
      payment_method: "gcash",
      payment_status: "pending",
      notes: deliveryAddress,
      shipping_address: shippingAddress,
      source: "online",
      items_snapshot: snapshot,
    })
    .select("id")
    .single();
  if (orderErr) {
    console.error("[CREATE-PI] order insert failed:", orderErr.message);
    return json(500, { error: "Could not create the order" });
  }
  const orderId: string = orderRow.id; // UUID (live DB orders.id)

  // ── Create the PayMongo redirect payment ────────────────────────
  const returnUrl =
    Deno.env.get("PUBLIC_RETURN_URL") ??
    "solvision://checkout/gcash"; // deep link finalized with the Flutter work
  let payment: Awaited<ReturnType<typeof createGcashRedirectPayment>>;
  try {
    payment = await createGcashRedirectPayment(
      total,
      `Payment for SoleVision Order #${String(orderId).slice(-8)}`,
      returnUrl,
    );
  } catch (e: any) {
    console.error("[CREATE-PI] PayMongo failed:", e?.message ?? e);
    // No money moved and no stock held — close the order for audit.
    await serviceClient
      .from("orders")
      .update({
        status: "cancelled",
        payment_status: "failed",
        cancellation_reason: "Payment gateway error",
        cancellation_details: String(e?.message ?? "PayMongo error").slice(0, 500),
        cancelled_at: new Date().toISOString(),
      })
      .eq("id", orderId);
    return json(502, { error: "Payment provider unavailable. Please try again." });
  }

  // ── Persist the payment intent ──────────────────────────────────
  const expiryMinutes = Number(Deno.env.get("GCASH_PAYMENT_EXPIRY_MINUTES") ?? 30);
  const expiresAt = new Date(Date.now() + expiryMinutes * 60_000).toISOString();

  const livemode = Deno.env.get("PAYMONGO_LIVEMODE") === "true";
  const { error: piErr } = await serviceClient.from("payment_intents").insert({
    customer_id: userId,
    order_id: orderId,
    idempotency_key: idempotencyKey,
    paymongo_payment_intent_id: payment.paymentIntentId,
    paymongo_payment_method_id: payment.paymentMethodId,
    client_key: payment.clientKey,
    checkout_url: payment.checkoutUrl,
    amount: total,
    status: "pending",
    livemode,
    expires_at: expiresAt,
    items_fingerprint: fingerprint,
  });
  if (piErr) {
    // 23505 = unique violation: either our own idempotency key or the
    // DB-level one-pending-per-customer index — a concurrent request won
    // the race. Close our duplicate order (no money moved, no stock held)
    // and, if visible, resume the winner's intent so the client can continue.
    const isDuplicate = piErr.code === "23505";
    console.error(
      `[CREATE-PI] payment_intents insert failed (duplicate=${isDuplicate}):`, piErr.message,
    );
    await serviceClient
      .from("orders")
      .update({
        status: "cancelled",
        payment_status: "failed",
        cancellation_reason: isDuplicate ? "Duplicate checkout detected" : "Payment provider error",
        cancellation_details: String(piErr.message).slice(0, 500),
        cancelled_at: new Date().toISOString(),
      })
      .eq("id", orderId);

    if (isDuplicate) {
      const { data: winner } = await serviceClient
        .from("payment_intents")
        .select("order_id, paymongo_payment_intent_id, client_key, checkout_url, amount, expires_at")
        .eq("customer_id", userId)
        .eq("status", "pending")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (winner) {
        return json(200, {
          order_id: winner.order_id,
          payment_intent_id: winner.paymongo_payment_intent_id,
          checkout_url: winner.checkout_url,
          client_key: winner.client_key,
          amount: winner.amount,
          expires_at: winner.expires_at,
          already_exists: true,
        });
      }
    }
    return json(409, { error: "A checkout is already in progress for this cart." });
  }

  console.log(`[CREATE-PI] OK order=${orderId} pi=${payment.paymentIntentId} amount=${total}`);
  return json(200, {
    order_id: orderId,
    payment_intent_id: payment.paymentIntentId,
    checkout_url: payment.checkoutUrl,
    client_key: payment.clientKey,
    amount: total,
    expires_at: expiresAt,
  });
});
