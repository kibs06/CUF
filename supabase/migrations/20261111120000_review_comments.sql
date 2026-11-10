-- Review discussion thread (2026-11-11).
--
-- The review author can reply under the seller's reply, and any other
-- signed-in customer can comment on the thread too. Flat list anchored
-- to the review (no nesting) — newest last, like a Shopee reply thread.
CREATE TABLE IF NOT EXISTS public.review_comments (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id         UUID NOT NULL REFERENCES public.reviews(id) ON DELETE CASCADE,
    user_id           UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    comment           TEXT NOT NULL CHECK (char_length(comment) BETWEEN 1 AND 500),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_review_comments_review_id
  ON public.review_comments(review_id);

DROP TRIGGER IF EXISTS trg_review_comments_updated_at ON public.review_comments;
CREATE TRIGGER trg_review_comments_updated_at
  BEFORE UPDATE ON public.review_comments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.review_comments ENABLE ROW LEVEL SECURITY;

-- Comments are public social proof, like reviews/votes: anyone can read;
-- only the author can write their own row.
DROP POLICY IF EXISTS "Review comments are viewable by everyone"
  ON public.review_comments;
CREATE POLICY "Review comments are viewable by everyone"
  ON public.review_comments FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can manage their own review comments"
  ON public.review_comments;
CREATE POLICY "Users can manage their own review comments"
  ON public.review_comments FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Comments ride on the same public readability as reviews/votes: exempt
-- from the trusted-device gate (a customer reading a review thread must
-- never be device-challenged for it). Full-list redefinition per the
-- established pattern (see 20261111080000) — this runs after it, so the
-- list below is that file's plus 'review_comments'.
CREATE OR REPLACE FUNCTION public.device_gate_exempt_tables()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ARRAY[
    'profiles',
    'trusted_devices',
    'device_secrets',
    'device_enforcement_policy',
    'failed_logins',
    'account_session_log',
    'products', 'product_images', 'product_variants', 'product_color_images',
    'product_customizations', 'product_review_images',
    'stores', 'banners', 'inventory', 'story_entries', 'store_follows',
    'reviews', 'store_reviews', 'review_images', 'product_reviews',
    'payment_fee_config',
    'product_models',
    'foot_scan_jobs',
    'product_ar_effects',
    'review_votes',
    -- ── review discussion comments (20261111120000): public social proof
    --    on the same surfaces that already serve reviews to everyone.
    'review_comments',
    'device_tokens'
  ];
$$;

COMMENT ON FUNCTION public.device_gate_exempt_tables() IS
  'Tables deliberately outside the trusted-device gate, each for a concrete '
  'reason (see the comments at each entry). Shared by '
  'install_device_gate_policies() and the pgTAP guard so the two cannot drift.';

-- Re-converge: gate anything still ungated, leave the exempt list alone.
SELECT public.install_device_gate_policies();

-- Admit the seller-side discussion notice to the bell type CHECK.
ALTER TABLE public.seller_notifications
  DROP CONSTRAINT IF EXISTS seller_notifications_type_check;

ALTER TABLE public.seller_notifications
  ADD CONSTRAINT seller_notifications_type_check
    CHECK (
      type IN (
        'new_order',
        'stale_order',
        'low_stock',
        'custom_order_request',
        'new_message',
        'model_request',
        'return_request',
        'new_review',
        'review_comment'
      )
    );
