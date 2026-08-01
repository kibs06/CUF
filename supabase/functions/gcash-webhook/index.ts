import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { verifyWebhookSignature, parseWebhookEvent } from "../_shared/paymongo.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
};

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get the raw body for signature verification
    const body = await req.text();
    const signature = req.headers.get("Paymongo-Signature") || "";

    // Verify webhook signature
    // TODO: Implement proper HMAC verification with PAYMONGO_WEBHOOK_SECRET
    const isValid = verifyWebhookSignature(body, signature);
    if (!isValid) {
      console.error("[WEBHOOK] Invalid signature, rejecting request");
      return new Response("Invalid signature", { status: 401, headers: corsHeaders });
    }

    // Parse the event
    const event = parseWebhookEvent(body);
    console.log(`[WEBHOOK] Received event: ${event.type}`);

    // Initialize Supabase client with service role key (bypasses RLS)
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    switch (event.type) {
      case "payment.paid": {
        // Payment has been confirmed via QR Ph
        const paymentId = event.data.id;
        const paymentIntentId = event.data.attributes?.payment_intent?.id
          || event.data.attributes?.payment_intent_id;

        console.log(`[WEBHOOK] Payment paid: ${paymentId}, payment_intent: ${paymentIntentId}`);

        if (!paymentIntentId) {
          console.error("[WEBHOOK] No payment_intent ID found in event payload");
          return new Response("No payment_intent ID", { status: 200, headers: corsHeaders });
        }

        // Look up the order by gcash_reference_number (which stores the Payment Intent ID)
        const { data: order, error: lookupError } = await supabase
          .from("orders")
          .select("id")
          .eq("gcash_reference_number", paymentIntentId)
          .eq("payment_status", "pending")
          .single();

        if (lookupError || !order) {
          console.error("[WEBHOOK] Order not found or already processed for PI:", paymentIntentId);
          return new Response("Order not found or already processed", { status: 200, headers: corsHeaders });
        }

        console.log(`[WEBHOOK] Found order ${order.id} for PI ${paymentIntentId}`);

        // Update order payment status to paid
        const { error: updateError } = await supabase
          .from("orders")
          .update({
            payment_status: "paid",
            gcash_transaction_id: paymentId,
            payment_verified_at: new Date().toISOString(),
          })
          .eq("id", order.id);

        if (updateError) {
          console.error("[WEBHOOK] Failed to update order:", updateError);
          throw updateError;
        }

        console.log(`[WEBHOOK] Order ${order.id} marked as paid ✓`);
        break;
      }

      case "payment.failed": {
        const paymentId = event.data.id;
        console.log(`[WEBHOOK] Payment failed: ${paymentId}`);
        // Could update order status to reflect failure, but for now just log
        break;
      }

      case "qrph.expired": {
        console.log(`[WEBHOOK] QR Ph expired for: ${event.data.id}`);
        // QR was not scanned within 30 minutes — order stays pending
        break;
      }

      default:
        console.log(`[WEBHOOK] Unhandled event type: ${event.type}`);
    }

    // Always return 2xx quickly to acknowledge receipt
    return new Response("OK", { status: 200, headers: corsHeaders });
  } catch (error) {
    console.error("[WEBHOOK] Error:", error);
    // Still return 200 to prevent PayMongo from retrying on code errors
    return new Response("OK", { status: 200, headers: corsHeaders });
  }
});
