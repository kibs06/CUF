// supabase/functions/send-notification-push/index.ts
//
// Supabase Edge Function: Send a generic FCM push notification for any
// notification type (order status, low stock, custom order, etc.).
//
// Called by: Dart client-side services (fire-and-forget via Supabase.functions.invoke)
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

interface NotificationPayload {
  recipientUserId: string;
  title: string;
  body: string;
  type: string; // e.g. 'new_order', 'stale_order', 'low_stock', 'unpaid', 'processing', 'shipped', 'review'
  referenceId?: string;
  screen?: string; // e.g. 'order_tracking', 'seller_order_detail', 'seller_product_detail'
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload: NotificationPayload = await req.json();

    // Validate required fields
    if (!payload.recipientUserId || !payload.title || !payload.body) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: recipientUserId, title, body" }),
        { status: 400, headers: corsHeaders }
      );
    }

    const supabase = getSupabaseAdmin();

    // Build data payload for deep-link navigation on tap
    const data: Record<string, string> = {
      type: payload.type,
    };
    if (payload.referenceId) {
      data.referenceId = payload.referenceId;
    }
    if (payload.screen) {
      data.screen = payload.screen;
    }

    // Send push via shared helper
    const result = await sendPushToUser(
      supabase,
      payload.recipientUserId,
      { title: payload.title, body: payload.body },
      data
    );

    console.log(
      `[NotificationPush] Sent ${result.successCount} push(es) for type="${payload.type}" to user=${payload.recipientUserId}`
    );

    return new Response(
      JSON.stringify({
        message: `Sent ${result.successCount} notifications`,
        invalidTokensRemoved: result.invalidTokensRemoved,
      }),
      { headers: corsHeaders }
    );
  } catch (e) {
    console.error("[NotificationPush] Error:", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
