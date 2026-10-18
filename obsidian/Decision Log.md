# 📜 Decision Log

> Why the code is the way it is. Newest first. One entry per decision: the choice, the reason, and where it lives. **#project/solevision**

---

- **Detection dots are Android overlay views, not Filament geometry (V4.13).** A Filament dot needs a material, and a material/mesh mismatch against the ubershader aborts the process (F16) — the wrong price for a debug indicator. Overlays compose for free on the `FrameLayout`.
- **One hold rule for dots and shoe (V4.17).** `DetectionDots.holdState` decides LIVE/COAST/LOST for both, so a hold can never begin for one and end for the other.
- **A hold without a track does not re-read depth (V4.17).** A UV the foot has left measures whatever is behind it — usually the floor — which is how a hold turns into a jump away from the foot.
- **Unknown shoe side is never mirrored (V4.18).** Null side renders as authored; a wrongly-mirrored panel/logo/closure is worse than an unmirrored guess.
- **3D viewer renders in a WebView (`<model-viewer>`), not the app renderer (v1.0.44).** The engine ladder (v1.0.41–45) ended with the phone's own browser engine — the driver, not the picture, was the failure.
- **Lockout write is UPDATE-by-id or INSERT, never upsert (v1.0.54).** `ON CONFLICT (user_id)` cannot match the partial unique index, and PostgREST won't emit the predicate — measured `42P10` on a local stack. Schema end-state (unconditional unique index) still open.
- **Dev builds are told why, not offered the download (unreleased).** `in_app_update_eligibility`: a debug-keystore build can never install a published APK, so both surfaces withhold *all* download routes including the browser fallback.
- **Device step-up is enforced by the DB, not the screen.** RESTRICTIVE `Require a trusted device` policies on the private tables; ships OFF (`set_device_enforcement(true)` flips it) so old clients don't break.
- **Stock decrements exactly once, only after verified payment.** Defer-until-paid killed attempt #2's held-stock pattern; the webhook materializes `order_items`.
- **`inventory` is the stock source of truth, not `product_variants`.** Checkout validates against `inventory`; the dual-sync loop exists so edits never wipe Adjust-Stock adjustments.

Full narrative for the try-on generation: [[docs/3D fitting/AR_TRY_ON_V4_CHANGELOG|AR try-on V4 changelog]].
