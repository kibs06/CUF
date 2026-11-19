// supabase/functions/confirm-replacement-received/index.ts
//
// Supabase Edge Function: the customer closes a shipped replacement
// (`replaced` → `replacement_received`).
//
// Called by: the customer app right after `confirm_replacement_received`
// (RPC) fails because the database does not have that function yet. The
// hosted project can lag the migration list, and the customer's button must
// not dead-end on a missing SQL function.
//
// The rules are the RPC's rules, enforced here with the service-role client:
//   - the caller's JWT must be the order's customer;
//   - only a `replaced` order can be confirmed, once;
//   - an in-store swap is already finished at the counter.
//
// It stamps `replacement_received_at`, writes the customer feed row and the
// store's bell row (each guarded, because a NULL recipient aborts the whole
// write in this project).
//
// Secrets: none beyond SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY, which the
// platform provides.
//
// Deploy: supabase functions deploy confirm-replacement-received

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

interface OrderRow {
  id: string;
  status: string;
  customer_id: string | null;
  store_id: string | null;
  replacement_method: string | null;
  replacement_received_at: string | null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json().catch(() => ({}));
    const orderId = (payload?.order_id ?? "").toString().trim();
    if (!orderId) return json({ error: "order_id is required" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });

    // The caller must be signed in; the customer check below is the real gate.
    const token = (req.headers.get("Authorization") ?? "")
      .replace(/^Bearer\s+/i, "")
      .trim();
    const { data: caller, error: callerError } = await supabase.auth.getUser(
      token,
    );
    if (callerError || !caller?.user) {
      return json({ error: "Not authenticated" }, 401);
    }
    const callerId = caller.user.id;

    const { data: orderRow, error: orderError } = await supabase
      .from("orders")
      .select(
        "id, status, customer_id, store_id, replacement_method, " +
          "replacement_received_at",
      )
      .eq("id", orderId)
      .maybeSingle();

    if (orderError) return json({ error: orderError.message }, 500);
    const order = orderRow as unknown as OrderRow | null;
    // One message for "no such order" and "not yours", like the RPC.
    if (!order || order.customer_id !== callerId) {
      return json({ error: "Order not found." }, 403);
    }

    if (order.status === "replacement_received") {
      return json({
        error: "You have already confirmed this replacement.",
        status: "replacement_received",
      }, 409);
    }
    if (order.status !== "replaced") {
      return json({
        error: "There is no replacement waiting to be confirmed on this order.",
      }, 409);
    }
    if (order.replacement_method === "in_store") {
      return json({
        error:
          "This replacement was handed over in store — there is nothing left to confirm.",
      }, 409);
    }

    const now = new Date().toISOString();
    const { error: updateError } = await supabase
      .from("orders")
      .update({
        status: "replacement_received",
        replacement_received_at: now,
      })
      .eq("id", orderId)
      .eq("status", "replaced");

    if (updateError) return json({ error: updateError.message }, 500);

    const shortId = orderId.slice(0, 8);

    if (order.customer_id) {
      const { error: feedError } = await supabase
        .from("notifications")
        .insert({
          user_id: order.customer_id,
          order_id: orderId,
          category: "returns",
          title: "Replacement received",
          message:
            `Order #${shortId} — thanks for confirming. This return is now closed.`,
          is_read: false,
          is_deleted: false,
        });
      if (feedError) {
        console.warn("[ConfirmReplacement] feed row skipped:", feedError.message);
      }
    }

    if (order.store_id) {
      const { error: bellError } = await supabase
        .from("seller_notifications")
        .insert({
          store_id: order.store_id,
          type: "replacement_received",
          title: "Replacement received",
          body:
            `Order #${shortId} — the customer confirmed they received the replacement.`,
          reference_id: orderId,
        });
      if (bellError) {
        console.warn("[ConfirmReplacement] seller bell skipped:", bellError.message);
      }
    }

    return json({ status: "replacement_received" });
  } catch (e) {
    console.error("[ConfirmReplacement] Error:", e);
    return json({ error: String(e) }, 500);
  }
});
