/**
 * Sale pricing — a 1:1 port of `lib/utils/sale_price.dart`, which the Flutter
 * side documents as the SINGLE source of truth for "is this product on sale
 * right now".
 *
 * The rule, unchanged:
 *   A product is on sale ONLY when
 *     1. `sale_price` is set and strictly less than `price`, AND
 *     2. `sale_starts_at` (if set) is in the past, AND
 *     3. `sale_ends_at` (if set) is in the future.
 *
 * Why port rather than re-implement: money. A storefront that shows a discount
 * the app does not — or misses one the app shows — is a customer-visible
 * discrepancy about price, and the two clients read the SAME rows. Keeping the
 * functions identical means the only way they can disagree is if one of these
 * files is edited alone. `pricing.test.js` pins the behaviour.
 *
 * `now` is injectable for testing, exactly as it is in Dart.
 */

/** Numeric coercion that tolerates what Supabase actually returns. */
function asNumber(value) {
  if (value === null || value === undefined) return null
  if (typeof value === 'number') return Number.isFinite(value) ? value : null
  const parsed = Number.parseFloat(value)
  return Number.isFinite(parsed) ? parsed : null
}

/** Date coercion from a Date, an ISO string or a Postgres timestamp string. */
function asDate(value) {
  if (value === null || value === undefined) return null
  const date = value instanceof Date ? value : new Date(value)
  return Number.isNaN(date.getTime()) ? null : date
}

/** True only while the sale is active (see the module docs for the rule). */
export function isOnSale(product, now = new Date()) {
  const price = asNumber(product?.price) ?? 0
  const salePrice = asNumber(product?.sale_price)

  if (salePrice === null || salePrice <= 0) return false
  // Strictly below, so an equal or higher value means "not on sale" — this is
  // what covers a cleared or corrected sale without a DB CHECK constraint.
  if (salePrice >= price) return false

  const start = asDate(product?.sale_starts_at)
  if (start && now.getTime() < start.getTime()) return false

  const end = asDate(product?.sale_ends_at)
  if (end && now.getTime() > end.getTime()) return false

  return true
}

/** The price the customer actually pays. */
export function effectivePrice(product, now = new Date()) {
  if (isOnSale(product, now)) {
    return asNumber(product?.sale_price) ?? asNumber(product?.price) ?? 0
  }
  return asNumber(product?.price) ?? 0
}

/** Whole-number discount for a badge (e.g. 20), or null when not on sale. */
export function salePercent(product, now = new Date()) {
  if (!isOnSale(product, now)) return null
  const price = asNumber(product?.price) ?? 0
  const salePrice = asNumber(product?.sale_price) ?? 0
  if (price <= 0) return null
  return Math.round(((price - salePrice) / price) * 100)
}

/**
 * The BEST discount among [products] on sale right now, as a whole percent —
 * the "ON SALE · UP TO n%" figure — or null when nothing valid is on sale.
 *
 * Rounded DOWN, unlike [salePercent]'s badge. A badge names one product's own
 * discount; this one is a claim about the whole shelf ("up to"), so 33.3% has
 * to read 33 — rounding up would advertise a deal no product actually offers.
 */
export function maxDiscountPercent(products, now = new Date()) {
  let best = 0
  for (const product of products) {
    if (!isOnSale(product, now)) continue
    const price = asNumber(product?.price) ?? 0
    const salePrice = asNumber(product?.sale_price) ?? 0
    if (price <= 0) continue
    const percent = Math.floor(((price - salePrice) / price) * 100)
    if (percent > best) best = percent
  }
  return best > 0 ? best : null
}

/**
 * The soonest `sale_ends_at` among products on sale right now — the expiry a
 * *set* shares. Products with no end date are skipped rather than treated as
 * "never", which would otherwise hide a shorter sale behind them.
 */
export function earliestSaleEnd(products, now = new Date()) {
  let earliest = null
  for (const product of products) {
    if (!isOnSale(product, now)) continue
    const end = asDate(product?.sale_ends_at)
    if (!end) continue
    if (earliest === null || end.getTime() < earliest.getTime()) earliest = end
  }
  return earliest
}

/*
───────────────────────────────────────────────────────────────────────────────
  The WRITING side of the same rules, for the seller's form.

  It belongs in this file for one reason: money. Everything above reads a sale
  and decides what a customer pays; a form that decided differently would be the
  one divergence a customer certainly notices. So the validation below is written
  against the same rule the readers implement — `sale_price` strictly below
  `price`, and a window that may be open at one end, both, or neither.
───────────────────────────────────────────────────────────────────────────────
*/

/**
 * A date input's value (`'2026-09-26'`) → the string written to the column.
 *
 * `T00:00:00` and no timezone, which is character-for-character what the app
 * writes: Flutter's `showDatePicker` hands back a date-only `DateTime`, and its
 * `toIso8601String()` is exactly this shape. PostgREST then reads it in the
 * column's own timezone, so a date picked on the phone and the same date picked
 * in the browser land on the same instant — rather than one of them being a day
 * out because a `Z` was added on one side only.
 */
