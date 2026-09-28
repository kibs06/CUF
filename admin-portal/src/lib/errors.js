// ─── A refusal told apart from a failure ──────────────────────────
//
// Every page in this portal used to collapse a refused request into one
// sentence: `err.message ?? 'Something went wrong'`. That is the same mistake
// the model-request RPCs were just fixed for on the database side — a
// `RAISE EXCEPTION` with no ERRCODE reports `P0001`, which is
// indistinguishable from a bug inside the function, so a caller could not tell
// "not your job" from "this broke".
//
// A client with no code to read has no move either. It retries what will never
// work, or gives up on what a single reload would fix. So this module is the
// portal's half of that rule: read the code the server sent, decide which of a
// small number of real situations it is, and say what to do about it.
//
// Three properties are deliberate, and each of them is a bug that already
// happened somewhere in this project:
//
//   1. The raw server text is never thrown away. It travels as `detail`, and
//      the page shows it when it differs from the sentence — because a
//      screenshot of the server's own words is often the only route to a fix.
//   2. `42501` means NOT AN ADMIN, and nothing else. It is what the RPCs'
//      `is_admin()` guards now raise on purpose. Reading it as "try again"
//      would loop a person through a door that is locked.
//   3. "The database is behind this build" is its own kind, because it is the
//      one refusal where retrying is pointless and reloading is right. `42804`
//      is in that set because that exact code shipped once already: `v_live`
//      declared `uuid` over a `bigint` column, and CI caught it.
//
// Pure on purpose — no supabase, no React — so the classification is a rule
// with a test beside it (`errors.test.js`, run by `npm test`) rather than a
// guess made at each call site.

/** The situations this portal knows how to answer. */
export const PORTAL_ERROR = {
  NOT_ADMIN: 'not_admin',
  SESSION_EXPIRED: 'session_expired',
  DB_BEHIND_CODE: 'db_behind_code',
  SCHEMA_DRIFT: 'schema_drift',
  OFFLINE: 'offline',
  UNKNOWN: 'unknown',
}

// `42501` insufficient_privilege: what the RPCs' admin guards raise, and what an
// RLS policy reports when it refuses a write. For THIS portal it has one
// meaning — the server does not consider this session an admin, whatever the
// client-side profile said a moment ago.
const NOT_ADMIN_CODES = new Set(['42501'])

// The session is gone, not the permission. PostgREST reports an expired JWT as
// PGRST301/302, and the same condition can arrive as a plain 401.
const SESSION_EXPIRED_CODES = new Set(['PGRST301', 'PGRST302', '401'])

// The database is older than the code. `42883`/`42P01`/`PGRST202`/`PGRST205`
// mean the function or table a page calls is not there yet; `42804` is a type
// mismatch, which is how the uuid-over-bigint bug presented. All of them are
// "apply the migration", and none of them are worth retrying.
const DB_BEHIND_CODES = new Set(['42804', '42883', '42P01', '3F000', 'PGRST202', 'PGRST205'])

// The schema moved under a page. PostgREST's relationship and column errors:
// the model-request queue names its foreign keys in the embed
// (`products!shoe_model_requests_product_id_fkey`), so renaming one shows up
// here rather than as an empty list.
const SCHEMA_DRIFT_CODES = new Set(['PGRST200', 'PGRST204', '42703', '42P10'])

// Some errors carry no code at all, so the text is the only evidence there is.
const SESSION_EXPIRED_TEXT = /jwt expired|invalid claim|token is expired|token has expired|invalid jwt/i
const OFFLINE_TEXT = /failed to fetch|networkerror|load failed|fetch failed|network request failed/i

/** What to do about each situation. `null` means "we have nothing better than
 *  the server's own words" — see `describeError`. */
