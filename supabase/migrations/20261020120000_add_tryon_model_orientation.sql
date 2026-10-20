-- ══════════════════════════════════════════════════════════════════
-- Migration: per-model orientation for the web foot try-on (Phase 2)
-- Date: 2026-10-20
--
-- WHY THIS CHANGE:
--   The workshop authors models inconsistently: most put the toe on +Z,
--   but at least one live model (JBC Crown, byte-identical to
--   qa_partner_shoe_v1.glb) points its toe at −Z with all three audit
--   signals agreeing. The portal viewer normalized every model by size.z
--   with no yaw, so such shoes render heel/toe swapped on the customer's
--   foot. These two columns let each row declare its own authoring; the
--   portal reads them through `fetchProductModel` and normalizes
--   accordingly (`modelNormalization.js`).
--
--   Both columns are nullable-tolerant by design: the portal falls back to
--   `forward_axis = '+z'` / `default_scale = 1.0` (the legacy behavior) when
--   a row predates this migration or holds NULL, so applying late changes
--   nothing until a row is actually annotated. Do NOT backfill blindly —
--   each model needs the inspector's verdict plus a human eyeball
--   (see customer-portal/docs/model-orientation-audit.md).
--
-- ⚠️ DO NOT APPLY without the owner's go-ahead (STOP AND ASK). It is
--   additive and safe (defaults preserve legacy rendering), but it touches
--   the live catalogue table.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.product_models
  ADD COLUMN IF NOT EXISTS forward_axis TEXT NOT NULL DEFAULT '+z'
    CHECK (forward_axis IN ('+z', '-z', '+x', '-x')),
  ADD COLUMN IF NOT EXISTS default_scale NUMERIC NOT NULL DEFAULT 1.0
    CHECK (default_scale BETWEEN 0.5 AND 3);

COMMENT ON COLUMN public.product_models.forward_axis IS
  'Which model-space axis the toe points along (glTF Y-up, before the viewer''s sole-side-up fix). Decided per asset by scripts/inspect-glb.mjs plus a human eyeball — never auto-detected at render time.';
COMMENT ON COLUMN public.product_models.default_scale IS
  'Per-model size baseline multiplying the try-on length on top of the wearer''s live +/- trim (1.0 = no correction). Calibrated per asset with the foot fully visible ~1m away.';
