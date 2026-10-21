-- P1 cold-open paging: SupabaseService.fetchProductPage() reads the
-- all-stores catalog newest-first via .order('created_at').order('id') with
-- .range() slices. The existing idx_products_store_created covers only
-- store-scoped reads; this covers the unfiltered home-feed page query.
CREATE INDEX IF NOT EXISTS idx_products_created_desc
  ON public.products (created_at DESC);
