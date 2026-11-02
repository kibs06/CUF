# Lens Studio footwear spike — build steps (brown sandal first)

Goal: one Footwear Lens that `/try-lens?product=<id>` loads. Prototype B stays untouched as fallback.

## 0. Downloads + portals

- Lens Studio: https://ar.snap.com/download (free, Snap account; Win 11 64-bit / macOS 12+).
- Camera Kit home: https://ar.snap.com/camera-kit — app/token management: https://kit.snapchat.com (Snap Kit portal → Camera Kit → API token, Lens ID, Lens Group ID).
- Web docs: https://developers.snap.com/camera-kit/integrate-sdk/web/web-configuration ; React wrapper: https://developers.snap.com/camera-kit/integrate-sdk/web/guides/react-camera-kit ; repo: https://github.com/Snapchat/react-camera-kit
- Pins at time of writing: `@snap/camera-kit ^1.13.0` (peer of `@snap/react-camera-kit`), browsers Chrome 95+ / Safari 16+, HTTPS required. Re-check the docs page before `npm i` — Snap revs these monthly.

Desktop GUI + Snap login, so this step runs on your machine, not in CI.

## 1. Brown sandal `.glb`

Open `/try-lens?product=<id>` → copy Model URL (same file `Product3DViewer` draws, public `shoe-models` via `useProductModel`). Import into Lens Studio; if toe points sideways, rotate Y 90° so toe is +Z (same `size.z` assumption as Prototype B).

## 2. Lens Studio → Footwear Try-On template

New project → Footwear Try-On (Foot Tracking + one-shoe carousel + lower-garment occlusion). Swap sample shoe for the brown sandal, delete carousel extras (one shoe = light spike), Preview in Foot mode (webcam + phone remote preview), Publish as Camera Kit target → copy Lens ID + Lens Group ID.

## 3. Wire the stub

`cp .env.example .env.local`, fill the three `VITE_CAMERAKIT_*` values (never commit). Then in `customer-portal/`: `npm i @snap/react-camera-kit` (+ `@snap/camera-kit@^1.13.0` peer), replace the `lens-mount` div in `src/pages/TryLens.jsx` with `CameraKitProvider` + `LensPlayer`, render only when `lensConfigStatus().ready`.

## 4. CSP / Vercel (add only when console demands)

`vercel.json` has no CSP today — keep it that way until the Lens mount throws. Then allow, in `headers` for `/try-lens` (verify exact hosts in devtools — Snap rotates subdomains):
`connect-src https://api.snapchat.com https://*.snapchat.com; img-src https: blob: data:; media-src blob: data:; worker-src blob:; script-src 'self' https://*.snapchat.com; frame-src 'self'`. Keep the existing `/vendor/mediapipe` cache header. Camera needs HTTPS + user gesture (`getUserMedia`).

## 5. Test + decide

Same phones as the Beta bug: iOS Safari 16+ / Android Chrome, rear camera ~1m, ankle + toes framed. Compare lock stability, occlusion, shin-jump on close-ups. `product_models` (`storage_path`, `forward_axis`, `default_scale`) stays source of truth — one Lens per model for the spike.
