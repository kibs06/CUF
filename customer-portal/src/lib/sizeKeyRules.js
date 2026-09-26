/**
 * The one place that decides what a stored size *means* — a 1:1 port of
 * `lib/utils/size_key.dart`.
 *
 * A size string in the catalog or the profile is either `'{SYSTEM} {VALUE}'`
 * (`'EU 40'`, `'US 8'`, `'UK 3.5'`, `'JP 25'`) or a bare value (`'40'`,
 * `'9.5'`). The database never sees the system: every RPC matches sizes
 * digits-only (`regexp_replace(size, '\D', '', 'g')`), so `'EU 40'` and `'40'`
 * are the same row to Postgres. `sizeKey` mirrors that rule exactly.
 *
 * The portal needed this the moment it wanted to read a size rather than print
 * one. Ported whole rather than cut down, because the parts interlock: the
 * match rule (`sizeMatchRules.js`) reads `sizeSystem` and `sizeNumberInEu`, and
 * the product page's size grid orders with `compareSizes`. See
 * `docs/AI/SIZE_AWARE_SHOPPING_PLAN.md` §4–5 for the defects this closes.
 *
 * Three of them were ported as fixes, not as copies, because the portal had the
 * same bug the app had:
 *
 *  * a bare size means **EU** (decision #1) — the portal's Settings page already
 *    writes `foot_size_ph` with no system, and a US label built from it would be
 *    a different size;
 *  * half sizes sort **numerically** (`compareSizes`) — `Number()` on `'9.5'`
 *    is fine but `parseInt` collapses it, and row order is not order at all;
 *  * an unknown system (`'JP 25'`) is **never** reinterpreted as EU 25.
 */

/** Which system a bare (prefix-less) size belongs to: **EU** (decision #1). */
export const kDefaultSizeSystem = 'EU'

/**
 * Plausible EU band. A size outside it is treated as an unknown system rather
 * than silently reinterpreted.
 */
export const kEuMin = 35
export const kEuMax = 48

/** Half a size — the "closest available" tolerance, never a silent substitution. */
export const kNearSizeToleranceEu = 0.5

/**
 * The shopping size SCALE a US/UK label is drawn on. EU itself is unisex — EU 42
 * is EU 42 whoever wears it — but the US chart is not: EU 42 is **US 9** on the
 * men's chart and **US 10.5** on the women's.
 *
 * Stored per customer in `profiles.foot_size_category` (`'men' | 'women' |
 * 'kids'`). Men's is only the fallback for a customer who never picked a scale.
 */
export const kDefaultSizeCategory = 'men'

/** EU → US chart offsets, by scale. Still an approximation. */
export const kEuToUsChartOffset = Object.freeze({
  men: 33,
  women: 31.5,
  kids: 33,
})

/** EU → UK chart offset. */
export const kEuToUkChartOffset = 33.5

/** Units a size can be shown in — EU first, because EU is what is stored. */
export const kSizeUnits = ['EU', 'US', 'UK']

/**
 * The units that can be honestly labelled on `category`'s chart.
 *
 * Kids' US/UK is a separate, non-linear scale this project owns no chart for:
 * the men's-derived step would label a child's EU 22 as 'US -11'. A kids'
 * shopper is therefore offered EU alone.
 */
export function sizeUnitsForCategory(category) {
  return category === 'kids' ? ['EU'] : [...kSizeUnits]
}

/** EU → US offset for `category`; men's when unset or unrecognised. */
export function euToUsChartOffset(category) {
  return kEuToUsChartOffset[category] ?? kEuToUsChartOffset[kDefaultSizeCategory]
}

/** US label for an EU size on `category`'s chart — halves kept exact. */
export function usSizeFromEu(eu, { category } = {}) {
  return eu - euToUsChartOffset(category)
}

/** The EU size behind a US size on `category`'s chart. */
export function euSizeFromUs(us, { category } = {}) {
  return us + euToUsChartOffset(category)
}

/** UK label for an EU size on the single UK chart (deliberately not scale-aware). */
export function ukSizeFromEu(eu) {
  return eu - kEuToUkChartOffset
}

/** The EU size behind a UK size. */
export function euSizeFromUk(uk) {
  return uk + kEuToUkChartOffset
}

/** A leading system prefix followed by a value: `'EU 40'`, `'EU40'`, `'US 8'`. */
const SYSTEM_PREFIX = /^([A-Za-z]+)\s*([0-9].*)$/

/** Everything that is not a digit — the database's `regexp_replace(size, '\D', '', 'g')`. */
const NON_DIGIT = /[^0-9]/g

/** Everything that is not a digit or a dot, so half sizes survive. */
const NON_NUMERIC = /[^0-9.]/g

