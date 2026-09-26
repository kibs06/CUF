import { pluralize } from './constants.js'

/**
 * The makers list's index — a port of `store_screen.dart`'s `_reindexIfNeeded`
 * and the two things it feeds (`StoreHeroCard`'s stat pills and
 * `CrossStoreProductRow`'s top picks).
 *
 * The app's Stores tab is a hero carousel: one workshop at a time, with its
 * product count and a row of its picks under it. The portal shows all the
 * workshops at once instead — a page of real URLs has to be scannable — but the
 * *content* the app chose for a store is what makes a card read as a shop
 * rather than a business card, so it is ported: the rating (only once the store
 * has reviews), the number of pairs it sells, where it works, and a few of its
 * actual shoes.
 *
 * All of it is derived from the catalog already in memory, so a makers page
 * costs no request of its own.
 */

/**
 * Products grouped by their store: how many each store sells, and the lists
 * themselves.
 *
 * **Newest first, and that is the one deliberate divergence from the app.** The
 * app re-sorts each store's list by product id descending, because the list it
 * holds arrives shuffled and it needs a deterministic order; the portal's query
 * already orders by `created_at` descending, so insertion order *is* the newest
 * first — re-sorting by UUID here would actively scramble it.
 *
 * A product with no `store_id` is skipped rather than filed under `undefined`:
 * it cannot belong to a card that does not exist.
 *
 * @returns {{ counts: Record<string, number>, byStore: Record<string, object[]> }}
 */
export function indexProductsByStore(products) {
  const counts = {}
  const byStore = {}

  for (const product of products ?? []) {
    const storeId = product?.store_id ? String(product.store_id) : ''
    if (!storeId) continue

    counts[storeId] = (counts[storeId] ?? 0) + 1
    if (!byStore[storeId]) byStore[storeId] = []
    byStore[storeId].push(product)
  }

  return { counts, byStore }
}

/** How many pairs the whole association has on sale right now. */
export function totalPairs(index) {
  return Object.values(index?.counts ?? {}).reduce(
    (sum, count) => sum + (Number(count) || 0),
    0,
  )
}

/**
 * The store's newest products that HAVE a photograph — the card's window.
 *
 * A tile with no image is a grey square, and three of them turn a shop window
 * into a broken gallery, so products without a photo are skipped rather than
 * shown as placeholders. A store whose products have no photos at all gets the
 * count tile instead (see `storeFacts`), which is at least true.
 */
export function topPicksFor(index, storeId, limit = 3) {
  const products = index?.byStore?.[String(storeId ?? '')] ?? []
  return products
    .filter((product) => Boolean(product?.images?.[0]))
    .slice(0, limit)
}

/**
 * The store card's fact row: the app's `⭐ rating · 👟 products · 📍 location`
 * pills, with each fact present only when it can be said honestly.
 *
 *  * **`rating` appears only when `stores.rating` is not null.** The column
 *    stays NULL until the first review, which is exactly why the app guards it —
 *    a `0.0 ★` on a store nobody has reviewed yet is a rating that does not
 *    exist. Live data has one store at 4.0 and two with no rating at all.
 *  * **`pairs` counts what a customer can buy right now** (the catalog hook
 *    drops out-of-stock products first), and reads `No pairs listed yet` at
 *    zero rather than `0 pairs`.
 *  * **`location` is the first comma-separated place**, as the app's pill does:
 *    `📍 Carcar City` fits a card, `Valladolid, Carcar City, Cebu` does not. The
 *    full address stays on the store's own page.
 *
 * @returns {{ kind: 'rating' | 'pairs' | 'location', label: string, value?: string }[]}
 */
export function storeFacts(store, count = 0) {
  const facts = []

  const rating = store?.rating
  if (rating !== null && rating !== undefined && rating !== '') {
    const value = Number(rating)
    // `toStringAsFixed(1)` on the app side: 4 → '4.0', 4.25 → '4.3'.
    if (Number.isFinite(value)) {
      facts.push({ kind: 'rating', label: `${value.toFixed(1)}`, value: String(rating) })
    }
  }

  const pairs = Number(count) || 0
  facts.push({
    kind: 'pairs',
    label: pairs > 0 ? pluralize(pairs, 'pair') : 'No pairs listed yet',
  })

  const location = String(store?.location ?? '').trim()
  if (location) {
    facts.push({ kind: 'location', label: location.split(',')[0].trim() })
  }

  return facts
}
