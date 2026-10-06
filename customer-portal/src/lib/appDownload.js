/**
 * Where the portals send someone who wants the AR try-on, and what they are told
 * on the way there.
 *
 * ## Why a download and not a try-on
 *
 * The camera fitting is the app's: it needs ARCore and a live camera, which a
 * browser cannot ask a page for. `Product3DViewer` says as much in its own words
 * — it draws the *look* (drag to turn, pinch to zoom) and deliberately offers no
 * AR of its own, because "a second, unmanaged AR door out of a product page is
 * not this component's to open". So the button is honest about being a door to
 * the app rather than a door to AR, and both portals get it for free: the
 * seller's product preview is the customer's own `ProductDetail`, so the shop and
 * the portal's preview cannot disagree about what the pair offers.
 *
 * ## The URL
 *
 * GitHub's `releases/latest` — the same place the app's own updater installs
 * from (`AppConstants.updateManifestUrl` → the `apk_url` in
 * `releases/version.json` → `github.com/kibs06/CUF/releases/download/…`). The
 * `/latest` form is used rather than a versioned APK URL for one reason: a
 * version number here would be a second place to forget. The page resolves to
 * whatever the newest published release is, and the APK is its asset.
 *
 * It is an APK, not a store listing, and the prompt says **Android** rather than
 * implying a store: this app is sideloaded during the testing phase, and a
 * customer sent to a releases page should have been told that before they got
 * there rather than after.
 */
export const APP_DOWNLOAD_URL = 'https://github.com/kibs06/CUF/releases/latest'

/**
 * The prompt, in the dialog's own words.
 *
 * Three things it has to do: name the thing the customer asked for (Try On in
 * AR) so the button and the dialog are obviously about the same wish, say where
 * it actually lives (the app, on a phone) rather than implying the website was
 * broken, and ask for the download as the action. The cancel is "Not now" and
 * not "Cancel" — nobody is losing work here, and "Cancel" on a download prompt
 * reads like something was called off.
 */
export function tryOnAppPrompt() {
  return {
    title: 'Try On in AR is in the CUFMAI app',
    description:
      'The camera fitting runs on your phone, not in the browser. Download the Android app to see how this pair looks on your feet.',
    confirmLabel: 'Download the app',
    cancelLabel: 'Not now',
  }
}

/**
 * The **Request a 3D model** prompt — the seller portal's pointer at the app.
 *
 * ## Why the portal points rather than files the request itself
 *
 * The table exists (`public.shoe_model_requests`) and the app can write to it
 * (`shoe_model_request_upload_sheet.dart`): the seller measures the pair with a
 * tape — the outside length and width, the heel and the upper, and the size it
 * was measured at — the team models it, and the app reports the request's own
 * status while they do ("Waiting for the CUFMAI team", "The CUFMAI team is
 * modelling it"). The portal builds no second copy of that form, and not only
 * because a browser session has no INSERT policy on the table: the numbers are
 * taken with a ruler against the shoe, which is a phone-at-the-bench job rather
 * than a laptop-at-the-desk one, and a request is a conversation with the team —
 * a thread of statuses this portal would only half-rebuild. So a product row
 * offers the wish ("Request a 3D model" in `sellerRowMenus.js`) and this is what
 * the seller is told when they take it.
 *
 * ## The same three jobs as the AR prompt next door
 *
 * Name what was asked for, so the item and the dialog are obviously about the
 * same wish; say where it actually happens, so the pointer does not read as the
 * portal having failed to do it; and make the download the action. It says
 * **Android** for the same reason as well, and it mentions *measurements* on
 * purpose: a seller who asks for a model may expect to hand over a file, and the
 * part they have to do is the part nobody warns them about.
 */
export function modelRequestAppPrompt() {
  return {
    title: '3D model requests are filed in the CUFMAI app',
    description:
      'A model is built from measurements taken against the shoe — how long and wide the pair is, and the heel and upper height — and the app walks you through taking them. Download the Android app to ask the team for one.',
    confirmLabel: 'Download the app',
    cancelLabel: 'Not now',
  }
}
