-- ══════════════════════════════════════════════════════════════════
-- Reviews / Ratings / Sold foundation (2026-11-12)
--
-- Consolidates everything shipped so far into one solid base:
--   • reviews            (per-order-item, primary — rating-only rows allowed,
--                         comment NULL)
--   • product_reviews    (legacy per-product)
--   • store_reviews      (direct "rate this store")
--   • review_votes       (helpful / not-helpful)
--   • review_comments    (discussion thread)
--   • products.avg_rating / review_count  (trigger-maintained)
--   • stores.rating / review_count        (trigger-maintained)
--
-- What this migration fixes / adds:
--   1. Blank-comment hygiene — whitespace-only comments are normalized to
--      NULL and a CHECK keeps them out going forward, so rating-only rows
--      (stars, no text) are first-class on every surface.
--   2. RLS status fix — the insert policy demanded o.status = 'received'
--      while the app treats 'ready' / 'received' / 'delivered' as
--      reviewable (canReview + submitReview). Buyers with ready/delivered
--      orders were wrongly blocked at the DB. Now the policy matches.
--   3. Seller-reply guard — the customer edit-window UPDATE policy covers
--      the whole row, so a customer could set seller_reply on their own
--      review. Only the store owner (or admin) may change it now, mirroring
--      guard_review_pin().
--   4. Vote counters — reviews.helpful_count / not_helpful_count,
--      trigger-maintained from review_votes, so counts are readable without
--      client-side aggregation (backfilled for existing rows).
--   5. product_sales() — the sold-count rule (paid, non-cancelled orders)
--      codified in the DB as a SECURITY DEFINER function both clients can
--      call, instead of living only in Dart.
--   6. Missing indexes for the rating filter chips / breakdown queries.
--   7. Backfill of products aggregates with the same weighted math as the
--      live trigger.
--
-- Idempotent throughout (IF NOT EXISTS / DROP IF EXISTS / CREATE OR
-- REPLACE) so it can be re-run safely.
-- ══════════════════════════════════════════════════════════════════

-- ─── 1. Blank-comment hygiene ────────────────────────────────────
-- Rating-only reviews store comment = NULL (the app already sends NULL
-- for empty text). Normalize any legacy '' / whitespace rows first so the
-- CHECK below passes on existing data.
UPDATE public.reviews
SET comment = NULL
WHERE comment IS NOT NULL AND char_length(btrim(comment)) = 0;

UPDATE public.store_reviews
SET comment = NULL
WHERE comment IS NOT NULL AND char_length(btrim(comment)) = 0;

ALTER TABLE public.reviews
  DROP CONSTRAINT IF EXISTS reviews_comment_not_blank;
ALTER TABLE public.reviews
  ADD CONSTRAINT reviews_comment_not_blank
  CHECK (comment IS NULL OR char_length(btrim(comment)) > 0);

ALTER TABLE public.store_reviews
  DROP CONSTRAINT IF EXISTS store_reviews_comment_not_blank;
ALTER TABLE public.store_reviews
  ADD CONSTRAINT store_reviews_comment_not_blank
  CHECK (comment IS NULL OR char_length(btrim(comment)) > 0);

-- ─── 2. RLS: reviewable statuses match the app ───────────────────
-- App rule (ReviewService.canReview / submitReview): an order item is
-- reviewable when its order is 'ready', 'received', or 'delivered'.
DROP POLICY IF EXISTS "Customers can insert reviews for delivered orders"
  ON public.reviews;
CREATE POLICY "Customers can insert reviews for reviewable orders"
  ON public.reviews FOR INSERT
  WITH CHECK (
    auth.uid() = customer_id
    AND EXISTS (
      SELECT 1
      FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
      WHERE oi.id = reviews.order_item_id
        AND o.customer_id = auth.uid()
        AND o.status IN ('ready', 'received', 'delivered')
    )
  );

-- ─── 3. Seller-reply guard ───────────────────────────────────────
-- Customers keep their edit-window UPDATE policy (rating/comment), but
-- seller_reply / seller_reply_at may only move via the store owner (or
-- an admin) — same shape as guard_review_pin().
CREATE OR REPLACE FUNCTION public.guard_review_reply()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.seller_reply IS NOT NULL OR NEW.seller_reply_at IS NOT NULL THEN
      IF NOT (
        public.is_admin()
        OR EXISTS (
          SELECT 1 FROM public.stores
          WHERE stores.id = NEW.store_id
            AND stores.owner_id = auth.uid()
        )
      ) THEN
        RAISE EXCEPTION 'Only the seller can write a seller reply';
      END IF;
    END IF;
  ELSIF NEW.seller_reply IS DISTINCT FROM OLD.seller_reply
     OR NEW.seller_reply_at IS DISTINCT FROM OLD.seller_reply_at
  THEN
    IF NOT (
      public.is_admin()
      OR EXISTS (
        SELECT 1 FROM public.stores
        WHERE stores.id = NEW.store_id
          AND stores.owner_id = auth.uid()
      )
    ) THEN
      RAISE EXCEPTION 'Only the seller can change a seller reply';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.guard_review_reply() IS
  'Only a store owner (or admin) may set or change seller_reply / '
  'seller_reply_at on reviews — the customer edit-window UPDATE policy '
  'must never be a reply door.';

