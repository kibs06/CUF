-- ══════════════════════════════════════════════════════════════════
-- Per-Order-Item Reviews & Ratings (Shopee/Lazada-style)
-- Date: 2026-07-18
--
-- Each purchased line item gets its own review (1-5 stars + comment +
-- optional photos). Sellers can post a public reply.
--
-- ⚠️  products.id is UUID in the live DB (not TEXT).
-- ⚠️  orders.id is UUID in the live DB (not BIGINT).
-- ⚠️  order_items.id is UUID in the live DB (not BIGINT).
-- ══════════════════════════════════════════════════════════════════

-- ─── 1. REVIEWS table ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.reviews (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id         UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  order_item_id    UUID NOT NULL REFERENCES public.order_items(id) ON DELETE CASCADE,
  product_id       UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  customer_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  store_id         UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  rating           SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment          TEXT,
  seller_reply     TEXT,
  seller_reply_at  TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now(),
  UNIQUE (order_item_id)  -- one review per purchased line item
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_reviews_order_id     ON public.reviews(order_id);
CREATE INDEX IF NOT EXISTS idx_reviews_product_id   ON public.reviews(product_id);
CREATE INDEX IF NOT EXISTS idx_reviews_customer_id  ON public.reviews(customer_id);
CREATE INDEX IF NOT EXISTS idx_reviews_store_id     ON public.reviews(store_id);

-- ─── 2. REVIEW IMAGES table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.review_images (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id     UUID NOT NULL REFERENCES public.reviews(id) ON DELETE CASCADE,
  image_url     TEXT NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_review_images_review_id
  ON public.review_images(review_id);

-- ─── 3. TRIGGER: updated_at ────────────────────────────────────
DROP TRIGGER IF EXISTS trg_reviews_updated_at ON public.reviews;
CREATE TRIGGER trg_reviews_updated_at
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── 4. Ensure products has avg_rating / review_count columns ──
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS avg_rating   NUMERIC(2,1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_count INTEGER      NOT NULL DEFAULT 0;

-- ─── 5. TRIGGER: refresh product avg_rating / review_count ─────
-- Counts from the `reviews` table (per-order-item, Shopee-style).
-- If product_reviews exists (legacy), includes it too via dynamic SQL.
CREATE OR REPLACE FUNCTION public.refresh_product_rating()
RETURNS TRIGGER AS $$
DECLARE
  target_product_id UUID;
  v_avg NUMERIC;
  v_count INTEGER;
BEGIN
  target_product_id := COALESCE(NEW.product_id, OLD.product_id);

  -- Count from reviews table (always exists)
  SELECT
    ROUND(AVG(rating)::numeric, 1),
    COUNT(*)::INTEGER
  INTO v_avg, v_count
  FROM public.reviews
  WHERE product_id = target_product_id;

  -- If product_reviews table exists, merge its data too
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'product_reviews'
  ) THEN
    DECLARE
      pr_avg NUMERIC;
      pr_count INTEGER;
    BEGIN
      SELECT
        ROUND(AVG(rating)::numeric, 1),
        COUNT(*)::INTEGER
      INTO pr_avg, pr_count
      FROM public.product_reviews
      WHERE product_id = target_product_id;

      -- Combine averages weighted by count
      IF pr_count > 0 THEN
        IF v_count > 0 THEN
          v_avg := ROUND(((v_avg * v_count) + (pr_avg * pr_count)) / (v_count + pr_count), 1);
        ELSE
          v_avg := pr_avg;
        END IF;
        v_count := v_count + pr_count;
      END IF;
    END;
  END IF;

  UPDATE public.products
  SET
    avg_rating = COALESCE(v_avg, 0),
    review_count = COALESCE(v_count, 0)
  WHERE id = target_product_id;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to the reviews table
DROP TRIGGER IF EXISTS trg_refresh_product_rating ON public.reviews;
CREATE TRIGGER trg_refresh_product_rating
  AFTER INSERT OR UPDATE OF rating OR DELETE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.refresh_product_rating();

-- Also attach to product_reviews if it exists (legacy table)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'product_reviews'
  ) THEN
    DROP TRIGGER IF EXISTS trg_refresh_product_rating ON public.product_reviews;
    CREATE TRIGGER trg_refresh_product_rating
      AFTER INSERT OR UPDATE OF rating OR DELETE ON public.product_reviews
      FOR EACH ROW EXECUTE FUNCTION public.refresh_product_rating();
  END IF;
END
$$;

-- ─── 5. ROW LEVEL SECURITY ────────────────────────────────────
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_images ENABLE ROW LEVEL SECURITY;

-- ── reviews policies ───────────────────────────────────────────

-- Anyone can read reviews (public, Shopee/Lazada style)
DROP POLICY IF EXISTS "Reviews are viewable by everyone" ON public.reviews;
CREATE POLICY "Reviews are viewable by everyone"
  ON public.reviews FOR SELECT USING (true);

-- Customer can insert a review only for their own delivered order item
DROP POLICY IF EXISTS "Customers can insert reviews for delivered orders" ON public.reviews;
CREATE POLICY "Customers can insert reviews for delivered orders"
  ON public.reviews FOR INSERT
  WITH CHECK (
    auth.uid() = customer_id
    AND EXISTS (
      SELECT 1
      FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
      WHERE oi.id = reviews.order_item_id
        AND o.customer_id = auth.uid()
        AND o.status = 'received'
    )
  );

-- Customer can update own reviews (edit window)
DROP POLICY IF EXISTS "Customers can update own reviews" ON public.reviews;
CREATE POLICY "Customers can update own reviews"
  ON public.reviews FOR UPDATE
  USING (auth.uid() = customer_id);

-- Customer can delete own reviews
DROP POLICY IF EXISTS "Customers can delete own reviews" ON public.reviews;
CREATE POLICY "Customers can delete own reviews"
  ON public.reviews FOR DELETE
  USING (auth.uid() = customer_id);

-- Seller can update reviews for their store (seller reply only, enforced by app)
DROP POLICY IF EXISTS "Sellers can reply to store reviews" ON public.reviews;
CREATE POLICY "Sellers can reply to store reviews"
  ON public.reviews FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.stores
      WHERE stores.id = reviews.store_id
        AND stores.owner_id = auth.uid()
    )
  );

-- ── review_images policies ─────────────────────────────────────

-- Anyone can read review images
DROP POLICY IF EXISTS "Review images are viewable by everyone" ON public.review_images;
CREATE POLICY "Review images are viewable by everyone"
  ON public.review_images FOR SELECT USING (true);

-- Owner of the parent review can manage images
DROP POLICY IF EXISTS "Review owners can manage their images" ON public.review_images;
CREATE POLICY "Review owners can manage their images"
  ON public.review_images FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.reviews r
      WHERE r.id = review_images.review_id
        AND r.customer_id = auth.uid()
    )
  );
