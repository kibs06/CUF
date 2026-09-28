// ─── P2 in the browser: modelling a pair somebody asked for ────────
//
// The Flutter admin queue can *make* the model for a request (`ShoeModelRequestUploadSheet`
// → `ShoeModelUploadService`, roadmap V2.11), and this is the portal's half of
// that phase. It exists because of the sentence in the Flutter screen's own
// header, which reads as if it were written about this app:
//
//   "Without it the picker above could only ever be filled by someone with a
//    terminal, which would leave this screen unable to answer the requests it
//    exists for."
//
// That was true of the portal until now: its only action could point at a model
// that already existed.
//
// **The rules below are ports, and the port is deliberate rather than clever.**
// Every one of them is transcribing a rule that already exists in Dart:
//
//   `lib/utils/shoe_model_upload.dart`   → the declaration, the gate, the row
//                                          payload, the storage path, versions
//   `lib/utils/shoe_model_request.dart`  → the prefill, the ±5 mm agreement,
//                                          and the three endings
//   `lib/services/shoe_model_server_validator.dart` → the verdict shapes
//
// The sentences are copied verbatim, including the ones with an em dash and a
// "guide §5" in them. That is not laziness: an admin who has used both surfaces
// should not be told two different things about the same mistake, and the
// wording is what makes the centimetre trap (*"write 270, not 27"*) land.
//
// **What is deliberately NOT ported: the authoring contract.** The Flutter
// client runs an 11-check GLB reader over the bytes (`lib/utils/glb_validator.dart`,
// 965 lines) so a partner gets a sentence in seconds, and it does so as a
// *courtesy*: the server re-reads the stored bytes and runs the same contract,
// and only the server may write `status = 'active'`
// (`20260928120000_gate_product_model_active.sql`). That contract already has
// two implementations — the Dart reference and its TypeScript mirror in
// `validate-shoe-model`, parity-checked over 22 fixtures. A third in JavaScript
// would be a third place for eleven rules to drift, in the one corner of this
// codebase where drift is measured in millimetres on a customer's foot.
//
// So the portal asks the server, and shows the server's answer. The cost is
// honest and small — one upload before a refusal, and no pre-flight report card
// — and the thing it buys is that there is still exactly one contract.
//
// Everything here is pure (no supabase, no React) except `sha256Hex`, which uses
// Web Crypto and is awaited — Node 20+ has the same API, so `npm test` covers it.

/** The public-read bucket `product_models.storage_path` points into. */
export const MODEL_BUCKET = 'shoe-models'

/** The MIME type the bucket allowlist permits. A `.glb` sent as
 *  `application/octet-stream` is refused by storage with an opaque error, so the
 *  content type is always set explicitly. */
export const MODEL_CONTENT_TYPE = 'model/gltf-binary'

/** The bucket's own `file_size_limit` (`20260927180000_add_try_on_models.sql`).
 *  The upload stops here rather than letting storage refuse 3 MB later. */
export const BUCKET_CAP_BYTES = 8 * 1024 * 1024

/** The contract's scale tolerance, in mm. */
export const LENGTH_TOLERANCE_MM = 5

/** The plausible band for an external length — the database CHECK's figures. */
export const PLAUSIBLE_LENGTH_MIN_MM = 100
export const PLAUSIBLE_LENGTH_MAX_MM = 400

/** The EU band a *reference* size may carry (the CHECK, and `fit_engine.dart`). */
export const AUTHORED_SIZE_MIN_EU = 22
export const AUTHORED_SIZE_MAX_EU = 48

/** The Edge Function that is the only writer of `status = 'active'`. */
export const VALIDATE_MODEL_FUNCTION = 'validate-shoe-model'

/** 272 rather than 272.0 — the same formatting the app uses, so a prefilled
 *  field and a typed one read identically. */
export function formatSizeNumber(value) {
  if (value === null || value === undefined) return ''
  const number = Number(value)
  if (!Number.isFinite(number)) return ''
  return String(number)
}