DROP TRIGGER IF EXISTS trg_guard_review_reply ON public.reviews;
CREATE TRIGGER trg_guard_review_reply
  BEFORE INSERT OR UPDATE OF seller_reply, seller_reply_at ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.guard_review_reply();

-- ─── 4. Vote counters on reviews ─────────────────────────────────
ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS helpful_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS not_helpful_count INTEGER NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.refresh_review_vote_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  target_review UUID;
BEGIN
  target_review := COALESCE(NEW.review_id, OLD.review_id);

  UPDATE public.reviews
  SET
    helpful_count = (
      SELECT COUNT(*)::INTEGER FROM public.review_votes
      WHERE review_id = target_review AND is_helpful
    ),
    not_helpful_count = (
      SELECT COUNT(*)::INTEGER FROM public.review_votes
      WHERE review_id = target_review AND NOT is_helpful
    )
  WHERE id = target_review;

  RETURN NULL;
END;
$fn$;

COMMENT ON FUNCTION public.refresh_review_vote_counts() IS
  'Keeps reviews.helpful_count / not_helpful_count in sync with '
  'review_votes (insert, vote flip, or vote removal).';

DROP TRIGGER IF EXISTS trg_refresh_review_vote_counts
  ON public.review_votes;
CREATE TRIGGER trg_refresh_review_vote_counts
  AFTER INSERT OR UPDATE OF is_helpful OR DELETE ON public.review_votes
  FOR EACH ROW EXECUTE FUNCTION public.refresh_review_vote_counts();

-- Backfill counters for reviews that already have votes.
UPDATE public.reviews r
SET
  helpful_count = COALESCE(v.helpful, 0),
  not_helpful_count = COALESCE(v.not_helpful, 0)
FROM (
  SELECT
    review_id,
    COUNT(*) FILTER (WHERE is_helpful)::INTEGER AS helpful,
    COUNT(*) FILTER (WHERE NOT is_helpful)::INTEGER AS not_helpful
  FROM public.review_votes
  GROUP BY review_id
) v
WHERE r.id = v.review_id;

-- ─── 5. Sold counts as a DB function ─────────────────────────────
-- The revenue-completion rule the app uses (paid AND non-cancelled
-- orders), codified once so every client reads the same numbers.
-- SECURITY DEFINER: order_items/orders are not publicly readable, but the
-- per-product totals are public social proof (shown on cards to guests).
CREATE OR REPLACE FUNCTION public.product_sales()
RETURNS TABLE (product_id TEXT, units_sold BIGINT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT
    oi.product_id::TEXT AS product_id,
    SUM(oi.quantity)::BIGINT AS units_sold
  FROM public.order_items oi
  JOIN public.orders o ON o.id = oi.order_id
  WHERE o.status <> 'cancelled'
    AND o.payment_status = 'paid'
  GROUP BY oi.product_id;
$$;

COMMENT ON FUNCTION public.product_sales() IS
  'Units sold per product across paid, non-cancelled orders — the single '
  'source of truth for sold counters (cards, detail header, best sellers).';

GRANT EXECUTE ON FUNCTION public.product_sales() TO anon, authenticated;

-- ─── 6. Indexes for the review surfaces ──────────────────────────
-- Rating filter chips + breakdown bars read (product_id, rating).
CREATE INDEX IF NOT EXISTS idx_reviews_product_rating
  ON public.reviews(product_id, rating);

-- Seller "latest first" feeds read (store_id, created_at).
CREATE INDEX IF NOT EXISTS idx_reviews_store_created
  ON public.reviews(store_id, created_at DESC);

-- "My votes" lookups read (user_id).
CREATE INDEX IF NOT EXISTS idx_review_votes_user_id
  ON public.review_votes(user_id);

-- ─── 7. Backfill product aggregates ──────────────────────────────
-- Same weighted math as refresh_product_rating(): primary `reviews`
-- merged with legacy `product_reviews` when that table exists.
DO $$
DECLARE
  p RECORD;
  v_avg NUMERIC;
  v_count INTEGER;
  pr_avg NUMERIC;
  pr_count INTEGER;
BEGIN
  FOR p IN SELECT id FROM public.products LOOP
    SELECT ROUND(AVG(rating)::numeric, 1), COUNT(*)::INTEGER
    INTO v_avg, v_count
    FROM public.reviews
    WHERE product_id = p.id;

    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'product_reviews'
    ) THEN
      SELECT ROUND(AVG(rating)::numeric, 1), COUNT(*)::INTEGER
      INTO pr_avg, pr_count
      FROM public.product_reviews
      WHERE product_id = p.id;

      IF COALESCE(pr_count, 0) > 0 THEN
        IF COALESCE(v_count, 0) > 0 THEN
          v_avg := ROUND(
            ((v_avg * v_count) + (pr_avg * pr_count)) / (v_count + pr_count),
            1
          );
        ELSE
          v_avg := pr_avg;
        END IF;
        v_count := COALESCE(v_count, 0) + pr_count;
      END IF;
    END IF;

    UPDATE public.products
    SET
      avg_rating = COALESCE(v_avg, 0),
      review_count = COALESCE(v_count, 0)
    WHERE id = p.id;
  END LOOP;
END
$$;

-- ─── 8. Device gate ──────────────────────────────────────────────
-- No new tables in this migration (vote counts are columns, sales are a
-- function), so device_gate_exempt_tables() is unchanged: reviews,
-- review_votes, and review_comments are already exempt.
