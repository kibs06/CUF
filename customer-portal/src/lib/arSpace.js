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
 *  1. **Android first.** The `.glb` the workshop already published is all
 *     Scene Viewer / WebXR needs, so `webxr scene-viewer` is always offered.
 *     `quick-look` is appended only when an `ios-src` (`.usdz`) URL exists —
 *     Quick Look cannot read `.glb`, and advertising it without a `.usdz`
 *     shows a button that opens nothing on iPhones.
 *  2. **Unsupported browsers see nothing new.** Desktops and browsers without
 *     WebXR / Scene Viewer must render exactly the viewer they have today:
 *     the caller hides the space button unless `<model-viewer>` fires
 *     `ar-status: session-started` support (see `Product3DViewer`).
 */

/** The modes `<model-viewer>` is allowed to use, in preference order. */
export const AR_MODES_ANDROID = 'webxr scene-viewer'
export const AR_MODES_ALL = 'webxr scene-viewer quick-look'

/**
 * The `ar-modes` attribute value for a model with (or without) an iOS source.
 * Pure so it can be tested without a browser.
 */
export function spaceArModes(hasIosSrc) {
  return hasIosSrc ? AR_MODES_ALL : AR_MODES_ANDROID
}

/**
 * Whether the "View in your space" button should be shown, from the latest
 * `ar-status` event detail (`session-started` support) or a `canActivateAR`
 * probe. Unknown / failed states hide the button rather than showing one
 * that opens nothing.
 */
export function shouldOfferSpaceView(status) {
  return status === 'session-started' || status === 'object-placed'
}
