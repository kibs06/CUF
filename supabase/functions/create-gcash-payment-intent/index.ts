// ══════════════════════════════════════════════════════════════════
// create-gcash-payment-intent — online GCash checkout (step 1)
// ══════════════════════════════════════════════════════════════════
//
// Auth:        required (JWT) — the logged-in customer
// Input:       { idempotency_key, items:[{product_id,size,quantity}],
//                delivery_address?, shipping_address? }
// Behavior:
//   • NEVER trusts a client-supplied total. Stock is revalidated and the
//     total is recomputed server-side from current product prices +
//     the fixed ₱100 delivery fee.
//   • Model B fee (confirmed with the human): the customer is charged
//     order_total + a GCash fee computed from payment_fee_config
//     (rate = data, not code) so the seller nets the full order total.
//       r_total  = (rate_bps/10000) * (1 + vat_bps/10000)
//       charged  = ceil_to_cent( order_total / (1 - r_total) )
//       fee      = charged - order_total
//   • Creates the orders row in status='awaiting_payment' with an
//     items_snapshot + the fee snapshot — order_items are NOT inserted
//     (stock untouched) until the webhook confirms payment
//     (defer-until-paid; see gcash-webhook).
//   • Creates a PayMongo CHECKOUT SESSION (hosted page that handles the
//     GCash handoff) and returns checkout_url for the customer.
//   • Idempotent: an existing pending intent for this customer is
//     returned instead of creating a duplicate (double-tap / retry /
//     two devices can never create two charges).
//   • Expiry: 15 minutes (confirmed). payment_intents.expires_at =
//     now() + GCASH_PAYMENT_EXPIRY_MINUTES; the sweep + app polling
//     resolve the order afterwards.
//
// Output:     { order_id, checkout_url, client_key, amount, fee_amount,
//               expires_at } — never the secret key.
//
// Env: PAYMONGO_SECRET_KEY (required), SUPABASE_URL,
//      SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
//      PAYMONGO_SUCCESS_URL / PAYMONGO_CANCEL_URL (deep links),
//      GCASH_PAYMENT_EXPIRY_MINUTES (default 15)
// ══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  createGcashCheckoutSession,
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

