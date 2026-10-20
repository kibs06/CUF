-- Per-model orientation seed (Phase 2.5) — REVIEW ONLY, do not run blind.
--
-- HOW TO USE: after the Phase 2 migration is applied, run the JBC block
-- ONLY once the owner has confirmed the toe direction visually in
-- "View in 3D" (Phase 2.1 gate). Each block reports what it changed via
-- the trailing SELECT. Re-run safe (idempotent by product name).
--
-- STATUS:
--   JBC Crown Leather Sandals → '-z' PROVISIONAL (audit: all 3 signals
--     agree toe at low end on the byte-identical qa_partner_shoe_v1.glb;
--     awaiting the owner's 3D-view screenshot).
--   HABÍ Woven Slides → not audited (asset not in repo); left at default.
--   placeholder_shoe.glb → audit split 1-vs-2; left at default pending eyeball.

-- ── JBC Crown Leather Sandals: toe on −Z (PROVISIONAL) ──
UPDATE public.product_models pm
SET forward_axis = '-z'
FROM public.products p
WHERE pm.product_id = p.id
  AND p.name = 'JBC Crown Leather Sandals'
  AND pm.status = 'active'
  AND pm.forward_axis IS DISTINCT FROM '-z';

SELECT p.name, pm.version, pm.forward_axis, pm.default_scale
FROM public.product_models pm
JOIN public.products p ON p.id = pm.product_id
WHERE p.name IN ('JBC Crown Leather Sandals', 'HABÍ — Woven Slides')
ORDER BY p.name, pm.version;
