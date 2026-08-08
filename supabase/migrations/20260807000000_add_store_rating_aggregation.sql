-- ══════════════════════════════════════════════════════════════════
-- Real Store Rating Aggregation
-- Date: 2026-08-07
--
-- Makes stores.rating a live, trigger-maintained aggregate of customer
-- reviews, mirroring how refresh_product_rating() maintains
-- products.avg_rating / products.review_count.
--
--  - Adds stores.review_count (there was no way to know whether a store
--    had any reviews at all).
--  - Makes stores.rating nullable (NULL = "no reviews yet") and drops
--    the fake DEFAULT 5.0.
--  - refresh_store_rating() aggregates BOTH review sources, weighted by
--    count, exactly like the product trigger:
--       * public.reviews         (primary, per-order-item, has store_id)
--       * public.product_reviews (legacy, per-product, no store_id —
--         resolved via products.store_id)
--  - Attaches AFTER INSERT OR UPDATE OF rating OR DELETE triggers to
--    both tables.
--  - Backfills every existing store so rating/review_count reflect the
--    current reviews immediately, instead of waiting for the next
--    review event.
--
-- ⚠️  Live DB id types: products.id, orders.id, order_items.id are UUID
--     in the live DB (see the header of 20260718_order_item_reviews.sql;
--     schema.sql's TEXT/BIGINT is stale). The joins here are FK-based so
--     they are type-agnostic and work regardless.
-- ══════════════════════════════════════════════════════════════════

-- ─── 1. STORES: nullable rating, no default, + review_count ──────
ALTER TABLE public.stores
  ALTER COLUMN rating DROP NOT NULL,
  ALTER COLUMN rating DROP DEFAULT;

ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS review_count INTEGER NOT NULL DEFAULT 0;

-- ─── 2. Shared aggregation helper (trigger + backfill both call it) ─
CREATE OR REPLACE FUNCTION public.refresh_store_rating_stats(target_store UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_avg    NUMERIC;
  v_count  INTEGER;
  pr_avg   NUMERIC;
  pr_count INTEGER;
BEGIN
  -- Unreachable store (e.g. legacy review whose product was deleted) —
  -- nothing to update, exit without erroring.
  IF target_store IS NULL THEN
    RETURN;
  END IF;

  -- Primary source: per-order-item reviews (has store_id directly)
  SELECT ROUND(AVG(rating)::numeric, 1), COUNT(*)::INTEGER
  INTO v_avg, v_count
  FROM public.reviews
  WHERE store_id = target_store;

  -- Legacy source: product_reviews has no store_id — join through products
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'product_reviews'
  ) THEN
    SELECT ROUND(AVG(pr.rating)::numeric, 1), COUNT(*)::INTEGER
    INTO pr_avg, pr_count
    FROM public.product_reviews pr
    JOIN public.products p ON p.id = pr.product_id
    WHERE p.store_id = target_store;

    -- Merge weighted by count (same math as refresh_product_rating)
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

-- ─── 3. Trigger function: resolve the affected store, then aggregate ─
CREATE OR REPLACE FUNCTION public.refresh_store_rating()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  target_store UUID;
BEGIN
  IF TG_TABLE_NAME = 'reviews' THEN
    -- reviews.store_id is direct
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

-- ─── 4. Attach triggers to BOTH review tables ─────────────────────
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

-- ─── 5. Backfill every existing store from current reviews ────────
DO $$
DECLARE
  s RECORD;
BEGIN
  FOR s IN SELECT id FROM public.stores LOOP
    PERFORM public.refresh_store_rating_stats(s.id);
  END LOOP;
END
$$;