/** A blank `{ value, error }` field read. */
const blank = { value: null, error: null }

/** One millimetre field: a bare number, and the centimetre message that is the
 *  single most valuable sentence in this file. Mirrors `_parseMm` in
 *  `shoe_model_upload.dart` — note it does **not** accept an `mm`/`cm` suffix,
 *  which is the request form's variant, not the declaration's. */
function parseMm(text, { what, min, max }) {
  if (text === '') return blank

  const value = Number.parseFloat(text)
  if (Number.isNaN(value)) {
    return { value: null, error: `Write ${what} as a number in millimetres (e.g. 275).` }
  }
  if (value <= 0) {
    return { value: null, error: `Write ${what} as a positive number of millimetres.` }
  }
  if (value < min) {
    // A length under 100 that is not absurd as centimetres is the likely typo,
    // and it is worth naming: "100–400 mm is plausible" sends somebody hunting
    // for a different number instead of a different unit.
    if (value * 10 >= min && value * 10 <= max) {
      const asCm = formatSizeNumber(value)
      const asMm = formatSizeNumber(value * 10)
      return {
        value: null,
        error: `Write ${what} in millimetres, not centimetres — ${asCm} looks like ${asMm} mm.`,
      }
    }
    return {
      value: null,
      error: `Write ${what} in millimetres — ${min}–${max} mm is plausible for a shoe.`,
    }
  }
  if (value > max) {
    return {
      value: null,
      error: `Write ${what} in millimetres — ${min}–${max} mm is plausible for a shoe.`,
    }
  }
  return { value, error: null }
}

/** The EU size the mesh was authored at. A US/UK number is the trap the fit form
 *  refuses by name, so this does too. */
function parseEuSize(text) {
  if (text === '') return blank

  const upper = text.toUpperCase()
  if (upper.includes('US') || upper.includes('UK') || upper.includes('CM')) {
    return {
      value: null,
      error:
        'Use the EU size the mesh was authored at (e.g. 42) — US and UK numbers are different sizes.',
    }
  }

  const value = Number.parseFloat(text)
  if (Number.isNaN(value)) {
    return { value: null, error: 'Write the authored EU size as a number (e.g. 42).' }
  }
  if (value < AUTHORED_SIZE_MIN_EU || value > AUTHORED_SIZE_MAX_EU) {
    return {
      value: null,
      error: `Write the authored EU size between ${AUTHORED_SIZE_MIN_EU} and ${AUTHORED_SIZE_MAX_EU}.`,
    }
  }
  return { value, error: null }
}

/** Which field an error belongs to, so the modal can show it inline. */
export const DECLARATION_FIELD = {
  EXTERNAL_LENGTH_MM: 'externalLengthMm',
  AUTHORED_SIZE_EU: 'authoredSizeEu',
}

/**
 * The handover declaration as two text fields — a port of
 * `ShoeModelDeclarationResult.fromFields`.
 *
 * Each field is checked for its own problem first, so a mistyped size is never
 * reported as "add the length". A size **without** a length is the one shape
 * refused outright: the server's scale check cannot run without the length, and
 * an authored size on its own is not a declaration.
 */
export function readDeclaration({ externalLengthMm, authoredSizeEu }) {
  const lengthText = String(externalLengthMm ?? '').trim()
  const sizeText = String(authoredSizeEu ?? '').trim()

  if (lengthText === '' && sizeText === '') {
    return { externalLengthMm: null, authoredSizeEu: null, error: null, errorField: null }
  }

  const size = parseEuSize(sizeText)
  if (size.error) {
    return {
      externalLengthMm: null,
      authoredSizeEu: null,
      error: size.error,
      errorField: DECLARATION_FIELD.AUTHORED_SIZE_EU,
    }
  }

  const length = parseMm(lengthText, {
    what: 'the declared external length',
    min: PLAUSIBLE_LENGTH_MIN_MM,
    max: PLAUSIBLE_LENGTH_MAX_MM,
  })
  if (length.error) {
    return {
      externalLengthMm: null,
      authoredSizeEu: null,
      error: length.error,
      errorField: DECLARATION_FIELD.EXTERNAL_LENGTH_MM,
    }
  }

  if (length.value === null && size.value !== null) {
    return {
      externalLengthMm: null,
      authoredSizeEu: null,
      error:
        'Add the declared external length — it is what the mesh is measured against, and an authored size on its own cannot check scale (guide §5.1).',
      errorField: DECLARATION_FIELD.EXTERNAL_LENGTH_MM,
    }
  }

  return {
    externalLengthMm: length.value,
    authoredSizeEu: size.value,
    error: null,
    errorField: null,
  }
}

