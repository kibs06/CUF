/**
 * Stock helpers — a 1:1 port of `lib/utils/product_stock.dart`.
 *
 * `inventory` is the AUTHORITATIVE stock source, not `product_variants`:
 * checkout validates against it and treats a missing match as out of stock.
 * These helpers share that semantics, so the portal hides exactly what the app
 * hides and what a customer genuinely cannot buy.
 *
 * `stockForSize` and `availableSizes` have no Dart counterpart — they are the
 * product page's size grid, added here. They were written against the same
 * `inventory` relation and have since been corrected to agree with the two
 * things that can overrule them: the cart (which sums a size's rows) and
 * `sizeMatchRules.stocksMySize` (which does the same).
 */
import { compareSizes } from './sizeKeyRules.js'

function asInt(value) {
  if (value === null || value === undefined) return null
  const parsed = typeof value === 'number' ? value : Number.parseFloat(value)
  return Number.isFinite(parsed) ? Math.trunc(parsed) : null
}

/**
 * Total purchasable stock across every size.
 *
 * A product with NO inventory rows totals 0 and is therefore out of stock —
 * matching `resolveInventoryStock`'s "no match" convention on the app side,
 * rather than treating "no rows" as "unlimited".
 */
export function totalStock(product) {
  const inventory = product?.inventory
  if (!Array.isArray(inventory)) return 0
  return inventory.reduce(
    (sum, item) => sum + (asInt(item?.stock) ?? 0),
    0,
  )
}

/** Whether a product has no stock on any size (hidden from browse). */
export function isOutOfStock(product) {
  return totalStock(product) <= 0
}

/**
 * Products a customer can purchase right now — the `hideOutOfStock` browse
 * rule. This is "hide until restocked": an out-of-stock product drops out of
 * the catalog here and comes back on the next fetch once a seller restocks it.
 */
export function purchasableProducts(products) {
  return products.filter((product) => !isOutOfStock(product))
}

/**
 * Stock for one size, or 0 when that size has no row. Used by the product
 * page's size selector.
 *
 * SUMMED across the rows that carry the size, not the first one found. A
 * product legitimately holds one `inventory` row per colour (the app's own
 * example: Black EU 42: 2, Brown EU 42: 3 → 5 available on EU 42), and the cart
 * already sums them (`cart.js` keys its fallback stock by
 * `${productId}-${size}`). Reading only the first row meant the size grid could
 * strike a size through as sold out while the cart would happily accept it —
 * the contradiction with the buy button the size plan's §8 R4 exists to stop.
 */
export function stockForSize(product, size) {
  const inventory = product?.inventory
  if (!Array.isArray(inventory)) return 0
  return inventory
    .filter((item) => String(item?.size) === String(size))
    .reduce((sum, item) => sum + (asInt(item?.stock) ?? 0), 0)
}

/**
 * The sizes a product offers — each one ONCE, ordered by numeric value.
 *
 * Sorted rather than left in row order, which is the app's §4.3 fix ported
 * across: `inventory` rows arrive in whatever order they were written (the live
 * catalog hands back `40, 39, 40, 41.5…`), so a size grid used to read as a
 * jumble and a half size sorted as though it were a different number entirely.
 * `compareSizes` (from `sizeKeyRules.js`) is the one comparator, so this grid
 * and the app's cannot order the same product differently.
 *
 * Deduped because the rows are per colour: two rows for EU 42 are one size a
 * customer can choose, and rendering it twice — with `stockForSize`'s sum
 * behind only one of the two chips — is a size grid that contradicts itself.
 */
export function availableSizes(product) {
  const inventory = product?.inventory
  if (!Array.isArray(inventory)) return []
  return [
    ...new Set(inventory.map((item) => String(item?.size)).filter(Boolean)),
  ].sort(compareSizes)
}