export function saleDateValue(dateOnly) {
  const text = String(dateOnly ?? '').trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null
  return `${text}T00:00:00`
}

/** The inverse: a stored timestamp → the `YYYY-MM-DD` a date input needs. */
export function saleDateInput(value) {
  if (value === null || value === undefined || value === '') return ''
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? '' : value.toISOString().slice(0, 10)
  }
  const text = String(value).trim()
  const match = text.match(/^(\d{4}-\d{2}-\d{2})/)
  return match ? match[1] : ''
}

/**
 * The one thing about a sale that **blocks** a save, or null.
 *
 * 'Sale price must be lower than the base price.' is the app's own sentence for
 * the app's own rule, and it is the only money rule either form enforces — a
 * sale at or above the regular price is not a smaller discount, it is a number
 * that means "not on sale" while looking like a price. The app refuses that save
 * and so does this.
 *
 * Blank, unparseable or zero means *no sale* rather than a fault: the app's
 * `double.tryParse` yields null for text it cannot read and its guard skips, and
 * a `0` sale price is inert in every reader. `null` is written for it, which is
 * the same "not on sale" the app stores as `0` — a difference in the row, never
 * in the price a customer sees.
 */
export function salePriceProblem({ price, salePrice }) {
  // A blank price is `0` to `Number()` and to nothing else, so it is excluded
  // by hand: an empty price field is the "name the product" problem, and
  // reporting it as a bad sale price would send the seller to the wrong field.
  const blankBase = price === null || price === undefined || price === ''
  const base = blankBase ? Number.NaN : Number(price)
  if (!Number.isFinite(base)) return null

  if (salePrice === null || salePrice === undefined || salePrice === '') return null
  const value = Number(salePrice)
  if (!Number.isFinite(value) || value === 0) return null

  if (value < 0) return 'A sale price cannot be negative.'
  if (value >= base) return 'Sale price must be lower than the base price.'
  return null
}

/**
 * A window that can never open — a note, never a refusal.
 *
 * An end that is not after the start is impossible to reach (`isOnSale` needs the
 * start behind *and* the end ahead), so the sale would simply never appear. The
 * app does not check this and neither does the save: blocking it would mean a
 * seller could not fix the *name* of a product whose window the app wrote, and
 * refusing a save over a value that is stored exactly as typed is a rule this
 * form would be inventing. Saying so is the honest middle.
 */
export function saleWindowNote({ saleStartsAt, saleEndsAt }) {
  const start = saleDateInput(saleStartsAt)
  const end = saleDateInput(saleEndsAt)
  if (!start || !end) return null
  if (end > start) return null
  return 'The sale ends before it starts, so it will never be active.'
}

/**
 * What a customer pays, as one sentence the form shows under the sale fields.
 *
 * It is built from the READER's own functions — `isOnSale`, `effectivePrice`,
 * `salePercent` — rather than from the draft's raw fields, which is the only way
 * the sentence can be true. A preview that compared the two prices itself would be
 * a second implementation of the sale rule, and money is the one place a second
 * implementation is guaranteed to be wrong eventually: the seller would be told
 * one price and the customer charged another.
 *
 * The four things it can say, and the case each one is for:
 *
 *  - a live sale → both prices and the discount, because that is the state a
 *    seller is checking for;
 *  - no sale price at all → just the regular price;
 *  - a start in the future → when it starts and what customers pay until then;
 *  - an end in the past → that it is over, with the date.
 *
 * A sale price that is set but neither live nor explicably scheduled (a `0`, a
 * price at or above the regular one) falls through to the first sentence: there
 * is no price change to explain.
 *
 * `money` is injected rather than imported so this file stays free of the
 * formatting module — the same reasoning as `now`, which is a parameter so a test
 * can pin every branch.
 */
export function salePreview(product, { now = new Date(), money = (value) => String(value), date = String } = {}) {
  const base = `Customers pay ${money(Number(product?.price) || 0)}`

  if (isOnSale(product, now)) {
    const percent = salePercent(product, now)
    return `${base} ${money(effectivePrice(product, now))} while this sale is on — ${percent}% off.`
  }

  const salePrice = asNumber(product?.sale_price)
  if (salePrice === null || salePrice <= 0) return `${base}.`

  const start = asDate(product?.sale_starts_at)
  if (start && start.getTime() > now.getTime()) {
    return `${base} until this sale starts on ${date(start)}, then ${money(salePrice)}.`
  }

  const end = asDate(product?.sale_ends_at)
  if (end && end.getTime() < now.getTime()) {
    return `${base}. This sale ended on ${date(end)}.`
  }

  return `${base}.`
}