/** The sentence for one field, or null when that field is fine. */
export function declarationMessageFor(declaration, field) {
  return declaration.errorField === field ? declaration.error : null
}

/**
 * What the admin's form starts with, taken from the seller's ask — a port of
 * `shoeModelRequestModellingPrefill`.
 *
 * ⚠️ The length IS prefilled here, and that is the opposite of what the
 * *seller's* form does (`shoeModelRequestPrefill`, deliberately blank). The
 * difference is the number on hand: there it was `products.last_length_mm`, the
 * internal last, 8–15 mm shorter than the outside of the same shoe, so offering
 * it would have put a plausible wrong figure in front of somebody who would then
 * confirm it. Here it is the seller's own **external** measurement, taken with a
 * ruler for exactly this purpose and the figure the mesh is scaled to.
 */
export function modellingPrefill({ externalLengthMm, measuredSizeEu }) {
  return {
    externalLengthMm:
      externalLengthMm === null || externalLengthMm === undefined
        ? ''
        : formatSizeNumber(externalLengthMm),
    authoredSizeEu:
      measuredSizeEu === null || measuredSizeEu === undefined
        ? ''
        : formatSizeNumber(measuredSizeEu),
  }
}

/**
 * Whether the declared length agrees with what the seller measured — a note,
 * never a gate (`shoeModelDeclaredLengthAgreement`).
 *
 * The asymmetry is the reason it is a note: the renderer scales every size to
 * the **declared** figure, so a mesh declared 20 mm long draws an oversize shoe
 * on every customer's foot — but the admin may know the seller measured the
 * wrong pair, and refusing to publish would be refusing a correct model.
 */
export function declaredLengthAgreement({ measuredMm, declaredMm }) {
  if (measuredMm === null || measuredMm === undefined) return { disagrees: false, message: null }
  if (declaredMm === null || declaredMm === undefined) return { disagrees: false, message: null }

  const delta = Math.abs(declaredMm - measuredMm)
  if (delta <= LENGTH_TOLERANCE_MM) return { disagrees: false, message: null }

  const direction = declaredMm > measuredMm ? 'longer' : 'shorter'
  return {
    disagrees: true,
    message:
      `The model is declared ${formatSizeNumber(declaredMm)} mm but the seller measured ` +
      `${formatSizeNumber(measuredMm)} mm outside — ${formatSizeNumber(delta)} mm ${direction}. ` +
      'The renderer scales every size to the declared figure, so one of the two is wrong: ' +
      're-measure the pair, or re-export the mesh at its real size (guide §5).',
  }
}

/** How "publish this model, then close the ask" ended. */
export const MODELLING_ENDING = {
  /** Live **and** fulfilled — the only ending where the seller's row turns into
   *  "3D model ready". */
  CLOSED: 'closed',
  /** Nothing went live, so the ask is untouched and still waiting. */
  NOT_LIVE: 'not_live',
  /** ⚠️ The model went live but the ask could not be closed: not a failure
   *  (customers can render the pair) and not a success either, because the
   *  seller's row still says somebody is working on it. */
  LIVE_BUT_OPEN: 'live_but_open',
}

