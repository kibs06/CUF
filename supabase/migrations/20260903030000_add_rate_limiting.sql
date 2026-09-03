-- ══════════════════════════════════════════════════════════════════
-- Migration: Edge Function rate limiting (Threat T6)
-- Date: 2026-09-03
--
-- Problem: no application-level rate limiting exists on any public
-- Edge Function. Supabase has no built-in per-function rate limiting
-- on any plan tier, and there is no CDN/WAF in front of the project,
-- so the functions themselves must enforce it.
--
-- Approach: a fixed-window counter persisted in Postgres, keyed by
--   <bucket>:<client-ip>:<window-start>.
-- Buckets are per-function/per-route (e.g. "geocode-proxy:search",
-- "gcash-webhook", "product-preview"). Windows roll every N seconds,
-- so the same key naturally resets next window; old rows are purged
-- opportunistically.
--
-- Access: only service_role may call rate_limit_increment — Edge
-- Functions call it through their service-role client. anon and
-- authenticated cannot read or manipulate counters.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.function_rate_limits (
    key          TEXT PRIMARY KEY,
    count        INTEGER NOT NULL DEFAULT 1,
    window_start TIMESTAMPTZ NOT NULL,
    expires_at   TIMESTAMPTZ NOT NULL
);

COMMENT ON TABLE public.function_rate_limits IS
    'Fixed-window rate-limit counters for public Edge Functions (T6). '
    'Key = <bucket>:<client-ip>:<window-start>. Written ONLY by the '
    'rate_limit_increment RPC (service_role). Rows self-expire via '
    'opportunistic cleanup inside the RPC.';

-- Atomic increment: INSERT-or-add-one and return the new count. The
-- ON CONFLICT upsert is atomic, so concurrent requests (e.g. a burst
-- of map-tile fetches) cannot lose counts to read-modify-write races.
CREATE OR REPLACE FUNCTION public.rate_limit_increment(
    p_key             TEXT,
    p_window_start    TIMESTAMPTZ,
    p_ttl_seconds     INT
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    INSERT INTO public.function_rate_limits (key, count, window_start, expires_at)
    VALUES (
        p_key,
        1,
        p_window_start,
        p_window_start + make_interval(secs => p_ttl_seconds)
    )
    ON CONFLICT (key) DO UPDATE
        SET count = public.function_rate_limits.count + 1
    RETURNING count INTO v_count;

    -- Opportunistic cleanup: purge expired windows every ~500 hits so
    -- the table never grows without bound (one row per active bucket
    -- per window is tiny, but clean anyway).
    IF v_count % 500 = 0 THEN
        DELETE FROM public.function_rate_limits WHERE expires_at < now();
    END IF;

    RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.rate_limit_increment(TEXT, TIMESTAMPTZ, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rate_limit_increment(TEXT, TIMESTAMPTZ, INT) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.rate_limit_increment(TEXT, TIMESTAMPTZ, INT) TO service_role;

REVOKE ALL ON TABLE public.function_rate_limits FROM PUBLIC;
REVOKE ALL ON TABLE public.function_rate_limits FROM anon, authenticated;
GRANT  ALL ON TABLE public.function_rate_limits TO service_role;

COMMENT ON FUNCTION public.rate_limit_increment(TEXT, TIMESTAMPTZ, INT) IS
    'Atomically increments the fixed-window counter for p_key and returns '
    'the new count. Service-role only — called by Edge Function rate '
    'limiters (supabase/functions/_shared/rate_limit.ts).';