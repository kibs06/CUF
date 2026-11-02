-- ══════════════════════════════════════════════════════════════════
-- Migration: Luna Loafers → segmented-lite visual-fitting model
-- Date: 2026-10-27 (manual, operator-run)
--
-- WHY THIS EXISTS:
--   The Luna Loafers product gets its own try-on mesh
--   (black-shoe-segmented-lite.glb, 6.8 MB, fits the 8 MB
--   `shoe-models` cap) while every other product is untouched.
--   The portal (`fetchProductModel`) and the app
--   (`ShoeModelService`) both resolve per product_id, newest
--   active version — so scoping is the row, not code.
--
-- MEASURED ASSET FACTS (2026-10-27, parsed from the lite bytes —
-- not asserted): bbox X 0.270 × Y 0.159 × Z 0.102 m, so the
-- heel→toe length is on X; low-X end meanY 0.029 (toe) vs high-X
-- end meanY 0.077 (heel collar), so the toe points at -X.
-- Hence forward_axis '-x', authored_length_mm 270 (269.9 mm
-- measured), 116693 tris, 7058904 bytes.
--
-- HOW TO RUN (manual, you do this):
--   1. Find Luna: SELECT id, store_id FROM public.products
--      WHERE name ILIKE '%luna%loaf%'; then upload
--      assets/models/black-shoe-segmented-lite.glb to the
--      `shoe-models` bucket as <store_id>/<product_id>/<sha>.glb
--      (first segment MUST be the store UUID — seller upload RLS).
--   2. Run this file in the Supabase SQL Editor.
--   3. Open /product/<luna-id>: View in 3D + Try on feet show the
--      platform shoe; other products are unchanged.
--
-- SAFETY:
--   - Resolves Luna strictly: raises on zero matches AND on
--     multiple matches (no silent LIMIT 1 pick). Touches ONLY the
--     resolved product_id.
--   - Storage path is built as <store>/<product>/<sha>.glb from
--     the resolved row, satisfying the bucket contract and the
--     seller-upload RLS (foldername(name)[1] = store id).
--   - Old Luna actives are set to 'draft' (history preserved,
--     hidden from customers); the new row is the single 'active'.
--   - Idempotent: re-running skips the insert when the same sha256
--     is already the active Luna row.
--   - Operator path (SQL Editor / migration = no JWT) is allowed
--     through trg_product_models_server_validation by design.
-- ══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_matches   UUID[];
  v_product_id UUID;
  v_store_id   UUID;
  v_next_version INT;
  v_storage_path TEXT;
  -- Pinned asset facts (measured from the lite bytes, do not hand-edit):
  c_sha256       CONSTANT TEXT := '0ce44e5b27790c06ff11032396f8da16705f3930b6203282aff9e725ec892db4';
  c_length_mm    CONSTANT NUMERIC := 270;      -- measured 269.9 mm on X
  c_forward      CONSTANT TEXT := '-x';        -- toe at -X (low end)
  c_scale        CONSTANT NUMERIC := 1.0;
  c_bytes        CONSTANT INT := 7058904;
  c_tris         CONSTANT INT := 116693;
BEGIN
  -- 1. Strict Luna resolution. No seed UUID exists in-repo (live
  --    catalogue data), so name is the handle — but ambiguity is a
  --    hard error, never a silent pick.
  SELECT ARRAY_AGG(p.id ORDER BY p.created_at DESC NULLS LAST) INTO v_matches
    FROM public.products p
   WHERE p.name ILIKE '%luna%loaf%';

  IF v_matches IS NULL OR array_length(v_matches, 1) IS NULL THEN
    RAISE EXCEPTION 'Luna Loafers product not found (name ILIKE ''%%luna%%loaf%%''). Create/rename the product first; nothing was changed.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF array_length(v_matches, 1) > 1 THEN
    RAISE EXCEPTION 'Multiple products match ''%%luna%%loaf%%'' (%). Rename to a single Luna Loafers or scope by id; nothing was changed.', array_to_string(v_matches, ', ')
      USING ERRCODE = 'cardinality_violation';
  END IF;

  v_product_id := v_matches[1];

  SELECT p.store_id INTO v_store_id
    FROM public.products p
   WHERE p.id = v_product_id;

  IF v_store_id IS NULL THEN
    RAISE EXCEPTION 'Luna (%) has no store_id; bucket path <store>/<product>/<sha>.glb cannot be built. Set the product store first; nothing was changed.', v_product_id
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- Bucket-contract path: <store_id>/<product_id>/<sha256>.glb.
  v_storage_path := v_store_id::text || '/' || v_product_id::text || '/' || c_sha256 || '.glb';

  -- 2. Idempotence: same bytes already live for Luna → nothing to do.
  IF EXISTS (
    SELECT 1 FROM public.product_models m
     WHERE m.product_id = v_product_id
       AND m.status = 'active'
       AND m.sha256 = c_sha256
  ) THEN
    RAISE NOTICE 'Luna (%) already serves sha % — skipping insert.', v_product_id, substr(c_sha256, 1, 12);
    RETURN;
  END IF;

  -- 3. Retire older Luna actives (draft = hidden, history kept).
  UPDATE public.product_models m
     SET status = 'draft'
   WHERE m.product_id = v_product_id
     AND m.status = 'active';

  -- 4. Next version for this product (1 when first model).
  SELECT COALESCE(MAX(m.version), 0) + 1 INTO v_next_version
    FROM public.product_models m
   WHERE m.product_id = v_product_id
     AND m.variant_id IS NULL;

  -- 5. Insert the new product-level default (variant_id NULL).
  INSERT INTO public.product_models
    (product_id, variant_id, storage_path, sha256, version,
     authored_length_mm, shoe_side, triangle_count, file_size_bytes,
     forward_axis, default_scale, status)
  VALUES
    (v_product_id, NULL, v_storage_path, c_sha256, v_next_version,
     c_length_mm, 'right', c_tris, c_bytes,
     c_forward, c_scale, 'active');

  RAISE NOTICE 'Luna (%) now serves % (v%, axis %, % mm).', v_product_id, v_storage_path, v_next_version, c_forward, c_length_mm;
END;
$$;

-- Verify after applying (SQL Editor):
--   SELECT id, version, status, storage_path, forward_axis, default_scale,
--          authored_length_mm, triangle_count, substr(sha256, 1, 12) AS sha12
--     FROM public.product_models
--    WHERE product_id = (SELECT id FROM public.products
--                         WHERE name ILIKE '%luna%loaf%' LIMIT 1)
--    ORDER BY version DESC;
--   -- Exactly ONE row with status='active'. Other products: zero rows changed.
--   -- Storage object must exist at the row's storage_path in `shoe-models`.