/**
 * Classifies one attempt from the two answers that produced it —
 * `shoeModelRequestModellingResult`, ported.
 *
 * Publish and close are two writes and they can disagree. Collapsing them into
 * "worked" / "failed" would misreport the state to the one person who can fix
 * it, which is why the partial case has its own ending and its own copy.
 */
export function modellingResult({ modelIsLive, fulfilled, modelId = null, refusal = null }) {
  if (!modelIsLive) {
    const detail =
      refusal === null || String(refusal).trim() === ''
        ? 'The server did not accept the file, so it stays hidden.'
        : String(refusal).trim()
    return {
      ending: MODELLING_ENDING.NOT_LIVE,
      modelId,
      message: `The model did not go live, so the request is still waiting. ${detail}`,
    }
  }

  if (!fulfilled) {
    return {
      ending: MODELLING_ENDING.LIVE_BUT_OPEN,
      modelId,
      message:
        'The model is live on the product, but the request could not be closed — it still reads ' +
        'as waiting. Close it as done from the queue; the model is already there to pick.',
    }
  }

  return {
    ending: MODELLING_ENDING.CLOSED,
    modelId,
    message: 'Published and closed — the seller now sees "3D model ready".',
  }
}

/**
 * Whether a link is one this feature will fetch — `isShoeModelSourceUrlAllowed`.
 *
 * **HTTPS only, except loopback.** A 3D asset fetched over cleartext is a
 * supply-chain hole rather than a convenience: the bytes become what customers
 * see on their feet, and an intercepted response would be indistinguishable from
 * a good one.
 */
export function sourceUrlAllowed(url) {
  const trimmed = String(url ?? '').trim()
  if (trimmed === '') return false

  let parsed
  try {
    parsed = new URL(trimmed)
  } catch {
    return false
  }
  if (parsed.protocol === 'https:') return true
  if (parsed.protocol !== 'http:') return false

  const host = parsed.hostname.toLowerCase()
  return host === 'localhost' || host === '127.0.0.1' || host === '[::1]' || host === '::1'
}

/**
 * One sentence per download failure, for the causes an admin can act on.
 *
 * The CORS case is the one this surface adds and the app has never needed: a
 * phone can download any link it can reach, while a browser is refused the
 * bytes by the *page* rules before the request is even answered. It is reported
 * as itself, with the way out (use the file picker, or host the file somewhere
 * a browser may read), because "could not reach that link" would send somebody
 * to check a link that works perfectly.
 */
export function downloadFailureMessage({ status = null, cors = false } = {}) {
  if (cors) {
    return (
      'The browser was not allowed to read that link (the host blocks cross-origin downloads, ' +
      'which is common for Drive/Dropbox share pages). Use "choose a .glb file" instead — that ' +
      'always works — or host it somewhere a browser may read it (this project’s storage, an S3 ' +
      'bucket or a release asset with permissive headers).'
    )
  }
  if (status === 404) {
    return 'That link returned 404 — check it is shared publicly and still exists.'
  }
  if (status === 403) {
    return 'That link is private. Set sharing to "anyone with the link" and check again.'
  }
  if (status !== null) {
    return `The link returned HTTP ${status} instead of a file.`
  }
  return 'Could not reach that link. Check the connection, then the link.'
}

/** Object path inside the bucket: `<store>/<product>/<sha>.glb`. The order is
 *  load-bearing — the seller-write policy keys on the first segment being a
 *  store the caller owns — and the filename is the digest, which is what makes
 *  an upload idempotent. */
export function storagePath({ storeId, productId, sha256 }) {
  return `${String(storeId).trim()}/${productId}/${sha256}.glb`
}

/** The `product_models` insert payload — `shoeModelRow`, ported.
 *
 *  ⚠️ **`status` is always `draft` and there is deliberately no way to ask for
 *  another value.** The portal cannot write `active`: a database trigger refuses
 *  it to every role but the service role, and before that trigger existed asking
 *  for it would have been worse, not better, because it would have *succeeded*
 *  and published a model the server never judged. `rejected` is likewise never
 *  written from here — it records a server-side refusal. */
