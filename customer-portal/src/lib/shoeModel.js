/**
 * The 3D model a product can be shown in — the portal's half of the app's box.
 *
 * A visitor can now turn the shoe, not only look at it: the same verified `.glb`
 * from the same public `shoe-models` bucket, drawn with the same library the
 * app's box falls back to (`<model-viewer>`, which the app runs inside a WebView
 * — `ShoePreviewWebView`). What the web does **not** do is try-on: the app's AR
 * screen needs a camera and ARCore and there is no such path here, so the portal
 * offers the look, never the fitting (`Product3DViewer` says the same thing to
 * the customer in one line).
 *
 * Two rules, both ports of rules the app already enforces, and both of them pure
 * so they can be tested without a browser:
 *
 *  1. **Only an `active` row is ever drawn.** A draft or a rejected asset is a
 *     work item — the table's own RLS gives customers active rows only — and this
 *     module repeats the filter rather than trusting it alone: the query is
 *     written by hand, and the day someone edits it back to a bare `*` this is
 *     the line that keeps a draft off a shop window.
 *  2. **A model with no path renders nothing at all.** "3D ready" is a claim
 *     about a row; a row is not a file. The app draws no entry for a product
 *     whose bytes are not usable, and neither does this page — the difference
 *     between a hidden entry and a broken canvas is one truthy check.
 */

/** The bucket the app's Dart side names in `ShoeModelService.bucket`. */
export const MODEL_BUCKET = 'shoe-models'

/** The object path on a row, trimmed — `''` when there is nothing to fetch. */
function modelPath(row) {
  return typeof row?.storage_path === 'string' ? row.storage_path.trim() : ''
}

/** Republished models carry the higher `version`; anything else is 0. */
function versionOf(row) {
  const version = Number(row?.version)
  return Number.isFinite(version) ? version : 0
}

/** Later `updated_at` (or `created_at`) wins a version tie. `NaN` sorts last. */
function stampOf(row) {
  const stamp = Date.parse(row?.updated_at ?? row?.created_at ?? '')
  return Number.isNaN(stamp) ? 0 : stamp
}

/**
 * **The row a customer may be shown**, or null.
 *
 * The newest `active` model of the product wins, and by `version` first because
 * that is what the app republishes against: a version bump is a new asset for
 * the same shoe, and the higher number is the one the renderer should draw
 * (`product_models.version`, `>= 1`). A tie falls back to the newer timestamp,
 * so the answer never depends on the order Postgres happened to return rows in.
 *
 * Rows with no usable path are skipped rather than returned: a product with one
 * unreadable row and one good one shows the good one.
 */
export function activeProductModel(rows) {
  const usable = (Array.isArray(rows) ? rows : []).filter(
    (row) => row?.status === 'active' && modelPath(row) !== '',
  )
  if (usable.length === 0) return null

  return usable.reduce((best, row) => {
    if (versionOf(row) !== versionOf(best)) {
      return versionOf(row) > versionOf(best) ? row : best
    }
    return stampOf(row) > stampOf(best) ? row : best
  })
}

/**
 * **The URL the browser fetches the `.glb` from**, or null when there is nothing
 * to fetch.
 *
 * `shoe-models` is public-read on purpose — a model is catalog content, like a
 * product photograph (`20260927180000_add_try_on_models.sql`) — so this is a
 * plain public object URL and not a signed one. Nothing here holds a token, and
 * a URL copied out of the page cannot reach anything the catalogue does not
 * already show.
 *
 * Null for a blank path **or** a missing project URL: both mean "there is
 * nothing to draw", which is the same state a product with no model is in, and
 * the caller renders none of it.
 */
export function modelFileUrl(storagePath, supabaseUrl) {
  const path = modelPath({ storage_path: storagePath })
  const base =
    typeof supabaseUrl === 'string' ? supabaseUrl.replace(/\/+$/, '') : ''
  if (path === '' || base === '') return null

  return `${base}/storage/v1/object/public/${MODEL_BUCKET}/${path}`
}
