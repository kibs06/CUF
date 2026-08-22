// supabase/functions/request-account-deletion/index.ts
//
// Supabase Edge Function: Submit an account deletion request.
//
// Called by: Dart client-side via Supabase.functions.invoke
// Auth: Requires a valid Bearer token (authenticated user)
//
// The function:
//   1. Calls the request_account_deletion() RPC to create the request
//   2. Sends a push notification to all admin users
//   3. Creates an in-app notification for each admin

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  getSupabaseAdmin,
  sendPushToUser,
  corsHeaders,
} from "../_shared/push.ts";

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get the Authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: corsHeaders }
      );
    }

    // Create a Supabase client with the user's token
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Verify the user is authenticated
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: corsHeaders }
      );
    }

    // Parse optional reason from request body
    let reason: string | null = null;
    try {
      const body = await req.json();
      reason = body.reason || null;
    } catch {
      // No body or invalid JSON — that's fine
    }

    // Call the RPC
    const { data, error } = await supabase.rpc("request_account_deletion", {
      p_reason: reason,
    });

    if (error) {
      console.error("[RequestDeletion] RPC error:", error);
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: corsHeaders }
      );
    }

    console.log(
      `[RequestDeletion] User ${user.id} submitted deletion request:`,
      data
    );

    // Check if the request was actually created (not a duplicate)
    const success = data && typeof data === "object" && (data as Record<string, unknown>).success === true;

    if (success) {
      // Get the requesting user's name for the notification
      const supabaseAdmin = getSupabaseAdmin();

      const { data: profile } = await supabaseAdmin
        .from("profiles")
        .select("full_name")
        .eq("id", user.id)
        .single();

      const userName = (profile as Record<string, string> | null)?.full_name ?? "A user";

      // Find all admin users
      const { data: admins } = await supabaseAdmin
        .from("profiles")
        .select("id")
        .eq("role", "admin");

      if (admins && admins.length > 0) {
        console.log(
          `[RequestDeletion] Notifying ${admins.length} admin(s) about deletion request from ${userName}`
        );

        for (const admin of admins) {
          // Skip the requesting user if they're also an admin
          if (admin.id === user.id) continue;

          // Send push notification
          await sendPushToUser(
            supabaseAdmin,
            admin.id,
            {
              title: "Account Deletion Request",
              body: `${userName} has requested to delete their account. Please review.`,
            },
            {
              type: "deletion_request",
              screen: "manage_deletion_requests",
            }
          );

          // Create in-app notification
          await supabaseAdmin.from("notifications").insert({
            user_id: admin.id,
            title: "Account Deletion Request",
            message: `${userName} has requested to delete their account. Please review in Deletion Requests.`,
            type: "deletion_request",
            reference_id: user.id,
          });
        }

        console.log(
          `[RequestDeletion] Notifications sent to ${admins.length} admin(s)`
        );
      }
    }

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("[RequestDeletion] Error:", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
