// supabase/functions/_shared/rate_limit.ts
//
// Shared fixed-window rate limiter for public Edge Functions (T6).
//
// Supabase has no built-in per-function rate limiting and this project
// has no CDN/WAF in front of the API, so the functions enforce their
// own limits against a Postgres counter table. The table + atomic
// increment RPC are created by migration
// 20260903030000_add_rate_limiting.sql. Each function that imports
// this helper must be deployed with the SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY secrets (already standard for every
// function in this repo).
//
// Limits are deliberately NOT magic numbers inside each handler — every
// caller passes an explicit per-route limit, and the values live next
// to the code that owns them (see each function's RATE_LIMITS block)
// so they can be tuned without touching the shared logic.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface RateLimitDecision {
  allowed: boolean;
  /** Seconds the caller must wait before retrying (only when !allowed). */
  retryAfterSeconds: number;
}

/// Best-effort client IP. Supabase's edge gateway forwards the real
/// client address in x-forwarded-for (comma-separated chain — the
/// left-most value is the original caller). Falls back to
/// cf-connecting-ip when present, then "unknown".
function clientIp(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for");
  if (fwd) {
    const first = fwd.split(",")[0].trim();
    if (first) return first;
  }
  const cf = req.headers.get("cf-connecting-ip");
  if (cf) return cf;
  return "unknown";
}

/// Checks one request against a fixed-window counter in Postgres.
///
/// @param bucket       logical name, e.g. "geocode-proxy:search"
/// @param limit        max requests per window for one IP
/// @param windowSeconds window length (default 60)
export async function checkRateLimit(
  req: Request,
  bucket: string,
  limit: number,
  windowSeconds = 60,
): Promise<RateLimitDecision> {
  const ip = clientIp(req);
  const nowSec = Math.floor(Date.now() / 1000);
  const windowStart = Math.floor(nowSec / windowSeconds) * windowSeconds;

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    // Misconfigured function — fail OPEN (allow) rather than break the
    // feature this function protects. The 429 path is a defense layer;
    // a config error must never take down address search / maps.
    console.error("[rate-limit] SUPABASE_URL/SERVICE_ROLE_KEY missing — skipping rate limit");
    return { allowed: true, retryAfterSeconds: 0 };
  }
  const supabase = createClient(supabaseUrl, serviceKey);

  const key = `${bucket}:${ip}:${windowStart}`;
  try {
    const { data: count, error } = await supabase.rpc("rate_limit_increment", {
      p_key: key,
      p_window_start: new Date(windowStart * 1000).toISOString(),
      p_ttl_seconds: windowSeconds,
    });

    if (error) {
      // Fail OPEN on infra errors (rate-limit table missing, DB hiccup)
      // — never 429 legitimate traffic because the counter store is down.
      console.error(`[rate-limit] check failed for ${bucket}:`, error.message);
      return { allowed: true, retryAfterSeconds: 0 };
    }

    const used = Number(count ?? 1);
    if (used <= limit) {
      return { allowed: true, retryAfterSeconds: 0 };
    }

    const retryAfter = Math.max(1, windowStart + windowSeconds - nowSec);
    console.warn(
      `[rate-limit] 429 ${bucket} ip=${ip} used=${used} limit=${limit} retryAfter=${retryAfter}s`,
    );
    return { allowed: false, retryAfterSeconds: retryAfter };
  } catch (e) {
    console.error(`[rate-limit] unexpected error for ${bucket}:`, (e as Error)?.message ?? e);
    return { allowed: true, retryAfterSeconds: 0 };
  }
}

/// Builds the standard 429 response with Retry-After + CORS headers.
export function rateLimitedResponse(
  decision: RateLimitDecision,
  corsHeaders: Record<string, string>,
): Response {
  return new Response(
    JSON.stringify({
      error: "rate limited",
      message: "Too many requests — please slow down and try again shortly.",
    }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": String(decision.retryAfterSeconds),
      },
    },
  );
}