const SENTENCE = {
  [PORTAL_ERROR.NOT_ADMIN]:
    'The server refused this: the session is not an admin’s. Sign out and back in — if it still says so, the admin role has been removed from the account.',
  [PORTAL_ERROR.SESSION_EXPIRED]:
    'The session has expired, so nothing was sent. Sign out and sign in again, then retry: no change was made.',
  [PORTAL_ERROR.DB_BEHIND_CODE]:
    'The database is behind this build: it does not have what this page calls yet, so the request was refused before it changed anything. Apply the latest migration in supabase/migrations, then reload.',
  [PORTAL_ERROR.SCHEMA_DRIFT]:
    'This page and the database have drifted apart — a column or relationship it asks for is not there under that name. A migration changed the shape, and this page needs the same change.',
  [PORTAL_ERROR.OFFLINE]:
    'Could not reach the server, so nothing was sent. Check the connection and try again.',
  [PORTAL_ERROR.UNKNOWN]: null,
}

/** The text of whatever was thrown, without assuming it is an `Error`. */
function textOf(error) {
  if (typeof error === 'string') return error.trim()
  if (error && typeof error.message === 'string') return error.message.trim()
  return ''
}

/** The code, as a string — `error.status` covers the auth service's numeric
 *  401, which is the same condition as PostgREST's PGRST301. */
function codeOf(error) {
  const code = error?.code ?? error?.status
  return code === undefined || code === null || code === '' ? null : String(code)
}

/**
 * Which of the known situations this is.
 * Exported because some call sites only need the kind — to decide whether to
 * offer a retry button, say — and because the rule is the thing worth testing.
 */
export function classifyError(error) {
  if (!error) return PORTAL_ERROR.UNKNOWN

  const code = codeOf(error)
  const text = textOf(error)

  if (code && NOT_ADMIN_CODES.has(code)) return PORTAL_ERROR.NOT_ADMIN
  if ((code && SESSION_EXPIRED_CODES.has(code)) || SESSION_EXPIRED_TEXT.test(text)) {
    return PORTAL_ERROR.SESSION_EXPIRED
  }
  if (code && DB_BEHIND_CODES.has(code)) return PORTAL_ERROR.DB_BEHIND_CODE
  if (code && SCHEMA_DRIFT_CODES.has(code)) return PORTAL_ERROR.SCHEMA_DRIFT
  if (OFFLINE_TEXT.test(text)) return PORTAL_ERROR.OFFLINE
  return PORTAL_ERROR.UNKNOWN
}

/**
 * An `Error` that carries what the server actually said.
 *
 * It stays an `Error` on purpose: React Query, `try/catch` and the dev overlay
 * all keep working, and `message` is the sentence a toast can show as-is.
 */
export class PortalError extends Error {
  constructor({ kind, message, detail = null, code = null, cause }) {
    super(message)
    this.name = 'PortalError'
    this.kind = kind
    this.detail = detail
    this.code = code
    if (cause !== undefined) this.cause = cause
  }
}

/**
 * The sentence for an error plus, when it is worth showing, the server's own
 * words. Shaped as `{ kind, message, detail, code }` so a page can render
 * `message` prominently and `detail` underneath.
 *
 * `detail !== message` is the test for "the server said something we are not
 * already saying", which is what makes the difference visible without printing
 * the same line twice.
 */
export function describeError(error, fallback = 'Something went wrong.') {
  const kind = error instanceof PortalError ? error.kind : classifyError(error)
  const detail = detailOf(error)
  const message = SENTENCE[kind] ?? (detail || fallback)

  return { kind, message, detail, code: codeOf(error) }
}

/** The server's words, preferring what a `PortalError` already preserved. */
function detailOf(error) {
  if (error instanceof PortalError) return error.detail || textOf(error) || null
  return textOf(error) || null
}

/**
 * Wrap a raw Supabase/PostgREST error so the code survives to the page.
 *
 * ⚠️ Call this with the ORIGINAL error, never with `new Error(error.message)`:
 * the code lives on the object, and a message-only copy loses the one field
 * that decides which sentence the admin reads. Wrapping twice is a no-op, so a
 * hook may wrap at its own boundary without checking what it was handed.
 */
export function toPortalError(error, fallback) {
  if (error instanceof PortalError) return error
  return new PortalError({ ...describeError(error, fallback), cause: error })
}
