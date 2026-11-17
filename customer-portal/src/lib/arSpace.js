/**
 * Web AR ("view in your space") for the portals' 3D viewer.
 *
 * The portals already publish one verified `.glb` per product
 * (`shoeModel.js` → `useProductModel` → `Product3DViewer`). `<model-viewer>`
 * can hand that same URL to the platform AR viewer — Scene Viewer / WebXR on
 * Android, Quick Look on iOS — with no new tracking code and no DeepAR-style
 * commercial SDK. That is the reference demo's ("AR Shoe Try-On System",
 * DeepAR `footInit`) web half, minus the foot lock: this places the shoe on
 * the floor in front of the visitor, it does not stick it to their foot. Foot
 * try-on stays in the app, where ARCore + the foot tracker live.
 *
 * Two rules:
 *
 *  1. **Every platform's mode is offered.** The `.glb` the workshop already
 *     published is all Scene Viewer / WebXR needs. Quick Look is offered too,
 *     even without an `ios-src`: `<model-viewer>` v4 generates the `.usdz`
 *     from the `.glb` on demand when `ios-src` is absent. Suppressing
 *     Quick Look unless a `.usdz` existed hid AR on every iPhone.
 *  2. **Unsupported browsers see nothing new.** Desktops and browsers without
 *     AR must render exactly the viewer they have today: the caller shows the
 *     space button only after `canActivateAR` proves a mode is available (see
 *     `Product3DViewer`).
 */

/** The modes `<model-viewer>` is allowed to use, in preference order. */
export const AR_MODES = 'webxr scene-viewer quick-look'

/**
 * The `ar-modes` attribute value. Kept as a function so call sites do not
 * hand-write the order, and so the list has one tested definition.
 */
export function spaceArModes() {
  return AR_MODES
}

/**
 * Whether an `ar-status` event proves the session actually started. This is
 * **not** the availability probe — `ar-status` stays `not-presenting` until a
 * session begins, even on a phone where AR is ready. `Product3DViewer` uses
 * `canActivateAR` for availability and this only to keep the entry visible
 * once a session has started.
 */
export function shouldOfferSpaceView(status) {
  return status === 'session-started' || status === 'object-placed'
}