/// Model B fee computation — MUST mirror public.get_gcash_fee (the RPC
/// is display-only; this is the authoritative one). Returns centavos.
function computeFeeCents(orderTotalCents: number, rateBps: number, vatBps: number): {
  chargedCents: number;
  feeCents: number;
} {
  const rTotal = (rateBps / 10000) * (1 + vatBps / 10000);
  if (rTotal >= 1) throw new Error("Invalid fee config: all-in rate >= 100%");
  const chargedCents = Math.ceil(orderTotalCents / (1 - rTotal));
  return { chargedCents, feeCents: chargedCents - orderTotalCents };
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

  // ── Role check: only customers place online orders ──────────────
  const { data: rawProfile } = await userClient
    .from("profiles")
    .select("role")
    .eq("id", userId)
    .maybeSingle();
  const profile = (rawProfile as { role?: string } | null);
  if (profile?.role !== "customer") {
    return json(403, { error: "Only customers can place online orders." });
  }

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
      "id, order_id, checkout_session_id, paymongo_payment_intent_id, client_key, checkout_url, amount, fee_amount, status, expires_at, items_fingerprint",
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
          checkout_url: pi.checkout_url,
          client_key: pi.client_key,
          amount: pi.amount,
          fee_amount: pi.fee_amount,
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

  // ── Reject mixed-store carts: the order belongs to ONE store ────
  const storeIds = new Set(products.map((p: any) => p.store_id as string));
  if (storeIds.size > 1) {
    return json(409, {
      error: "Your cart contains items from different stores. Please check out each store separately.",
    });
  }

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
  let subtotalCents = 0;
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
    subtotalCents += Math.round(unitPrice * 100) * quantity;
    snapshot.push({
      product_id: it.product_id,
      product_name: productName,
      size,
      quantity,
      unit_price: unitPrice,
    });
  }
  const orderTotalCents = subtotalCents > 0 ? subtotalCents + DELIVERY_FEE * 100 : 0;

  // ── Model B fee — read the config (rate = data, never hardcoded) ─
  const { data: feeConfig, error: feeErr } = await serviceClient
    .from("payment_fee_config")
    .select("rate_bps, vat_bps")
    .eq("id", 1)
    .eq("active", true)
    .maybeSingle();
  if (feeErr || !feeConfig) {
    console.error("[CREATE-PI] fee config lookup failed:", feeErr?.message ?? "not found");
    return json(503, { error: "GCash fee is not configured. Please contact support." });
  }
  const rateBps = Number(feeConfig.rate_bps);
  const vatBps = Number(feeConfig.vat_bps);

  let chargedCents: number;
  let feeCents: number;
  try {
    ({ chargedCents, feeCents } = computeFeeCents(orderTotalCents, rateBps, vatBps));
  } catch (e: any) {
    console.error("[CREATE-PI] fee config invalid:", e?.message ?? e);
    return json(503, { error: "GCash fee is not configured. Please contact support." });
  }
  const chargedPesos = chargedCents / 100;
  const feePesos = feeCents / 100;

  // ── Create the order (awaiting_payment — no stock touched) ──────
  const firstProduct: any = productById.get(productIds[0]);
  const { data: orderRow, error: orderErr } = await serviceClient
    .from("orders")
    .insert({
      customer_id: userId,
      store_id: firstProduct.store_id,
      status: "awaiting_payment",
      fulfillment: "pickup",
      total_amount: orderTotalCents / 100,
      payment_method: "gcash",
      payment_status: "pending",
      notes: deliveryAddress,
      shipping_address: shippingAddress,
      source: "online",
      items_snapshot: snapshot,
      gcash_fee_amount: feePesos,
      gcash_fee_rate_bps: rateBps,
      gcash_fee_vat_bps: vatBps,
    })
    .select("id")
    .single();
  if (orderErr) {
    console.error("[CREATE-PI] order insert failed:", orderErr.message);
    return json(500, { error: "Could not create the order" });
  }
  const orderId: string = orderRow.id; // UUID (live DB orders.id)

  // ── Create the PayMongo Checkout Session ────────────────────────
  const successUrl =
    Deno.env.get("PAYMONGO_SUCCESS_URL") ??
    "solvision://checkout/gcash/success";
  const cancelUrl =
    Deno.env.get("PAYMONGO_CANCEL_URL") ??
    "solvision://checkout/gcash/cancel";

  const lineItems = [
    ...snapshot.map((s: any) => ({
      name: `${s.product_name}${s.size ? ` (EU ${s.size})` : ""}`,
      amount: Math.round(Number(s.unit_price) * 100), // per unit, centavos
      quantity: Number(s.quantity),
    })),
    { name: "Delivery Fee", amount: DELIVERY_FEE * 100, quantity: 1 },
    { name: "GCash Service Fee", amount: feeCents, quantity: 1 },
  ];

  let session: Awaited<ReturnType<typeof createGcashCheckoutSession>>;
  try {
    session = await createGcashCheckoutSession(
      lineItems,
      successUrl,
      cancelUrl,
      `Payment for SoleVision Order #${String(orderId).slice(-8)}`,
      { order_id: orderId, idempotency_key: idempotencyKey },
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
    // Append-only audit row (synthetic key — not a real webhook event).
    const errKey = `err-${crypto.randomUUID()}`;
    await (serviceClient.from("payment_webhook_events").insert({
      paymongo_event_id: errKey,
      event_type: "checkout_session.create_failed",
      order_id: orderId,
      status: "failed",
      livemode: Deno.env.get("PAYMONGO_LIVEMODE") === "true",
      redacted_payload: {
        event_id: errKey,
        type: "checkout_session.create_failed",
        resource_id: null,
        status: "failed",
      },
    }) as any);
    return json(502, { error: "Payment provider unavailable. Please try again." });
  }

  // ── Persist the payment intent ──────────────────────────────────
  const expiryMinutes = Number(Deno.env.get("GCASH_PAYMENT_EXPIRY_MINUTES") ?? 15);
  const expiresAt = new Date(Date.now() + expiryMinutes * 60_000).toISOString();

  const livemode = Deno.env.get("PAYMONGO_LIVEMODE") === "true";
  const { error: piErr } = await serviceClient.from("payment_intents").insert({
    customer_id: userId,
    order_id: orderId,
    idempotency_key: idempotencyKey,
    checkout_session_id: session.checkoutSessionId,
    client_key: session.clientKey,
    checkout_url: session.checkoutUrl,
    amount: chargedPesos,
    fee_amount: feePesos,
    fee_rate_bps: rateBps,
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
    // Append-only audit row (synthetic key).
    const dupKey = `dup-${crypto.randomUUID()}`;
    await (serviceClient.from("payment_webhook_events").insert({
      paymongo_event_id: dupKey,
      event_type: isDuplicate
        ? "checkout_session.duplicate_cancelled"
        : "checkout_session.persist_failed",
      order_id: orderId,
      status: "failed",
      livemode: Deno.env.get("PAYMONGO_LIVEMODE") === "true",
      redacted_payload: {
        event_id: dupKey,
        type: "checkout_session.persist_failed",
        resource_id: null,
        status: "failed",
      },
    }) as any);

    if (isDuplicate) {
      const { data: winner } = await serviceClient
        .from("payment_intents")
        .select("order_id, checkout_url, client_key, amount, fee_amount, expires_at")
        .eq("customer_id", userId)
        .eq("status", "pending")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (winner) {
        return json(200, {
          order_id: winner.order_id,
          checkout_url: winner.checkout_url,
          client_key: winner.client_key,
          amount: winner.amount,
          fee_amount: winner.fee_amount,
          expires_at: winner.expires_at,
          already_exists: true,
        });
      }
    }
    return json(409, { error: "A checkout is already in progress for this cart." });
  }

  console.log(`[CREATE-PI] OK order=${orderId} cs=${session.checkoutSessionId} charged=${chargedPesos} fee=${feePesos}`);
  return json(200, {
    order_id: orderId,
    checkout_url: session.checkoutUrl,
    client_key: session.clientKey,
    amount: chargedPesos,
    fee_amount: feePesos,
    expires_at: expiresAt,
  });
});
