// supabase/functions/_shared/push.ts
//
// Shared FCM push notification helpers.
// Used by: send-message-push, send-notification-push

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Types ─────────────────────────────────────────────────────────

export interface PushNotification {
  title: string;
  body: string;
}

export interface DeviceToken {
  fcm_token: string;
  platform: string;
}

// ── Supabase Client ───────────────────────────────────────────────

export function getSupabaseAdmin(): SupabaseClient {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(supabaseUrl, supabaseServiceKey);
}

// ── Badge Count Helpers ───────────────────────────────────────────

/**
 * Compute the total unread notification count for a user.
 *
 * For customers: counts unread rows in `notifications` where user_id matches.
 * For sellers: counts unread rows in `seller_notifications` where store_id
 * matches the seller's store.
 *
 * @returns The unread count (capped display value is NOT applied here —
 *          the raw count is sent to the OS so it can render "99+" itself).
 */
export async function getUnreadBadgeCount(
  supabaseAdmin: SupabaseClient,
  userId: string,
): Promise<number> {
  // Try customer notifications first
  const { count: customerCount } = await supabaseAdmin
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("is_read", false)
    .eq("is_deleted", false);

  // Also check if the user owns a store (seller)
  const { data: stores } = await supabaseAdmin
    .from("stores")
    .select("id")
    .eq("owner_id", userId);

  let sellerCount = 0;
  if (stores && stores.length > 0) {
    for (const store of stores) {
      const { count } = await supabaseAdmin
        .from("seller_notifications")
        .select("id", { count: "exact", head: true })
        .eq("store_id", store.id)
        .eq("is_read", false)
        .eq("is_deleted", false);
      sellerCount += count ?? 0;
    }
  }

  return (customerCount ?? 0) + sellerCount;
}

// ── FCM HTTP v1 API ──────────────────────────────────────────────

interface FcmResult {
  ok: boolean;
  /** True only when FCM says the registration itself is dead. */
  invalidToken: boolean;
  error?: string;
}

async function sendFcmPush(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
  badge: number,
  projectId: string,
  serviceAccountKey: string,
): Promise<FcmResult> {
  try {
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
                  badge: badge,
                },
              },
            },
          },
        }),
      }
    );

    if (!response.ok) {
      const error = await response.text();
      console.error(`[FCM] Send failed (${response.status}): ${error}`);

      // ONLY a token FCM declares dead may be deleted. Treating every failure
      // as invalid used to delete a working device's row on a transient 500 /
      // quota error, which silenced that user's pushes until they signed in
      // again — the "pushes suddenly stopped" symptom.
      const invalidToken = response.status === 404 ||
        /UNREGISTERED|INVALID_ARGUMENT|not a valid (FCM )?registration token/i
          .test(error);
      return { ok: false, invalidToken, error };
    }

    return { ok: true, invalidToken: false };
  } catch (e) {
    console.error(`[FCM] Error: ${e}`);
    return { ok: false, invalidToken: false, error: String(e) };
  }
}

// ── OAuth2 Access Token ──────────────────────────────────────────

export async function getAccessToken(serviceAccountKey: string): Promise<string> {
  const decoded = atob(serviceAccountKey);
  const serviceAccount = JSON.parse(decoded);

  const now = Math.floor(Date.now() / 1000);
  const expiry = now + 3600;

  const header = { alg: "RS256", typ: "JWT" };
  const headerB64 = btoa(JSON.stringify(header)).replace(/=/g, "");

  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: expiry,
  };
  const payloadB64 = btoa(JSON.stringify(payload)).replace(/=/g, "");

  const encoder = new TextEncoder();
  const data = encoder.encode(`${headerB64}.${payloadB64}`);

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

// ── Send Push to User ────────────────────────────────────────────

/**
 * Send an FCM push notification to all registered devices of a user.
 *
 * Computes the recipient's current unread badge count and includes it
 * in the APNs payload so the OS app icon badge updates even when the
 * app is not running.
 *
 * @param supabaseAdmin - Supabase client with service role key
 * @param userId - The target user's auth user ID
 * @param notification - { title, body } for the push
 * @param data - Arbitrary data payload (e.g. { type, referenceId, screen })
 * @returns { successCount, invalidTokensRemoved }
 */
export async function sendPushToUser(
  supabaseAdmin: SupabaseClient,
  userId: string,
  notification: PushNotification,
  data: Record<string, string>,
): Promise<{
  successCount: number;
  invalidTokensRemoved: number;
  failedCount: number;
}> {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
  const serviceAccountKey = Deno.env.get("FCM_SERVICE_ACCOUNT_KEY") ?? "";

  if (!projectId || !serviceAccountKey) {
    console.error("[FCM] Missing Firebase configuration");
    return { successCount: 0, invalidTokensRemoved: 0, failedCount: 0 };
  }

  // Compute badge count for the OS app icon
  const badgeCount = await getUnreadBadgeCount(supabaseAdmin, userId);
  console.log(`[FCM] Badge count for user ${userId}: ${badgeCount}`);

  // Look up device tokens
  const { data: tokens, error: tokenError } = await supabaseAdmin
    .from("device_tokens")
    .select("fcm_token, platform")
    .eq("customer_id", userId);

  if (tokenError) {
    console.error("[FCM] Token query ERROR:", JSON.stringify(tokenError));
    return { successCount: 0, invalidTokensRemoved: 0, failedCount: 0 };
  }

  if (!tokens || tokens.length === 0) {
    console.log("[FCM] No device tokens for user:", userId);
    return { successCount: 0, invalidTokensRemoved: 0, failedCount: 0 };
  }

  console.log(`[FCM] Sending to ${tokens.length} device(s) for user: ${userId}`);

  // Send to each device token
  const invalidTokens: string[] = [];
  let successCount = 0;
  let failedCount = 0;

  for (const tokenRow of tokens) {
    const result = await sendFcmPush(
      tokenRow.fcm_token,
      notification.title,
      notification.body,
      data,
      badgeCount,
      projectId,
      serviceAccountKey
    );

    if (result.ok) {
      successCount++;
    } else {
      failedCount++;
      if (result.invalidToken) {
        invalidTokens.push(tokenRow.fcm_token);
      } else {
        // Transient: keep the registration so the next push can reach it.
        console.warn(
          `[FCM] Delivery failed for user ${userId} (kept token): ${result.error}`,
        );
      }
    }
  }

  // Clean up invalid tokens
  if (invalidTokens.length > 0) {
    await supabaseAdmin
      .from("device_tokens")
      .delete()
      .in("fcm_token", invalidTokens);
    console.log(`[FCM] Removed ${invalidTokens.length} invalid tokens`);
  }

  console.log(
    `[FCM] Sent ${successCount}/${tokens.length} notifications to user ${userId}` +
      (failedCount > 0 ? ` (${failedCount} failed)` : ""),
  );

  return {
    successCount,
    invalidTokensRemoved: invalidTokens.length,
    failedCount,
  };
}

// ── CORS Headers ─────────────────────────────────────────────────

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