export function modelRow({
  productId,
  storagePath: path,
  sha256,
  version,
  authoredLengthMm = null,
  authoredSizeEu = null,
  shoeSide = 'right',
  triangleCount = null,
  fileSizeBytes = null,
}) {
  return {
    product_id: productId,
    variant_id: null,
    storage_path: path,
    sha256: String(sha256).trim().toLowerCase(),
    version,
    authored_size_eu: authoredSizeEu,
    authored_length_mm: authoredLengthMm,
    shoe_side: shoeSide,
    material_map: null,
    alignment_json: null,
    triangle_count: triangleCount,
    file_size_bytes: fileSizeBytes,
    // The server validator's call, not this one's — see the doc comment.
    status: 'draft',
  }
}

/** The next `version` for a product's default target: highest + 1. `version` is
 *  an authoring revision, not a retry counter, and `(product_id, version) WHERE
 *  variant_id IS NULL` is unique — so the same target can never be written twice
 *  at one version. */
export function nextVersion(rows) {
  let highest = 0
  for (const row of rows ?? []) {
    if (row?.variant_id !== null && row?.variant_id !== undefined) continue
    const version = Number.isFinite(Number(row?.version)) ? Number(row.version) : 1
    if (version > highest) highest = version
  }
  return highest + 1
}

/** The existing row that already holds these exact bytes, or null.
 *
 *  Publishing the same file twice is a no-op rather than a new version: the
 *  digest is the filename, so the object is already in the bucket and a second
 *  row pointing at it would give the resolver two candidates for one asset. */
export function reuseMatch(rows, sha256) {
  const digest = String(sha256).trim().toLowerCase()
  for (const row of rows ?? []) {
    if (row?.variant_id !== null && row?.variant_id !== undefined) continue
    if (String(row?.sha256 ?? '').trim().toLowerCase() === digest) return row
  }
  return null
}

/** `product_models.id` out of a row, or null. `bigint` arrives as a number from
 *  PostgREST and as a string from some clients, so both are read — and null is
 *  returned rather than a guess, because a publish with no id leaves the model
 *  unjudged. */
export function rowId(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value)
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number.parseInt(value.trim(), 10)
    return Number.isNaN(parsed) ? null : parsed
  }
  return null
}

/** Lowercase SHA-256 hex — `product_models.sha256`'s CHECK demands
 *  `^[0-9a-f]{64}$`. Web Crypto, so this is the same number the app computes
 *  over the same bytes: the storage filename and the integrity check, one value. */
