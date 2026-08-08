-- ══════════════════════════════════════════════════════════════════
-- Direct Store Reviews ("Rate this store")
-- Date: 2026-08-08
--
-- Lets customers rate a STORE directly (1-5 stars + optional comment),
-- separate from per-order-item product reviews. One review per customer
-- per store (UNIQUE store_id + customer_id).
--
-- The store rating becomes a 3-source weighted aggregate, mirroring how
-- refresh_product_rating() merges tables by count:
--   1. public.reviews          (per-order-item product reviews, has store_id)
--   2. public.product_reviews  (legacy product reviews, store via products)
--   3. public.store_reviews    (NEW — direct store reviews)
--
-- This migration supersedes the 2-source refresh_store_rating*()
-- functions created in 20260807000000_add_store_rating_aggregation.sql
-- (CREATE OR REPLACE) and re-attaches the triggers.
--
-- ⚠️  Live DB id types: products.id, orders.id, order_items.id are UUID
--     in the live DB. All FKs here are UUID.
-- ══════════════════════════════════════════════════════════════════

-- ─── 1. STORE_REVIEWS table ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.store_reviews (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id    UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE (store_id, customer_id)  -- one store review per customer per store
);

CREATE INDEX IF NOT EXISTS idx_store_reviews_store_id
  ON public.store_reviews(store_id);
CREATE INDEX IF NOT EXISTS idx_store_reviews_customer_id
  ON public.store_reviews(customer_id);

-- ─── 2. TRIGGER: auto-set updated_at ───────────────────────────────
DROP TRIGGER IF EXISTS trg_store_reviews_updated_at ON public.store_reviews;
CREATE TRIGGER trg_store_reviews_updated_at
  BEFORE UPDATE ON public.store_reviews
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── 3. ROW LEVEL SECURITY ─────────────────────────────────────────
ALTER TABLE public.store_reviews ENABLE ROW LEVEL SECURITY;

-- Anyone can read store reviews (public)
DROP POLICY IF EXISTS "Store reviews are viewable by everyone"
  ON public.store_reviews;
CREATE POLICY "Store reviews are viewable by everyone"
  ON public.store_reviews FOR SELECT USING (true);

-- Verified buyers only: must have a 'received' order from this store.
-- (UNIQUE(store_id, customer_id) additionally enforces one per customer.)
DROP POLICY IF EXISTS "Customers can rate stores after receiving an order"
  ON public.store_reviews;
CREATE POLICY "Customers can rate stores after receiving an order"
  ON public.store_reviews FOR INSERT
  WITH CHECK (
    auth.uid() = customer_id
    AND EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.customer_id = auth.uid()
        AND o.store_id = store_reviews.store_id
        AND o.status = 'received'
    )
  );

-- Customer can update their own store review
DROP POLICY IF EXISTS "Customers can update own store reviews"
  ON public.store_reviews;
CREATE POLICY "Customers can update own store reviews"
  ON public.store_reviews FOR UPDATE
  USING (auth.uid() = customer_id);

-- Customer can delete their own store review
DROP POLICY IF EXISTS "Customers can delete own store reviews"
  ON public.store_reviews;
CREATE POLICY "Customers can delete own store reviews"
  ON public.store_reviews FOR DELETE
  USING (auth.uid() = customer_id);

