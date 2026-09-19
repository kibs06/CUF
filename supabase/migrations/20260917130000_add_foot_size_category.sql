-- ══════════════════════════════════════════════════════════════════
-- Foot-profile snapshot: the shopping size scale
-- ══════════════════════════════════════════════════════════════════
-- EU sizes are unisex — EU 42 is EU 42 — so `foot_size_ph` alone cannot say
-- how to LABEL that size in US/UK: on the app's own converter EU 42 is US 9
-- on the men's chart and US 10.5 on the women's (FootMeasurement.euToUs).
--
-- The AR scan already asks the question ("Shopping size": men / women /
-- kids) and keeps the answer in `foot_measurements.shoe_category`. The
-- manual picker had nowhere to put it, which is why a manually-entered size
-- could never produce a correct US/UK equivalent. This is that place.
--
--   foot_size_category: 'men' | 'women' | 'kids'
--     The sizing SCALE the customer shops in — not identity. The account's
--     `gender` column answers a different question, may be unset, and may be
--     self-described, so it is deliberately not reused here.
--     NULL → never answered (rows that predate this column). Callers fall
--     back to the men's chart, which is what the app used before.
--
-- RLS is unaffected: profiles is already covered by the existing
-- "Users can update their own profile" policy.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS foot_size_category TEXT
      CHECK (foot_size_category IN ('men', 'women', 'kids'));

-- Backfill from the newest scan that recorded a scale, so existing scanned
-- customers get correct US/UK labels without re-scanning. Idempotent: it
-- only touches rows that have never held a scale.
UPDATE public.profiles p
   SET foot_size_category = m.shoe_category
  FROM (
        SELECT DISTINCT ON (user_id) user_id, shoe_category
          FROM public.foot_measurements
         WHERE shoe_category IS NOT NULL
         ORDER BY user_id, scan_date DESC
       ) m
 WHERE p.id = m.user_id
   AND p.foot_size_category IS NULL;
