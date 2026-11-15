-- Align `product_color_paint_hex_format` with the documented pattern.
--
-- WHY THIS EXISTS: the table's first draft shipped a narrower CHECK than the
-- file that created it documents (lowercase hex only), and
-- `CREATE TABLE IF NOT EXISTS` never revisits a constraint — so re-running
-- `20261114000100_add_product_color_paint.sql` kept the first draft's check
-- forever, and every Confirm the portal sent (e.g. `#3F4A63`) was refused
-- even though the repo file allows it. This migration drops whatever the
-- live check is and re-adds the documented case-insensitive pattern, so the
-- database and the repo agree again.
--
-- SAFE TO RE-RUN: both statements are conditional on the constraint's
-- presence, and the table holds no rows that the documented pattern would
-- reject (nothing could ever be stored under the narrower check that the
-- wider one refuses).

ALTER TABLE public.product_color_paint
  DROP CONSTRAINT IF EXISTS product_color_paint_hex_format;

ALTER TABLE public.product_color_paint
  ADD CONSTRAINT product_color_paint_hex_format
  CHECK (paint_hex ~ '^#[0-9A-Fa-f]{6}$');