/**
 * The system a stored size string is in — `'EU'`, `'US'`, `'UK'`, `'JP'`, …
 *
 * Prefers an explicit prefix; a bare number falls back to
 * `kDefaultSizeSystem`. Strings with no recognizable prefix+number (empty,
 * `'Other'`, garbage) also return the default — pair with `sizeNumber`, which
 * returns null for those.
 */
export function sizeSystem(raw) {
  const match = SYSTEM_PREFIX.exec(String(raw ?? '').trim())
  if (!match) return kDefaultSizeSystem
  return match[1].toUpperCase()
}

/**
 * The numeric value (`'EU 40'` → 40, `'9.5'` → 9.5). null when unparseable.
 *
 * `Number()` rather than `parseFloat`, because `parseFloat('1.2.3')` is 1.2
 * where Dart's `double.tryParse` is null — a size nobody typed must not become
 * a number.
 */
export function sizeNumber(raw) {
  const cleaned = String(raw ?? '').replace(NON_NUMERIC, '')
  if (cleaned.length === 0) return null
  const parsed = Number(cleaned)
  return Number.isFinite(parsed) ? parsed : null
}

/**
 * The digits-only key the DATABASE matches on.
 *
 * The mirror is exact: `'UK 3.5'` and `'9.5'` reduce to `'35'` and `'95'`, the
 * decimal point included, because the database strips non-digits.
 */
export function sizeKey(raw) {
  return String(raw ?? '').replace(NON_DIGIT, '')
}

/** The profile's EU size as a `sizeKey`, for comparing against catalog sizes. */
export function sizeKeyForEu(euSize) {
  return sizeKey(formatSizeNumber(euSize))
}

/**
 * Value of `raw` in EU (identity when already EU, and for bare values that
 * default to EU).
 *
 * Unknown systems keep their raw value — no per-category offsets. The match
 * rule's band check (`[kEuMin, kEuMax]`) is what makes that safe: a `'JP 25'`
 * stays 25 and is never claimed as EU 25.
 */
export function sizeNumberInEu(raw) {
  const number = sizeNumber(raw)
  if (number === null) return null
  const system = sizeSystem(raw)
  if (system === 'EU') return number
  return convertSizeNumber(number, system, 'EU')
}

/**
 * Render a stored size with its system named: `'EU 40'` / `'US 8'`.
 *
 * This is the one label formatter every size surface uses instead of a
 * hardcoded `'EU '` literal. Bare values are named with `kDefaultSizeSystem`;
 * unparseable strings come back verbatim.
 *
 * Pass `unit` to display the value converted into another unit, and `category`
 * to say which shopping scale that unit's chart is drawn on (`'women'` → EU 42
 * reads US 10.5).
 */
export function formatSize(raw, { unit, category } = {}) {
  const number = sizeNumber(raw)
  if (number === null) return raw
  const system = sizeSystem(raw)
  const target = unit ?? system
  const value =
    target === system
      ? number
      : convertSizeNumber(number, system, target, { category })
  return `${target} ${formatSizeNumber(value)}`
}

/**
 * Convert a numeric shoe size between units. EU is the pivot — it is the system
 * the catalog stores and the only one with a chart offset per scale.
 *
 * Identical units are identity, and an unknown system is returned unchanged
 * rather than silently treated as one of the three.
 */
export function convertSizeNumber(value, from, to, { category } = {}) {
  if (from === to) return value

  let eu = null
  if (from === 'EU') eu = value
  else if (from === 'US') eu = euSizeFromUs(value, { category })
  else if (from === 'UK') eu = euSizeFromUk(value)
  if (eu === null) return value

  if (to === 'EU') return eu
  if (to === 'US') return usSizeFromEu(eu, { category })
  if (to === 'UK') return ukSizeFromEu(eu)
  return eu
}

/**
 * Format a numeric size, dropping the decimal for whole numbers:
 * 40 → `'40'`, 6.5 → `'6.5'`.
 *
 * No branch is needed for the whole-number case here the way Dart needs one:
 * `String(40)` is already `'40'` in JavaScript.
 */
export function formatSizeNumber(value) {
  const number = Number(value)
  if (!Number.isFinite(number)) return String(value)
  return String(number)
}

/**
 * Order two stored sizes by numeric value — half sizes included — with
 * unparseable values LAST rather than at the front, and a raw-string tiebreak so
 * the order is deterministic.
 */
export function compareSizes(a, b) {
  const na = sizeNumber(a)
  const nb = sizeNumber(b)
  if (na === null && nb === null) return compareStrings(a, b)
  if (na === null) return 1
  if (nb === null) return -1
  const byNumber = na - nb
  return byNumber !== 0 ? byNumber : compareStrings(a, b)
}

/** Dart's `String.compareTo`, which `Array.prototype.sort` does not provide. */
function compareStrings(a, b) {
  const left = String(a)
  const right = String(b)
  return left < right ? -1 : left > right ? 1 : 0
}
