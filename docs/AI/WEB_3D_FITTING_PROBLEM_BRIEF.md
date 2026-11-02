# Web 3D Fitting — Problem Brief (for another AI)

> **Scope:** `customer-portal/` (React storefront, live at `cufmai-portal.vercel.app`) — NOT the Flutter app's simulated AR (`docs/AI/AR_TRY_ON_ARCHITECTURE.md`) nor its Filament renderer (`docs/AI/PRODUCT_3D_VIEW_ARCHITECTURE.md`).
> **Date:** 2026-10-20. **Main branch:** `f76d201` (fix `d23cefa` re-applied). **Uncommitted:** axis auto-rotate fix in `FootTryOnViewer.jsx` only.
> **Status:** Prototype A works. Prototype B tracks but renders the shoe small + misplaced (see screenshots below).

## 1. The two prototypes (both exist, both shipped)

**A — "View in your space" (room AR, works fine).**
- `customer-portal/src/components/product/Product3DViewer.jsx` + `customer-portal/src/lib/arSpace.js`
- Same verified `.glb` from public `shoe-models` bucket (`shoeModel.js` → `useProductModel` → `ProductDetail.jsx`), drawn by `<model-viewer>` with `ar`, `ar-modes="webxr scene-viewer"`, `ar-placement="floor"`.
- Button appears only after `ar-status: session-started` / `canActivateAR` probe. No tracking code. Places shoe on floor, not on foot.
- Limitation: `ProductDetail.jsx` never passes `iosSrc`, so iPhones get no Quick Look (Android-only).

**B — "Try on feet (Beta)" (foot fitting, broken).**
- `customer-portal/src/components/product/FootTryOnViewer.jsx` + `customer-portal/src/lib/footTryOn.js` + `footTracker.worker.js` / `footTrackerMain.js` (fallback)
- Rear camera → MediaPipe Pose Landmarker Lite (self-hosted, ~19 MB) → 3 points per foot (ankle 27/28, heel 29/30, foot-index 31/32) → `placementFromFoot()` heel→toe axis → Three.js renders the SAME `.glb`, flat over video via orthographic camera (1 three-unit = 1 video pixel).
- Smoothing: `smoothPoint` (0.45) + `smoothAngle` (0.35) + length lerp 0.4. Coast 1200 ms. Manual place/drag fallback. Live +/− `userScale` trim (now capped 2.0). Zoom + lens switch.
- Footer is honest: "Beta — an approximate look, not a fitted size."

## 2. The problem (with phone evidence)

Screenshots from production (foot fully framed, ankle + toes visible, 1.0x, widest lens):
1. First: tiny sandal bottom-left of frame, trim at 125% still tiny → collapsed axis (shin false positive).
2. After `f76d201`: sandal locks onto foot but sits SMALL + DIAGONAL over ankle/mid-foot at 100% (3 shots). Heel at ankle, toe dies mid-foot, rotated ~45°.

## 3. Root causes (in order)

1. **Pose landmarks under-read the foot.** Foot-index 31/32 lands mid-foot (proximal to toe tip); heel 29/30 lands forward of heel back; top-down phone angle foreshortens. Raw axis ≈ 60–70% of true foot. Fix `f76d201` extends axis (heel −16% `HEEL_BACK`, toe +28% `TOE_EXTENSION`) and gates garbage with `isPlausiblePlacement()` (<12% of short edge = shin, coast/hide). Landed, verified 1002/1002.
2. **Model forward-axis mismatch (current, uncommitted fix).** Viewer normalizes with `s = 1/size.z` assuming toe on +Z. If the workshop authored toe on +X (likely for the brown sandal), it normalizes to WIDTH → small + diagonal regardless of tracking. Uncommitted fix: if `size.x > size.z`, `model.rotation.y += PI/2` then re-measure before normalizing. File: `FootTryOnViewer.jsx` ~line 391.
3. **Per-model scale variance.** Every `.glb` authored at different scale; no per-product default. `userScale` trim compensates manually only.

## 4. Key code (exact)

```js
// footTryOn.js
placementFromFoot(foot, vw, vh) // raw heel/toe → extend → { heel, toe, lengthPx, angleRad }
isPlausiblePlacement(place, vw, vh) // minLen = min(vw,vh)*0.12, maxLen = max(vw,vh)*0.95, bounds ±25%
smoothPoint / smoothAngle / shouldDrawShoe / pickFoot (hysteresis 0.15)
```

```jsx
// FootTryOnViewer.jsx (after GLTFLoader.loadAsync)
model.rotation.z = Math.PI            // sole-side-up fix
// UNCOMMITTED: if (size.x > size.z) { model.rotation.y += Math.PI/2; re-measure }
s = 1 / size.z; inner.scale.set(s,s,s)
inner.position.set(-center.x*s, -box.min.y*s, (-center.z + size.z/2)*s)
yawGroup.scale.set(lengthPx * userScale, ...)  // lengthPx already extended
yawGroup.rotation.z = Math.atan2(-dx, -dy)
```

## 5. What to do next (do NOT just crank extensions)

- Confirm suspect #2: open the brown sandal in `View in 3D`, orbit — if toe points sideways, axis bug confirmed. Or read GLB bounds: longest horizontal axis should be Z.
- If confirmed, keep auto-rotate but scope perverse cases per-model (a `forwardAxis`/`defaultScale` field on `product_models` beats global heuristics).
- Ask user for the `+` % that fits that sandal at 100% → bake in as its default so customers never trim.
- Longer term: foot-detector ONNX (`training/foot-detector/` is scaffold only — no photos, no model, no wiring) or segmentation occluder; Pose 3-point tracking cannot do fitted 6-DoF.

## 6. Verify like this

```
cd customer-portal && npm test   # 1002/1002 (206 suites)
npm run build                    # success ~9s
```
Manual: product with model → `Try on feet (Beta)` → back camera ~1m, ankle + toes visible → shoe should span heel→toes, no shin-jump on close-ups. Vercel `cufmai-portal` auto-deploys `main` (~2–3 min); check `Ready` row per commit.

## 7. Files

- `customer-portal/src/components/product/FootTryOnViewer.jsx` (viewer + Three.js + trim UI)
- `customer-portal/src/lib/footTryOn.js` + `footTryOn.test.js` (pure math + tests)
- `customer-portal/src/lib/footTracker.worker.js`, `footTrackerMain.js` (tracker)
- `customer-portal/src/components/product/Product3DViewer.jsx`, `src/lib/arSpace.js` (Prototype A)
- `customer-portal/src/pages/ProductDetail.jsx`, `src/hooks/useProductModel.js`, `src/lib/shoeModel.js` (wiring)
- History: `d23cefa` (fix) → `886f8f7` (revert) → `f76d201` (re-applied, on `main`)
