-- ══════════════════════════════════════════════════════════════════
-- Product "On Sale" feature
-- ══════════════════════════════════════════════════════════════════
-- Adds nullable sale fields to public.products. `price` is ALWAYS the
-- original/regular price — it is never overwritten by a sale. A product
-- counts as "on sale" only while sale_price is strictly below price and
-- within the optional start/end window (enforced in the app layer via
-- lib/utils/sale_price.dart — deliberately NO DB CHECK requiring
-- sale_price < price so sellers can freely clear/adjust a sale).

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS sale_price     NUMERIC,          -- NULL = not on sale
  ADD COLUMN IF NOT EXISTS sale_starts_at TIMESTAMPTZ,      -- NULL = active immediately
  ADD COLUMN IF NOT EXISTS sale_ends_at   TIMESTAMPTZ;      -- NULL = never expires

CREATE INDEX IF NOT EXISTS idx_products_active_sale
  ON public.products (sale_price)
  WHERE sale_price IS NOT NULL;
