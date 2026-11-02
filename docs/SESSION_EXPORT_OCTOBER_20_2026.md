# Session export — October 20, 2026

## Release
- Tag `v1.0.56` cut on `126fe15`, pushed to origin; `pubspec.yaml` `1.0.56+64`.
- Follow-up release commit `4881647` updated `releases/version.json` + changelog (GitHub workflow).
- APK build/sign/publish runs on GitHub runners (~10 min); failures there are signing-secrets issues, not code.

## Vercel portal (`cufmai-portal`)
- Production auto-deploys `main`. Old `Error` on `f41efa6` (vercel.json with comments) was fixed by `5dda977`.
- `126fe15` and `4881647` both showed `Ready / Production`.
- Tracker is MediaPipe Pose Landmarker Lite, self-hosted via `customer-portal/scripts/vendor-trackers.mjs` (`5777746` bytes), **not** a dataset model.

## Datasets
- `training/foot-detector/` is a scaffold only: `README.md`, `data.yaml` (1 class `foot`, kpts `heel/toe`), empty `datasets/raw/` + `datasets/public/`.
- No photos, no trained ONNX, no `onnxruntime-web` wiring in the portal.

## Web try-on bug (shin placement + wrong size)
- Symptom: tiny shoe rendered on the shin; size did not match the foot.
- Cause: pose heel+toe collapse on foot close-ups + foot-index sitting proximal to the true toe tip.
- Fix written in `d23cefa` (3 files): extended axis in `placementFromFoot()` (heel −16%, toe +28%), new `isPlausiblePlacement()` gate in `footTryOn.js`, live +/− size trim via `track.userScale` in `FootTryOnViewer.jsx`, tests updated. `npm test` 1002/1002, `npm run build` OK.
- Pushed to `main`, then **reverted** per request in `886f8f7` (pushed). `npm test` after revert: 1001/1001.

## Final state
- `main` = `886f8f7` (revert), tree clean, on top of `4881647`.
- Portal live code = pre-fix beta; Vercel redeploys each push (confirm `Ready` row per commit).
