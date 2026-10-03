-- ══════════════════════════════════════════════════════════════════
-- Migration: Restore the public-read (and admin) policies the hosted
--            project is missing on three catalog tables
-- Date: 2026-10-03
--
-- WHY THIS CHANGE:
--   `product_variants` and `product_customizations` on the hosted
--   project were created by hand from an older revision of the schema
--   and never received the public read policies this repo's lineage
--   defines (`20260601000000_base_schema.sql`; the same drift is already
--   recorded in `PROJECT_HANDOFF.md` — the hosted `product_variants.id`
--   is UUID where the lineage builds BIGINT, which is how we know the
--   table was hand-made). RLS is enabled, so reads are filtered to
--   nothing for every non-owner. The customer app's colour picker
--   embeds `product_variants(*)` and receives `[]`, which is why a
--   product with Black + Brown shows no colour selector at all.
--
--   Measured against the live project on 2026-10-03, same product:
--
--     GET /rest/v1/product_variants?product_id=eq.3e95a923-…    → []
--     sql: select … from product_variants where product_id = …  → 14 rows
--          (7 sizes × 2 colours, so the data is there and unreadable)
--
--   `product_images` is also missing its admin policy, restored here for
--   the same reason (its public SELECT is already present).
--
--   Additive and idempotent: SELECT-only exposure of catalog rows that
--   every other surface already treats as public, plus the admin ALL
--   policies the base schema defines for these tables.
-- ══════════════════════════════════════════════════════════════════

-- ── product_variants ──────────────────────────────────────────────
-- The app reads these for the colour picker, the per-colour stock and
-- the cart's variant resolution; the storefront will need them the
-- moment it grows a colour picker.
DROP POLICY IF EXISTS "Product variants are viewable by everyone"
    ON public.product_variants;
CREATE POLICY "Product variants are viewable by everyone"
    ON public.product_variants FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins can manage all product variants"
    ON public.product_variants;
CREATE POLICY "Admins can manage all product variants"
    ON public.product_variants FOR ALL USING (public.is_admin());

-- ── product_customizations ────────────────────────────────────────
-- The app's product page offers what the seller wrote here (engraving,
-- a different sole); without the public read the options are invisible
-- for the same reason the colours were.
DROP POLICY IF EXISTS "Product customizations are viewable by everyone"
    ON public.product_customizations;
CREATE POLICY "Product customizations are viewable by everyone"
    ON public.product_customizations FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins can manage all product customizations"
    ON public.product_customizations;
CREATE POLICY "Admins can manage all product customizations"
    ON public.product_customizations FOR ALL USING (public.is_admin());

-- ── product_images ────────────────────────────────────────────────
-- Public SELECT and the seller policy already exist; only the admin
-- one is missing.
DROP POLICY IF EXISTS "Admins can manage all product images"
    ON public.product_images;
CREATE POLICY "Admins can manage all product images"
    ON public.product_images FOR ALL USING (public.is_admin());

-- ══════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run after applying)
-- ══════════════════════════════════════════════════════════════════
-- -- Every table should now carry all three policies:
-- SELECT tablename, policyname, cmd
--   FROM pg_policies
--  WHERE schemaname = 'public'
--    AND tablename IN ('product_variants', 'product_customizations', 'product_images')
--  ORDER BY tablename, policyname;
--
-- -- And the app's own embed, as anon, must return the rows:
-- --   GET /rest/v1/products?id=eq.<product-id>&select=product_variants(id,size,color,stock)
-- --   → [{"product_variants":[…14 rows…]}]
