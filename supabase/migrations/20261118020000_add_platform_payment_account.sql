-- ══════════════════════════════════════════════════════════════════
-- Migration: Platform GCash account + platform settings
-- Date: 2026-11-18
--
-- Purpose: the marketplace collects every online GCash payment into ONE
--          admin-controlled account, then remits each seller their share
--          at the end of the day. This migration adds:
--
--   1. platform_payment_accounts — the receiving GCash number(s) shown to
--      customers at checkout. Exactly ONE row may be active at a time
--      (partial unique index), so the checkout screen always has a
--      single unambiguous destination. Rotating accounts = deactivate
--      the old row, activate the new one (no history is lost: orders
--      store payment_account_id).
--
--   2. platform_settings — singleton for the payout math:
--      • platform_fee_bps  — marketplace commission on the goods value,
--        0 by default (nothing is taken from sellers until the admin
--        raises it). Excludes the delivery pass-through.
--      • delivery_fee_amount — the flat ₱100 line the checkout already
--        charges; the platform keeps it to pay the courier, so it is
--        carved OUT of the seller payout rather than paid to them.
--
-- No seed data: an account row with a made-up number would be worse than
-- none (customers would pay a stranger). Until an admin adds an active
-- account, create_gcash_checkout refuses new checkouts and the app shows
-- a clearly-labelled "GCash is being set up" state.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. platform_payment_accounts
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.platform_payment_accounts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  label         TEXT NOT NULL DEFAULT 'Platform GCash',
  gcash_number  TEXT NOT NULL,
  account_name  TEXT NOT NULL,
  -- Public URL of the receive-money QR image (safe to show: it only
  -- encodes the number above). NULL = show the number only.
  qr_url        TEXT,
  is_active     BOOLEAN NOT NULL DEFAULT false,
  created_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_platform_account_number
    CHECK (gcash_number ~ '^[0-9+][0-9 \-]{6,19}$'),
  CONSTRAINT chk_platform_account_name
    CHECK (length(btrim(account_name)) >= 2)
);

-- At most ONE active account. A unique index on the boolean restricted to
-- the active rows means a second activation fails with 23505 instead of
-- silently showing customers two different numbers.
CREATE UNIQUE INDEX IF NOT EXISTS uq_platform_payment_accounts_single_active
  ON public.platform_payment_accounts (is_active)
  WHERE is_active;

CREATE INDEX IF NOT EXISTS idx_platform_payment_accounts_created
  ON public.platform_payment_accounts (created_at DESC);

COMMENT ON TABLE public.platform_payment_accounts IS
  'Receiving GCash accounts for online checkout. Exactly one active row (partial unique index). Orders reference the account that was shown via orders.payment_account_id. Admin-managed; no client write path.';

ALTER TABLE public.platform_payment_accounts ENABLE ROW LEVEL SECURITY;

-- Signed-in users (the checkout screen) may read the ACTIVE account only.
DROP POLICY IF EXISTS "Signed-in users can read the active payment account"
  ON public.platform_payment_accounts;
CREATE POLICY "Signed-in users can read the active payment account"
  ON public.platform_payment_accounts FOR SELECT
  TO authenticated
  USING (is_active);

-- Admins read every row (including retired accounts) and manage them.
DROP POLICY IF EXISTS "Admins can read all payment accounts"
  ON public.platform_payment_accounts;
CREATE POLICY "Admins can read all payment accounts"
  ON public.platform_payment_accounts FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can insert payment accounts"
  ON public.platform_payment_accounts;
CREATE POLICY "Admins can insert payment accounts"
  ON public.platform_payment_accounts FOR INSERT
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can update payment accounts"
  ON public.platform_payment_accounts;
CREATE POLICY "Admins can update payment accounts"
  ON public.platform_payment_accounts FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can delete payment accounts"
  ON public.platform_payment_accounts;
CREATE POLICY "Admins can delete payment accounts"
  ON public.platform_payment_accounts FOR DELETE
  USING (public.is_admin());

