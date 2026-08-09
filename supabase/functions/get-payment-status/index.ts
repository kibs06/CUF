// ══════════════════════════════════════════════════════════════════
// get-payment-status — post-redirect / polling status check
//
// Auth: required (JWT) — a customer may only query their OWN orders.
// Returns the authoritative order + payment state so the app can decide
// what to show after the customer returns from the GCash redirect.
// The app must NEVER infer payment success from landing on a redirect —
// it queries this endpoint (or the order row) instead.
//
// Output: {
//   order_id, status, payment_status, total_amount,
//   payment: { status, amount, expires_at, checkout_url },
//   paid: boolean
// }
// ══════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData?.user) {
    return json(401, { error: "Unauthorized" });
  }
  const userId = authData.user.id;

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Invalid JSON body" });
  }
  const orderId = body?.order_id;
  if (!orderId) {
    return json(400, { error: "order_id is required" });
  }

  const serviceClient = createClient(supabaseUrl, serviceKey);

  const { data: order } = await serviceClient
    .from("orders")
    .select("id, customer_id, status, payment_status, total_amount, cancellation_reason")
    .eq("id", orderId)
    .maybeSingle();

  // Ownership check is done server-side (we bypass RLS with the service
  // role, so we must enforce it ourselves).
  if (!order || String(order.customer_id) !== userId) {
    return json(403, { error: "Forbidden" });
  }

  const { data: pi } = await serviceClient
    .from("payment_intents")
    .select("status, amount, fee_amount, expires_at, checkout_url")
    .eq("order_id", order.id)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  // Enforce expiry HERE, not just on the 5-minute cron sweep: if the
  // intent's window has closed and the order is still awaiting_payment,
  // expire it now (same UPDATE the sweep runs, idempotently guarded).
  // This makes the app's poll authoritative the moment the countdown
  // reaches zero — the customer never sits on "confirming… 0m 00s"
  // waiting for the next sweep tick. (Payment.failed / .paid still come
  // only from the signature-verified webhook; this path only handles the
  // abandoned-window case.)
  const nowIso = new Date().toISOString();
  if (
    order.status === "awaiting_payment" &&
    pi &&
    pi.status === "pending" &&
    pi.expires_at &&
    String(pi.expires_at) < nowIso
  ) {
    const { error: piErr } = await serviceClient
      .from("payment_intents")
      .update({ status: "expired", updated_at: nowIso })
      .eq("order_id", order.id)
      .eq("status", "pending");
    if (!piErr) {
      await serviceClient
        .from("orders")
        .update({
          status: "cancelled",
          payment_status: "failed",
          cancellation_reason: "Payment session expired",
          cancellation_details: "GCash payment was not completed within the allowed window.",
          cancelled_at: nowIso,
        })
        .eq("id", order.id)
        .eq("status", "awaiting_payment");
      pi.status = "expired";
    }
  }

  return json(200, {
    order_id: order.id,
    status: order.status === "awaiting_payment" && pi?.status === "expired"
      ? "cancelled"
      : order.status,
    payment_status: order.status === "awaiting_payment" && pi?.status === "expired"
      ? "failed"
      : order.payment_status,
    total_amount: order.total_amount,
    cancellation_reason: order.status === "awaiting_payment" && pi?.status === "expired"
      ? "Payment session expired"
      : order.cancellation_reason,
    payment: pi
      ? {
          status: pi.status,
          amount: pi.amount,            // charged to the customer (total + fee)
          fee_amount: pi.fee_amount,    // Model B surcharge line
          expires_at: pi.expires_at,
          checkout_url: pi.checkout_url, // so the app can re-open the redirect
        }
      : null,
    paid: order.status === "awaiting_payment" && pi?.status === "expired"
      ? false
      : order.payment_status === "paid",
  });
});
