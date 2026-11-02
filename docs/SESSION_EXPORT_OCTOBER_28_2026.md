# Session export — October 28, 2026 (try-lens QA thread)

## Camera zoom saga (resolved, verified on-phone)
- Symptom: `/try-lens` view looked ~2-3x zoomed vs native 1x; readout `src 1280x960 canvas 1280x960`.
- Cause: 4:3 landscape sensor buffer `cover`-cropped into a portrait screen + Camera Kit
  render-size call silently ignored while the session was live.
- Fix chain (`DirectLensPlayer.jsx` owns its own stream; wrapper dropped deviceId on mobile):
  `b89bce8` runtime rotation → `5527040` build marker → `1f2211a` raw-first 4s
  countdown → `0c78caf` **[rs1] pause-first `setRenderSize` + fullscreen cover** (the fix).
- Phone proof: `[rs1] src 1280x960 rot canvas 960x1280` — sensor landscape, rotation
  fired, canvas portrait. Lens applied cleanly onto the wide feed (foot-hint UI = tracker
  waiting for a shoe, not a broken camera).

## 60fps detour (reverted)
- `bef7648` requested 60fps capture + 720px render cap + fps meter; user asked to revert.
- `72c78b5` reverted it; HEAD verified byte-identical to `0c78caf` for the pages.

## Shipping states
- `d9c2600` clean default (lens immediately, no QA chrome) — deployed, then reverted per
  request in `68696d1`, restoring readout/toggle/pills/slider.
- `c42cc6e` pins first rear camera (**cam1**) as default (safe fallback to browser pick).
- `1b51cb0` instant camera pills: inventory is enumerate-only now. Opening each camera to
  probe resolution stalled for seconds while the session was live (backgrounding the app
  just gave the stuck opens time to finish). Pills show `cam0..camN`, `*` marks cam1.

## Lens gating (the wrong-shoe bug)
- Symptom: non-Luna products showed "Try in Snapchat" and loaded the Luna Loafers lens.
- Cause: button gated on `model && lens configured`; lens is one global
  `VITE_CAMERAKIT_LENS_ID`, `?product=` never selected a lens, no product→lens map existed.
- Fix in `aa10562`: `VITE_CAMERAKIT_LENS_PRODUCT_IDS` (Luna =
  `0aebaa64-4d9e-44f8-8876-6b3ee9855fae`, also set in Vercel production env).
  `lensAvailableForProduct()` gates the button in `ProductDetail.jsx` and guards
  `TryLens.jsx` (direct links to ungated products get a "no lens yet" note).
- Rule for new shoes: publish a per-product lens in Lens Studio, then append its product
  ID to the setting. Until then the product keeps 3D + foot try-on, no Snapchat button.

## Final state
- `main` = `aa10562`, pushed; Vercel production `Ready` (auto-deploys `main`).
- Local tree: only pre-existing `docs/diagrams` modifications, untouched by this thread.
- Open item: 20-second lock-on recording on the phone (shoe in frame) for the defense clip.
