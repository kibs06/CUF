/**
 * Deciding whether a product actually stocks the customer's size — a 1:1 port
 * of `lib/utils/size_match.dart`.
 *
 * `sizeKeyRules.js` owns what a stored size *means*; this file owns the one
 * comparison every size-aware surface shares, so the "In your size" shelf and a
 * product page's advice line can never disagree about whether "my size" is
 * available.
 *
 * The reason this is a port and not a re-implementation is the failure mode: a
 * size-aware surface that is *confidently wrong* is worse than one that says
 * nothing. Every rule below therefore fails towards silence — an unknown
 * system, a bare value outside the plausible EU band, no inventory rows, a
 * product whose only size is a whole size away all answer "nothing to say"
 * rather than a guess.
 *
 * See `docs/AI/SIZE_AWARE_SHOPPING_PLAN.md` §5.2 (the match rule), §8 R1 (the
 * wrong-confident-claim risk) and §8 R4 (never contradicting the buy button).
 */
import {
  formatSize,
  formatSizeNumber,
  kEuMax,
  kEuMin,
  kNearSizeToleranceEu,
  sizeNumberInEu,
  sizeSystem,
} from './sizeKeyRules.js'

/**
 * The band a catalog size must fall inside to be believed as EU.
 *
 * The union of the two bands the app issues — kids' 22→35 and adult 35→48 — so
 * a child's size is matched as readily as an adult's. Outside it a value is
 * treated as an unknown system and never matched: a stored `'9'` that is really
 * a US 9 must not be read as EU 9 (plan §8 R1).
 */
export const kPlausibleEuMin = 22
export const kPlausibleEuMax = 48

/**
 * The systems this project can resolve into EU on its own. A size prefixed with
 * anything else (`'JP 25'`, `'CHN 42'`) is a system we own no chart for, so it
 * is skipped rather than guessed at.
 */
const KNOWN_SIZE_SYSTEMS = ['EU', 'US', 'UK']

/**
 * How a product relates to the customer's size. The values are the Dart enum's
 * `index`, and the distinction is load-bearing at every call site:
 *
 *  * `exact` — the product sells exactly the customer's size. Whether it can be
 *    *bought* is `stock`'s answer, not this one: a stocked size with 0 units is
 *    sold out, not absent.
 *  * `near` — the product does not sell the customer's size but holds something
 *    within `kNearSizeToleranceEu`. Reported as "closest is …", **never**
 *    substituted silently (plan §8 R3), and never counted as "my size".
 */
export const SIZE_MATCH_KIND = Object.freeze({
  exact: 0,
  near: 1,
})

/**
 * A `StockedSize`: the answer to "do you have my size?", with Dart's
 * `isAvailable` getter kept as an explicit field rather than a method, so a
 * caller cannot forget that a stocked size with 0 units is sold out.
 */
function stockedSize(euSize, stock, kind) {
  return { euSize, stock, kind, isAvailable: stock > 0 }
}

/**
 * The product's stock per EU size, from the authoritative `inventory` relation.
 *
 * `inventory` only, deliberately: the buy button's `stock.js` and checkout both
 * treat it as the source of truth, and `product_variants` is derived from it —
 * adding the two would inflate every figure and could contradict the buy button
 * (plan §8 R2/R4). Rows for the same size sum, because a product legitimately
 * holds one row per colour (Black EU 42: 2, Brown EU 42: 3 → 5 on EU 42).
 *
 * The Dart version casts `stock` with `as num?`, which would throw on a string.
 * JavaScript has no cast, so this reads the value the way `stock.js` does —
 * tolerant of the string numbers PostgREST can return, and 0 for a value that
 * is not a number at all.
 *
 * @returns {Map<number, number>} EU size → units available
 */
export function stockByEuSize(product) {
  const inventory = product?.inventory
  if (!Array.isArray(inventory)) return new Map()

  const bySize = new Map()
  for (const row of inventory) {
    if (!row || typeof row !== 'object') continue

    const raw = String(row.size ?? '')
    // A prefix we own no chart for is an unknown system, not EU.
    if (!KNOWN_SIZE_SYSTEMS.includes(sizeSystem(raw))) continue

    const eu = sizeNumberInEu(raw)
    if (eu === null) continue
    if (eu < kPlausibleEuMin || eu > kPlausibleEuMax) continue

    const parsed = Number(row.stock)
    const stock = Number.isFinite(parsed) ? Math.trunc(parsed) : 0

    bySize.set(eu, (bySize.get(eu) ?? 0) + (stock < 0 ? 0 : stock))
  }
  return bySize
}

/**
 * The size in `product`'s stock that answers `euSize`.
 *
 * An exact size wins even when it is sold out — the product *does* sell it — so
 * a caller can say "sold out" instead of silently offering the next size down,
 * which would be a different shoe on a different fit. Only when the product does
 * not sell the size at all does the nearest one within `kNearSizeToleranceEu`
 * answer, as `near`.
 *
 * Returns null when the product holds nothing close enough to mention, or no
 * size data at all — every caller must then render nothing rather than guess.
 *
 * @returns {{ euSize: number, stock: number, kind: number, isAvailable: boolean } | null}
 */
