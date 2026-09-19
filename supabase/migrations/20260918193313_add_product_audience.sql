-- ══════════════════════════════════════════════════════════════════
-- Product audience: who a product is for (Men's / Women's / Kids')
-- ══════════════════════════════════════════════════════════════════
-- The catalog has no way to say which audience a product is sold to.
-- `products.category` is a STYLE (Casual, Formal, Boots, Sneakers — see
-- AppConstants.productCategories) and the tag vocabulary is Product type /
-- Material / Sustainability; neither carries an audience. `profiles.gender`
-- describes a PERSON, not an item, and may be unset or self-described.
--
-- Audience cannot be inferred from the sizes either: EU is unisex, so Men's
-- and Women's share the same 35→48 band — the scale only decides which US/UK
-- chart a size is LABELLED on (EU 42 reads US 9 on the men's chart and
-- US 10.5 on the women's; lib/utils/size_key.dart kEuToUsChartOffset). Kids'
-- (22→35) overlaps the adult band at the top, so a size-derived guess would
-- put an adult shoe in a children's section.
--
-- So it is STATED by the seller, never inferred:
--
--   audience: 'men' | 'women' | 'kids' | 'unisex'
--     NULL      → not set. Every existing row. Readers must treat this as
--                 "no audience", never as a default — an unset product shows
--                 in no audience rail (docs/AI/PRODUCT_AUDIENCE_PLAN.md §3).
--     'unisex'  → genuinely for anyone, and deliberately NOT a rail: a
--                 unisex product listed in Men's, Women's AND Kids' would
--                 appear three times down the feed.
--
-- Nullable on purpose, and NOT backfilled here: guessing an audience from the
-- size band is the one shortcut the plan rejects. Backfill (P4) measures the
-- unset count first and takes the only honest source — the seller.
--
-- No index: nothing queries this column yet (P2 adds the rails' read).
-- No policy change: the existing products policies already cover a new
-- column, and the CHECK below is the only new rule.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS audience TEXT
      CHECK (audience IN ('men', 'women', 'kids', 'unisex'));

-- The CHECK must CONVERGE on a re-apply rather than merely exist beside a
-- fresh column. `ADD COLUMN IF NOT EXISTS` is a no-op once the column is
-- there, so a first partial apply would leave the rule permanently missing
-- while every later run reported success — the failure
-- supabase/MIGRATIONS_LIVE_STATUS.md records twice ("the same is true of the
-- CHECKs that arrive WITH those columns"). Named explicitly so the DROP/ADD
-- pair is stable and re-runnable.
ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_audience_check;

ALTER TABLE public.products
  ADD CONSTRAINT products_audience_check
      CHECK (audience IN ('men', 'women', 'kids', 'unisex'));
