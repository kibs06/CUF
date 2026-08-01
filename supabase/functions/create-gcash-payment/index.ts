import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createQrPhPayment } from "../_shared/paymongo.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { orderId, amount } = await req.json();

    if (!orderId || !amount) {
      return new Response(
        JSON.stringify({ error: "orderId and amount are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (amount <= 0) {
      return new Response(
        JSON.stringify({ error: "Amount must be greater than zero" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`[CREATE-GCASH] Creating QR Ph payment for order ${orderId}, amount: ₱${amount}`);

    // Create QR Ph payment via PayMongo API (Payment Intent → Payment Method → Attach)
    const result = await createQrPhPayment(
      amount,
      `Payment for Order #${orderId}`,
    );

    console.log(`[CREATE-GCASH] QR Ph created: PI=${result.paymentIntentId}`);

    // Save the Payment Intent ID on the order so the webhook can find it later
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { error: updateError } = await supabase
      .from("orders")
      .update({ gcash_reference_number: result.paymentIntentId })
      .eq("id", orderId);

    if (updateError) {
      console.error("[CREATE-GCASH] Failed to save Payment Intent ID to order:", updateError);
      throw new Error(`Failed to link payment to order: ${updateError.message}`);
    }

    return new Response(
      JSON.stringify({
        paymentIntentId: result.paymentIntentId,
        qrImageBase64: result.qrImageBase64,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("[CREATE-GCASH] Error:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