-- ────────────────────────────────────────────────────────────────
-- 2. platform_settings (singleton)
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.platform_settings (
  id                    INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  platform_fee_bps      INT NOT NULL DEFAULT 0
                          CHECK (platform_fee_bps BETWEEN 0 AND 5000),
  delivery_fee_amount   NUMERIC(12,2) NOT NULL DEFAULT 100
                          CHECK (delivery_fee_amount >= 0),
  updated_by            UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  note                  TEXT
);

INSERT INTO public.platform_settings (id, platform_fee_bps, delivery_fee_amount, note)
VALUES (1, 0, 100,
        'Default: 0% commission, ₱100 flat delivery pass-through. Update platform_fee_bps here — never in code.')
ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE public.platform_settings IS
  'Singleton payout configuration. platform_fee_bps = commission on goods value (excludes delivery). delivery_fee_amount = flat delivery line charged at checkout and kept by the platform to pay the courier, so it is excluded from seller payouts.';

ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Signed-in users can read platform settings"
  ON public.platform_settings;
CREATE POLICY "Signed-in users can read platform settings"
  ON public.platform_settings FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Admins can update platform settings"
  ON public.platform_settings;
CREATE POLICY "Admins can update platform settings"
  ON public.platform_settings FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ────────────────────────────────────────────────────────────────
-- 3. Public bucket for the receive-money QR image
--    (a QR of the platform number carries no personal data; the proofs
--    bucket stays private)
-- ────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('platform-payment-qr', 'platform-payment-qr', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Admins can upload platform payment QR" ON storage.objects;
CREATE POLICY "Admins can upload platform payment QR"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'platform-payment-qr'
    AND public.is_admin()
  );

DROP POLICY IF EXISTS "Admins can replace platform payment QR" ON storage.objects;
CREATE POLICY "Admins can replace platform payment QR"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'platform-payment-qr' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can delete platform payment QR" ON storage.objects;
CREATE POLICY "Admins can delete platform payment QR"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'platform-payment-qr' AND public.is_admin());

-- ────────────────────────────────────────────────────────────────
-- 4. Admin readers on the private proof bucket
--    (the admin verification queue must open the customer's screenshot)
-- ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Admins can read payment proofs" ON storage.objects;
CREATE POLICY "Admins can read payment proofs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'payment-proofs'
    AND public.is_admin()
  );

-- ────────────────────────────────────────────────────────────────
-- 5. Device-gate exemptions for the two new config tables
--    public.device_gate_exempt_tables() is the single source of truth the
--    gate installer and the admin_account_security invariant test both
--    read, so a table is either listed there or must carry the
--    "Require a trusted device" policy. These two are read on the checkout
--    path exactly like payment_fee_config / stores (which are already
--    exempt): they hold the platform's own number and the payout rates,
--    never another user's data. seller_payouts / seller_payout_items, in
--    the payouts migration, are money data and ARE gated.
--
--    The list below is the previous list verbatim plus the two new names.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.device_gate_exempt_tables()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ARRAY[
    -- identity / the step-up flow itself
    'profiles',
    'trusted_devices',
    'device_secrets',
    'device_enforcement_policy',
    'failed_logins',
    'account_session_log',

    -- public catalog: readable by anon already
    'products', 'product_images', 'product_variants', 'product_color_images',
    'product_color_paint',
    'product_customizations', 'product_review_images',
    'stores', 'banners', 'inventory', 'story_entries', 'store_follows',
    'reviews', 'store_reviews', 'review_images', 'product_reviews',
    'payment_fee_config',
    'product_models',
    'foot_scan_jobs',
    'product_ar_effects',
    'review_votes',
    'review_comments',
    'device_tokens',

    -- checkout pricing / destination (this migration)
    'platform_payment_accounts',
    'platform_settings'
  ];
$$;

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- SELECT count(*) FROM public.platform_payment_accounts WHERE is_active;
-- SELECT * FROM public.platform_settings;
-- SELECT id, public FROM storage.buckets WHERE id = 'platform-payment-qr';