export function matchStockedSize(product, euSize) {
  const stock = stockByEuSize(product)
  if (stock.size === 0) return null

  const exact = stock.get(euSize)
  if (exact !== undefined) {
    return stockedSize(euSize, exact, SIZE_MATCH_KIND.exact)
  }

  let nearest = null
  let nearestDistance = Infinity
  for (const candidate of stock.keys()) {
    const distance = Math.abs(candidate - euSize)
    if (distance > kNearSizeToleranceEu) continue
    // Equally-near ties resolve DOWN, to the smaller size: when the data cannot
    // choose, never advertise a size above the customer's own.
    if (distance < nearestDistance || (distance === nearestDistance && candidate < nearest)) {
      nearest = candidate
      nearestDistance = distance
    }
  }
  if (nearest === null) return null

  return stockedSize(nearest, stock.get(nearest), SIZE_MATCH_KIND.near)
}

/**
 * Whether `product` can be bought right now in `euSize`.
 *
 * The one rule every surface that *suggests* products uses: an exact size with
 * stock behind it. A near size is not the customer's size, and a sold-out exact
 * size is not available.
 */
export function stocksMySize(product, euSize) {
  const match = matchStockedSize(product, euSize)
  return (
    match !== null &&
    match.kind === SIZE_MATCH_KIND.exact &&
    match.isAvailable
  )
}

/**
 * The customer's size for shopping, in EU, or null when they never gave one.
 *
 * The Dart version reads a scan held in memory as a second source. A browser
 * cannot scan a foot, so the portal has exactly one: the profile snapshot,
 * which the app writes from BOTH paths (the scanner and the manual picker), so
 * it is the most recent size the customer gave us either way. No size resolves
 * → null → every surface renders nothing.
 *
 * Deliberately does not fetch: the signed-in customer's profile is already on
 * hand, and a browse surface must never wait on — or fail because of — a network
 * call.
 */
export function shoppingEuSizeFrom(profile) {
  const raw = profile?.foot_size_ph
  if (raw === null || raw === undefined) return null
  if (String(raw).trim().length === 0) return null
  return sizeNumberInEu(String(raw))
}

/** A resolved EU size as a display label — `42` → `'EU 42'`. */
export function euSizeLabel(euSize) {
  return formatSize(formatSizeNumber(euSize))
}

/** The bare number of a resolved EU size — `42` → `'42'`, `42.5` → `'42.5'`. */
export function euSizeValue(euSize) {
  return formatSizeNumber(euSize)
}

/**
 * The "In your size" shelf's inclusion rule, in one place: purchasable right
 * now, in the customer's own size.
 *
 * The shelf and the shop's size filter both call this, so a product can never
 * appear in the shelf and then be filtered out of the list the shelf links to.
 */
export function productsInMySize(products, euSize) {
  if (euSize === null || euSize === undefined) return []
  return (products ?? []).filter((product) => stocksMySize(product, euSize))
}

/**
 * The product card's size tag — the plan's P2 table, as a value instead of as
 * JSX, so the three states are testable without a widget harness:
 *
 * | State | Label |
 * |---|---|
 * | exact, in stock | `EU 42` |
 * | exact, zero stock | `EU 42 sold out` |
 * | near, no size data, or no size on file | *nothing* |
 *
 * **A near size gets NO tag.** The plan's shelf rule and this one differ on
 * purpose: a shelf of "in your size" is a claim of buyability, so near sizes are
 * excluded there, and the same reasoning applies to a tag on every tile of a
 * grid — the customer reads it as "I can wear this" and it materialises a whole
 * size away. The near case is only ever *named* on the product page, where
 * there is room to say "closest is".
 *
 * "In stock" is `inventory` summed for that size (`stockByEuSize`), the same
 * source the buy button and the shelf read, so a tag cannot promise a pair the
 * cart will refuse (plan §8 R4).
 */
export function sizeBadgeFor(product, euSize) {
  if (euSize === null || euSize === undefined) return null

  const match = matchStockedSize(product, euSize)
  if (match === null || match.kind !== SIZE_MATCH_KIND.exact) return null

  const label = euSizeLabel(euSize)
  return match.isAvailable
    ? { tone: 'in-stock', label }
    : { tone: 'sold-out', label: `${label} sold out` }
}

/**
 * What a product page says about the customer's size — or nothing at all.
 *
 * The plan's P3 copy, verbatim, because the wording is the safety mechanism:
 *
 *  * in stock in my size → `In your size · EU 42 · 3 left`
 *  * my size sold out    → `In your size · EU 42 · sold out`
 *  * not stocked, near   → `EU 42 isn't available — closest is EU 41.5`
 *  * no size data / nothing close → `null`, and the page renders no line
 *
 * A near size is named as the *closest*, never offered as the customer's, and a
 * whole size away is not mentioned at all.
 */
export function sizeAdvice(product, euSize) {
  if (euSize === null || euSize === undefined) return null

  const match = matchStockedSize(product, euSize)
  if (match === null) return null

  const mine = euSizeLabel(euSize)

  if (match.kind === SIZE_MATCH_KIND.exact) {
    return match.isAvailable
      ? { tone: 'in-stock', text: `In your size · ${mine} · ${match.stock} left` }
      : { tone: 'sold-out', text: `In your size · ${mine} · sold out` }
  }

  return {
    tone: 'near',
    text: `${mine} isn't available — closest is ${euSizeLabel(match.euSize)}`,
  }
}
