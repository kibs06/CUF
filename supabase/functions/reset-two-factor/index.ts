// supabase/functions/reset-two-factor/index.ts
//
// Supabase Edge Function: turn off a user's authenticator-app 2FA after they
// lost the device, by proving they can read the account's email.
//
// Called by: Dart client (MfaVerifyScreen, "Lost your authenticator?") via
//            Supabase.functions.invoke, AFTER the user has entered the code
//            from an email OTP sign-in.
// Auth:      Bearer token from that email-OTP session.
//
// Why a server function: Supabase refuses to unenroll a verified factor from
// an AAL1 session ("AAL2 required to unenroll verified factor"), and the user
// in this flow only has AAL1. The admin API can delete the factor, but the
// service-role key must never reach the client, so the deletion lives here.
//
// Why the email code is the proof: the access token's `amr` claim records how
// the session was created. A password session carries `password`; only an
// email-OTP session carries `otp` (or `magiclink`). Requiring a RECENT one
// means the caller read the code from the inbox, not just knew the password.
//
// Deleting a verified factor logs the user out of every session (Supabase
// behaviour), so the client signs out after this returns.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getSupabaseAdmin, corsHeaders } from "../_shared/push.ts";

/** How long after the email code was used the reset is still accepted. */
const MAX_CODE_AGE_SECONDS = 600;

/** AMR methods that prove the caller read a code or link from their inbox. */
const EMAIL_PROOF_METHODS = new Set(["otp", "magiclink"]);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Decodes the payload of a JWT without verifying it (the caller already did). */
function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const part = token.split(".")[1];
    if (!part) return null;
    const base64 = part.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
    return JSON.parse(atob(padded)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/** True when the session was created by an email code used recently. */
function hasRecentEmailProof(claims: Record<string, unknown>): boolean {
  const amr = claims.amr;
  if (!Array.isArray(amr)) return false;
  const now = Math.floor(Date.now() / 1000);
  return amr.some((entry) => {
    if (typeof entry !== "object" || entry === null) return false;
    const { method, timestamp } = entry as Record<string, unknown>;
    return (
      typeof method === "string" &&
      EMAIL_PROOF_METHODS.has(method) &&
      typeof timestamp === "number" &&
      now - timestamp <= MAX_CODE_AGE_SECONDS
    );
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    const token = authHeader?.replace(/^Bearer\s+/i, "") ?? "";
    if (!authHeader || !token) {
      return json({ error: "Missing authorization header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();
    if (authError || !user) {
      return json({ error: "Unauthorized" }, 401);
    }

    const claims = decodeJwtPayload(token);
    if (!claims || !hasRecentEmailProof(claims)) {
      return json({ error: "recent_email_code_required" }, 403);
    }

    const admin = getSupabaseAdmin();
    const { data: listed, error: listError } =
      await admin.auth.admin.mfa.listFactors({ userId: user.id });
    if (listError) {
      console.error("[ResetTwoFactor] listFactors failed:", listError);
      return json({ error: "Could not read 2FA factors" }, 500);
    }

    const verified = (listed?.factors ?? []).filter(
      (f: { status: string }) => f.status === "verified",
    );

    for (const factor of verified) {
      const { error: deleteError } = await admin.auth.admin.mfa.deleteFactor({
        id: factor.id,
        userId: user.id,
      });
      if (deleteError) {
        console.error("[ResetTwoFactor] deleteFactor failed:", deleteError);
        return json({ error: "Could not turn off 2FA" }, 500);
      }
    }

    console.log(
      `[ResetTwoFactor] User ${user.id} removed ${verified.length} verified factor(s)`,
    );
    return json({ success: true, removed: verified.length });
  } catch (e) {
    console.error("[ResetTwoFactor] Error:", e);
    return json({ error: String(e) }, 500);
  }
});
