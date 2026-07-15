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
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface MessagePayload {
  conversation_id: string;
  sender_id: string;
  sender_type: string;
  body?: string;
  store_name?: string;
  customer_id?: string;
}

interface DeviceToken {
  fcm_token: string;
  platform: string;
}

// ── FCM HTTP v1 API ──────────────────────────────────────────────

async function sendFcmPush(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
  projectId: string,
  serviceAccountKey: string
): Promise<boolean> {
  try {
    // Get OAuth2 access token from service account
    const accessToken = await getAccessToken(serviceAccountKey);

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: token,
            notification: {
              title: title,
              body: body,
            },
            data: data,
            android: {
              priority: "high",
              notification: {
                channel_id: "solevision_messages",
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: 1,
                },
              },
            },
          },
        }),
      }
    );

    if (!response.ok) {
      const error = await response.text();
      console.error(`[FCM] Send failed: ${error}`);

      // Only remove token if FCM says it's unregistered (device uninstalled/app data cleared).
      // INVALID_ARGUMENT means our payload was wrong — don't delete a valid token for our bug.
      if (error.includes("UNREGISTERED")) {
        return false; // Signal to remove this token
      }
      return false;
    }

    return true;
  } catch (e) {
    console.error(`[FCM] Error: ${e}`);
    return false;
  }
}

// ── OAuth2 Access Token ──────────────────────────────────────────

async function getAccessToken(serviceAccountKey: string): Promise<string> {
  // Service account key is base64-encoded JSON
  const decoded = atob(serviceAccountKey);
  const serviceAccount = JSON.parse(decoded);

  const now = Math.floor(Date.now() / 1000);
  const expiry = now + 3600; // 1 hour

  // Create JWT header
  const header = { alg: "RS256", typ: "JWT" };
  const headerB64 = btoa(JSON.stringify(header)).replace(/=/g, "");

  // Create JWT payload
  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: expiry,
  };
  const payloadB64 = btoa(JSON.stringify(payload)).replace(/=/g, "");

  // Sign with private key (using Web Crypto API)
  const encoder = new TextEncoder();
  const data = encoder.encode(`${headerB64}.${payloadB64}`);

  // Import the private key
  const privateKey = serviceAccount.private_key;
  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const pemContents = privateKey
    .replace(pemHeader, "")
    .replace(pemFooter, "")
    .replace(/\s/g, "");

  const binaryDer = Uint8Array.from(atob(pemContents), (c) =>
    c.charCodeAt(0)
  );

  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    data
  );

  const signatureB64 = btoa(
    String.fromCharCode(...new Uint8Array(signature))
  ).replace(/=/g, "");

  const jwt = `${headerB64}.${payloadB64}.${signatureB64}`;

  // Exchange JWT for access token
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenData = await tokenResponse.json();
  return tokenData.access_token;
}

// ── Main Handler ─────────────────────────────────────────────────

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

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

    // Create Supabase client with service role key
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const projectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
    const serviceAccountKey = Deno.env.get("FCM_SERVICE_ACCOUNT_KEY") ?? "";

    if (!projectId || !serviceAccountKey) {
      console.error("[FCM] Missing Firebase configuration");
      return new Response(
        JSON.stringify({ error: "Firebase not configured" }),
        { status: 500, headers: corsHeaders }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

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

    // 3. Determine recipient and look up their device tokens
    //    Seller → Customer: recipient is the customer
    //    Customer → Seller: recipient is the store owner
    let recipientUserId: string;
    let recipientLabel: string;

    if (payload.sender_type === "seller") {
      // Notifying the customer
      recipientUserId = conversation.customer_id;
      recipientLabel = "customer";
    } else {
      // Notifying the seller (store owner)
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
    console.log("[FCM] Sender type:", payload.sender_type);

    const { data: tokens, error: tokenError } = await supabase
      .from("device_tokens")
      .select("fcm_token, platform")
      .eq("customer_id", recipientUserId);

    if (tokenError) {
      console.error("[FCM] Token query ERROR:", JSON.stringify(tokenError));
      return new Response(
        JSON.stringify({ error: "Token query failed", details: tokenError }),
        { status: 500, headers: corsHeaders }
      );
    }

    console.log("[FCM] Token query returned", tokens?.length ?? 0, "rows");

    if (!tokens || tokens.length === 0) {
      console.log("[FCM] No device tokens for", recipientLabel, ":", recipientUserId);
      return new Response(
        JSON.stringify({ message: "No device tokens found" }),
        { headers: corsHeaders }
      );
    }

    // 4. Build notification title
    //    Seller → Customer: title = store name (customer recognizes the store)
    //    Customer → Seller: title = customer's name (seller recognizes who messaged)
    let senderProfileName: string | null = null;
    if (payload.sender_type === "customer" && payload.sender_id) {
      const { data: senderProfile } = await supabase
        .from("profiles")
        .select("full_name")
        .eq("id", payload.sender_id)
        .single();
      senderProfileName = senderProfile?.full_name ?? null;
    }

    // title = who sent the message, from the recipient's POV
    const title = payload.sender_type === "customer"
      ? (senderProfileName ?? "Customer")
      : storeName;

    const body = payload.body
      ? payload.body.length > 100
        ? payload.body.substring(0, 100) + "..."
        : payload.body
      : "New message";

    const data: Record<string, string> = {
      type: "new_message",
      conversation_id: payload.conversation_id,
      sender_name: title,
      store_name: storeName,
      body: body,
    };

    // 5. Send to each device token
    const invalidTokens: string[] = [];
    let successCount = 0;

    for (const tokenRow of tokens) {
      const sent = await sendFcmPush(
        tokenRow.fcm_token,
        title,
        body,
        data,
        projectId,
        serviceAccountKey
      );

      if (sent) {
        successCount++;
      } else {
        invalidTokens.push(tokenRow.fcm_token);
      }
    }

    // 6. Clean up invalid tokens
    if (invalidTokens.length > 0) {
      await supabase
        .from("device_tokens")
        .delete()
        .in("fcm_token", invalidTokens);
      console.log(`[FCM] Removed ${invalidTokens.length} invalid tokens`);
    }

    console.log(
      `[FCM] Sent ${successCount}/${tokens.length} notifications for conversation ${payload.conversation_id}`
    );

    return new Response(
      JSON.stringify({
        message: `Sent ${successCount} notifications`,
        invalidTokensRemoved: invalidTokens.length,
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