export async function sha256Hex(bytes) {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  const digest = await globalThis.crypto.subtle.digest('SHA-256', view)
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

/** A cheap "is this even a GLB" read: the 12-byte header's magic and version, so
 *  a wrong file is named in a second instead of after a 3 MB upload.
 *
 *  Deliberately NOT a check of anything the contract covers — eleven rules with
 *  two implementations already; a fast failure for the wrong file is the whole
 *  job. */
export function looksLikeGlb(bytes) {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  if (view.length < 12) return false
  return (
    view[0] === 0x67 && // g
    view[1] === 0x6c && // l
    view[2] === 0x54 && // T
    view[3] === 0x46 && // F
    view[4] === 0x02 && // version 2, little-endian uint32
    view[5] === 0x00 &&
    view[6] === 0x00 &&
    view[7] === 0x00
  )
}

/** What one `validate-shoe-model` call produced. */
export const SERVER_OUTCOME = {
  VALIDATED: 'validated',
  REJECTED: 'rejected',
  /** No verdict: the call did not complete, or was refused before the checks
   *  ran. The row keeps the status it had. */
  UNDETERMINED: 'undetermined',
}

/** The failing check names out of a report, whatever wrapper they arrive in. */
export function failedChecks(report) {
  const source = report && typeof report === 'object' && 'checks' in report ? report.checks : report
  if (!Array.isArray(source)) return []
  const names = []
  for (const check of source) {
    if (!check || typeof check !== 'object') continue
    if (String(check.status) !== 'fail') continue
    const name = check.name === undefined || check.name === null ? '' : String(check.name)
    if (name !== '') names.push(name)
  }
  return names
}

function asJsonMap(body) {
  if (body && typeof body === 'object' && !(body instanceof ArrayBuffer)) return body
  if (typeof body === 'string') {
    const text = body.trimStart()
    if (!text.startsWith('{')) return null
    try {
      const decoded = JSON.parse(text)
      return decoded && typeof decoded === 'object' ? decoded : null
    } catch {
      // Not JSON after all; the status code is the honest answer.
      return null
    }
  }
  return null
}

/**
 * One HTTP response as a verdict — `shoeModelServerVerdictFrom`, ported.
 *
 * **422 means refused whether or not the body parses.** It is the function's own
 * refusal signal (the gateway returns 401/403/404/502), so a response whose body
 * is lost in transit must still count as a judgement rather than degrade into
 * "no verdict" — otherwise a refused model would sit in drafts with nobody told
 * why.
 */
export function serverVerdict({ statusCode, body }) {
  const map = asJsonMap(body)

  if (statusCode === 422) {
    const names = [...failedChecks(map?.report)]
    // The server-only check no client can perform: the bytes in the bucket must
    // hash to the digest the row records. Named here because a modeller
    // debugging "it passed my validator" needs to see this one.
    const sha = map?.integrity?.sha256
    if (sha && sha.matches === false) {
      names.unshift('sha256 (the stored bytes do not match the row)')
    }
    return {
      outcome: SERVER_OUTCOME.REJECTED,
      status: map?.status ? String(map.status) : 'rejected',
      failedChecks: names,
      notChecked: Array.isArray(map?.notChecked) ? map.notChecked.map(String) : [],
      detail: map?.error ? String(map.error) : null,
    }
  }

  if (statusCode === 200 && map && map.ok === true) {
    return {
      outcome: SERVER_OUTCOME.VALIDATED,
      status: map.status ? String(map.status) : 'active',
      failedChecks: [],
      notChecked: Array.isArray(map.notChecked) ? map.notChecked.map(String) : [],
      detail: null,
    }
  }

  const message = map?.error ?? map?.message
  const detail =
    message === undefined || message === null || String(message) === ''
      ? `HTTP ${statusCode}`
      : String(message)
  return {
    outcome: SERVER_OUTCOME.UNDETERMINED,
    status: 'draft',
    failedChecks: [],
    notChecked: [],
    detail,
  }
}

/** The sentence the admin reads when the model did not go live, or null when it
 *  did — `ShoeModelServerVerdict.sellerMessage`. */
export function verdictMessage(verdict) {
  switch (verdict?.outcome) {
    case SERVER_OUTCOME.VALIDATED:
      return null
    case SERVER_OUTCOME.REJECTED:
      if (!verdict.failedChecks || verdict.failedChecks.length === 0) {
        return (
          'The server refused the model without naming a failing row, which it should not do — ' +
          'upload it again, and report it if that happens twice. It stays hidden until it passes.'
        )
      }
      return (
        `The server checked the model and refused it (${verdict.failedChecks.join(', ')}), so it ` +
        'is saved as a draft and is not shown to customers. Fix those and upload again.'
      )
    case SERVER_OUTCOME.UNDETERMINED:
      return (
        `The model is saved as a draft: the server could not check it (${verdict.detail ?? 'no response'}), ` +
        'so it is not shown to customers yet. Publish the product again to retry.'
      )
    default:
      return null
  }
}

/** The status a row carries after a verdict. Only the server may write `active`;
 *  this reads its answer rather than deciding. */
export function statusAfterVerdict(verdict) {
  if (verdict?.outcome === SERVER_OUTCOME.VALIDATED) return verdict.status ?? 'active'
  if (verdict?.outcome === SERVER_OUTCOME.REJECTED) return 'rejected'
  return 'draft'
}