-- ─── 4. Shared aggregation helper (now 3 sources, weighted by count) ─
-- Replaces the 2-source version from 20260807000000.
CREATE OR REPLACE FUNCTION public.refresh_store_rating_stats(target_store UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_avg    NUMERIC;
  v_count  INTEGER;
  pr_avg   NUMERIC;
  pr_count INTEGER;
  sr_avg   NUMERIC;
  sr_count INTEGER;
BEGIN
  -- Unreachable store (e.g. legacy review whose product was deleted) —
  -- nothing to update, exit without erroring.
  IF target_store IS NULL THEN
    RETURN;
  END IF;

  -- Source 1: per-order-item reviews (has store_id directly)
  SELECT ROUND(AVG(rating)::numeric, 1), COUNT(*)::INTEGER
  INTO v_avg, v_count
  FROM public.reviews
  WHERE store_id = target_store;

  -- Source 2: legacy product_reviews — no store_id, join through products
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'product_reviews'
  ) THEN
    SELECT ROUND(AVG(pr.rating)::numeric, 1), COUNT(*)::INTEGER
    INTO pr_avg, pr_count
    FROM public.product_reviews pr
    JOIN public.products p ON p.id = pr.product_id
    WHERE p.store_id = target_store;

    IF pr_count > 0 THEN
      IF v_count > 0 THEN
        v_avg := ROUND(
          ((v_avg * v_count) + (pr_avg * pr_count)) / (v_count + pr_count),
          1
        );
      ELSE
        v_avg := pr_avg;
      END IF;
      v_count := v_count + pr_count;
    END IF;
  END IF;

  -- Source 3: direct store reviews
  SELECT ROUND(AVG(rating)::numeric, 1), COUNT(*)::INTEGER
  INTO sr_avg, sr_count
  FROM public.store_reviews
  WHERE store_id = target_store;

  IF sr_count > 0 THEN
    IF v_count > 0 THEN
      v_avg := ROUND(
        ((v_avg * v_count) + (sr_avg * sr_count)) / (v_count + sr_count),
        1
      );
    ELSE
      v_avg := sr_avg;
    END IF;
    v_count := v_count + sr_count;
  END IF;

  -- Write back: NULL rating when the store has no reviews at all
  UPDATE public.stores
  SET
    rating       = CASE
                     WHEN COALESCE(v_count, 0) > 0 THEN COALESCE(v_avg, 0)
                     ELSE NULL
                   END,
    review_count = COALESCE(v_count, 0)
  WHERE id = target_store;
END;
$$;

-- ─── 5. Trigger function: resolve the affected store, then aggregate ─
-- Replaces the 2-source version from 20260807000000.
CREATE OR REPLACE FUNCTION public.refresh_store_rating()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  target_store UUID;
BEGIN
  IF TG_TABLE_NAME IN ('reviews', 'store_reviews') THEN
    -- Both have store_id directly
    target_store := COALESCE(NEW.store_id, OLD.store_id);
  ELSE
    -- product_reviews has no store_id — resolve via the product
    SELECT store_id INTO target_store
    FROM public.products
    WHERE id = COALESCE(NEW.product_id, OLD.product_id);
  END IF;

  PERFORM public.refresh_store_rating_stats(target_store);
  RETURN NULL;
END;
$$;

-- ─── 6. Attach triggers to ALL three review tables ─────────────────
DROP TRIGGER IF EXISTS trg_refresh_store_rating ON public.reviews;
CREATE TRIGGER trg_refresh_store_rating
  AFTER INSERT OR UPDATE OF rating OR DELETE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.refresh_store_rating();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'product_reviews'
  ) THEN
    DROP TRIGGER IF EXISTS trg_refresh_store_rating ON public.product_reviews;
    CREATE TRIGGER trg_refresh_store_rating
      AFTER INSERT OR UPDATE OF rating OR DELETE ON public.product_reviews
      FOR EACH ROW EXECUTE FUNCTION public.refresh_store_rating();
  END IF;
END
$$;

DROP TRIGGER IF EXISTS trg_refresh_store_rating ON public.store_reviews;
CREATE TRIGGER trg_refresh_store_rating
  AFTER INSERT OR UPDATE OF rating OR DELETE ON public.store_reviews
  FOR EACH ROW EXECUTE FUNCTION public.refresh_store_rating();

-- ─── 7. Backfill every existing store (picks up store_reviews) ─────
DO $$
DECLARE
  s RECORD;
BEGIN
  FOR s IN SELECT id FROM public.stores LOOP
    PERFORM public.refresh_store_rating_stats(s.id);
  END LOOP;
END
$$;
