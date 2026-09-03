// supabase/functions/send-message-push/index.ts
//
// Supabase Edge Function: Send FCM push notification when a new message
// is inserted into the `messages` table.
//
// Triggered by: Database pg_net trigger on messages INSERT (both directions)
//   - Seller → Customer: notifies the customer
//   - Customer → Seller: notifies the store owner
//
// Environment secrets required:
//   - FCM_SERVICE_ACCOUNT_KEY: Firebase service account JSON (base64 encoded)
//   - FIREBASE_PROJECT_ID: Firebase project ID

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  getSupabaseAdmin,
  sendPushToUser,
  corsHeaders,
} from "../_shared/push.ts";
import { checkRateLimit, rateLimitedResponse } from "../_shared/rate_limit.ts";

interface MessagePayload {
  conversation_id: string;
  sender_id: string;
  sender_type: string;
  body?: string;
  store_name?: string;
  customer_id?: string;
}

// ── Main Handler ─────────────────────────────────────────────────

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // T6: per-IP rate limit (600/min — the DB pg_net trigger fires once
  // per message insert and chat can burst; this only caps scripted
  // direct HTTP abuse of the function).
  const rl = await checkRateLimit(req, "send-message-push", 600);
  if (!rl.allowed) return rateLimitedResponse(rl, corsHeaders);

  try {
    const payload: MessagePayload = await req.json();

    // Validate sender_type
    if (payload.sender_type !== "seller" && payload.sender_type !== "customer") {
      console.log("[FCM] Unknown sender_type:", payload.sender_type, "— skipping");
      return new Response(
        JSON.stringify({ message: "Unknown sender type, skipping" }),
        { headers: corsHeaders }
      );
    }

    const supabase = getSupabaseAdmin();

    // 1. Get conversation details
    const { data: conversation, error: convError } = await supabase
      .from("conversations")
      .select("customer_id, store_id")
      .eq("id", payload.conversation_id)
      .single();

    if (convError || !conversation) {
      console.error("[FCM] Conversation not found:", convError);
      return new Response(
        JSON.stringify({ error: "Conversation not found" }),
        { status: 404, headers: corsHeaders }
      );
    }

    // 2. Get store details (name + owner_id for seller-bound notifications)
    const { data: store } = await supabase
      .from("stores")
      .select("name, owner_id")
      .eq("id", conversation.store_id)
      .single();

    const storeName = store?.name ?? "Store";
    const storeOwnerId = store?.owner_id ?? null;

    // 3. Determine recipient
    //    Seller → Customer: recipient is the customer
    //    Customer → Seller: recipient is the store owner
    let recipientUserId: string;
    let recipientLabel: string;

    if (payload.sender_type === "seller") {
      recipientUserId = conversation.customer_id;
      recipientLabel = "customer";
    } else {
      if (!storeOwnerId) {
        console.error("[FCM] Store owner not found for store:", conversation.store_id);
        return new Response(
          JSON.stringify({ error: "Store owner not found" }),
          { status: 404, headers: corsHeaders }
        );
      }
      recipientUserId = storeOwnerId;
      recipientLabel = "seller";
    }

    console.log("[FCM] Looking up tokens for", recipientLabel, ":", recipientUserId);

    // 4. Build notification title
    //    Seller → Customer: title = store name
    //    Customer → Seller: title = customer's name
    let senderProfileName: string | null = null;
    if (payload.sender_type === "customer" && payload.sender_id) {
      const { data: senderProfile } = await supabase
        .from("profiles")
        .select("full_name")
        .eq("id", payload.sender_id)
        .single();
      senderProfileName = senderProfile?.full_name ?? null;
    }

    const title = payload.sender_type === "customer"
      ? (senderProfileName ?? "Customer")
      : storeName;

    const body = payload.body
      ? payload.body.length > 100
        ? payload.body.substring(0, 100) + "..."
        : payload.body
      : "New message";

    // 5. Send via shared helper (badge count is computed inside sendPushToUser)
    const result = await sendPushToUser(
      supabase,
      recipientUserId,
      { title, body },
      {
        type: "new_message",
        conversation_id: payload.conversation_id,
        sender_name: title,
        store_name: storeName,
        body: body,
      }
    );

    console.log(
      `[FCM] Sent ${result.successCount}/${result.successCount + result.invalidTokensRemoved} notifications for conversation ${payload.conversation_id}`
    );

    return new Response(
      JSON.stringify({
        message: `Sent ${result.successCount} notifications`,
        invalidTokensRemoved: result.invalidTokensRemoved,
      }),
      { headers: corsHeaders }
    );
  } catch (e) {
    console.error("[FCM] Error:", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
