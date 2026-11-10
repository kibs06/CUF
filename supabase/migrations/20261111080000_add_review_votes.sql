-- Review helpfulness votes (thumbs up / thumbs down).
--
-- Any signed-in user gets one vote per review: is_helpful = true means
-- "this review was helpful", false means "not helpful". Changing the vote
-- is an UPDATE (or upsert) on the same row; tapping the active vote again
-- removes it. Counts are aggregated client-side from these rows.
CREATE TABLE IF NOT EXISTS public.review_votes (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id         UUID NOT NULL REFERENCES public.reviews(id) ON DELETE CASCADE,
    user_id           UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    is_helpful        BOOLEAN NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT review_votes_one_per_user UNIQUE (review_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_review_votes_review_id
  ON public.review_votes(review_id);

ALTER TABLE public.review_votes ENABLE ROW LEVEL SECURITY;

-- Votes are public social proof, like the reviews themselves: anyone can
-- read them; only the voter can write their own row.
DROP POLICY IF EXISTS "Review votes are viewable by everyone"
  ON public.review_votes;
CREATE POLICY "Review votes are viewable by everyone"
  ON public.review_votes FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can manage their own review votes"
  ON public.review_votes;
CREATE POLICY "Users can manage their own review votes"
  ON public.review_votes FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Votes ride on the same public readability as reviews/review_images:
-- exempt from the trusted-device gate (a customer deciding whether a
-- review was helpful must never be device-challenged for it).
CREATE OR REPLACE FUNCTION public.device_gate_exempt_tables()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ARRAY[
    -- ── identity / the step-up flow itself ──
    'profiles',                   -- role routing + the profile load that
                                  -- decides which shell to show
    'trusted_devices',            -- the challenge READS this to decide
                                  -- whether to challenge; gating it would
                                  -- lock every new device out forever
    'device_secrets',             -- internal (no grants); gated for clarity
    'device_enforcement_policy',  -- internal (no grants)
    'failed_logins',              -- the login lockout counter is written
                                  -- during the password attempt, i.e.
                                  -- strictly BEFORE any step-up exists
    -- Login-time session claims (20261015000000): written by the client at
    -- sign-in/sign-out, before any step-up exists on a new device. Gating
    -- would lock a new device out of logging its own sign-in.
    'account_session_log',

    -- ── public catalog: readable by anon already ──
    'products', 'product_images', 'product_variants', 'product_color_images',
    'product_customizations', 'product_review_images',
    'stores', 'banners', 'inventory', 'story_entries', 'store_follows',
    'reviews', 'store_reviews', 'review_images', 'product_reviews',
    'payment_fee_config',
    -- virtual fitting V2.1 (`20260927180000_add_try_on_models.sql`): a seller's
    -- 3D handover. Exempt ON PURPOSE, and the opposite of a leak — an `active`
    -- row is world-readable already (that is what the RLS policy on that table
    -- says), and the gate would sit directly across the customer's product page,
    -- which reads this table to warm the renderer's model cache. Gating it would
    -- lock a customer out of the very bytes V3 hands to the camera. It holds
    -- nothing customer-private either: a storage path, a digest, a triangle
    -- count and the seller's own declared length, all of it the seller's own
    -- work.
    --
    -- ⚠️ Added 2026-09-28, found by `supabase/tests/admin_account_security.test.sql`
    -- assertion 31 in CI, not by hand — which is the guard doing its job: the
    -- table was created months after the sweep above and would otherwise have
    -- been gated silently the first time `install_device_gate_policies()` was
    -- re-run with the gate switched on. The hosted project's copy of this
    -- function still predates the entry (see `MIGRATIONS_LIVE_STATUS.md`), so
    -- re-apply this file before re-running that installer.
    'product_models',

    -- ── 360° foot scan (20261025000000): captured and read by the browser
    --    portal, which has no trusted-device step-up — gating would lock
    --    every web customer out of their own sweep. Owner-only RLS plus
    --    the private owner-scoped `foot-scans` bucket carry the protection.
    'foot_scan_jobs',

    -- ── virtual fitting AR effects (20261102000000): same shape as
    --    product_models above — `active` rows are catalog content served to
    --    the product page/portal for AR fitting. Found by
    --    `supabase/tests/admin_account_security.test.sql` assertion 33.
    'product_ar_effects',

    -- ── review helpfulness votes (20261111080000): public social proof on
    --    the same surfaces that already serve reviews to everyone.
    'review_votes',

    -- ── device-scoped, not account-sensitive: the push token is
    --    registered right after login and leaking it would give an
    --    attacker nothing they do not already have ──
    'device_tokens'
  ];
$$;

COMMENT ON FUNCTION public.device_gate_exempt_tables() IS
  'Tables deliberately outside the trusted-device gate, each for a concrete '
  'reason (see the comments at each entry). Shared by '
  'install_device_gate_policies() and the pgTAP guard so the two cannot drift.';

-- Re-converge: gate anything still ungated, leave the exempt list alone.
SELECT public.install_device_gate_policies();
