/**
 * The customer search rule — a 1:1 port of `lib/utils/product_search.dart`.
 *
 * The rule that matters most here is the one that caused a real dead end:
 * searching **"Formal Shoes"** returned nothing, because `Formal` is a
 * *category* — the catalog's own word for those products — and no product is
 * named that or tagged with it. A search that cannot use the catalog's own
 * vocabulary is a search that tells a customer their own catalog does not
 * exist.
 *
 * The portal's own version of this page did exactly that: one
 * `name.includes(query)` test against the whole trimmed query, so a two-word
 * search only matched if those two words happened to be adjacent in a product
 * name. `matchesSearchQuery` matches whole-phrase names *and* every word
 * against the name, the category and the tags, which is the app's rule and now
 * this one's.
 *
 * `matchesStorefrontSearch` below is the ONE deliberate addition: the portal's
 * rows carry `store_name` and `collection`, which the app never searches
 * because it reaches a maker through their own page. A customer typing
 * "Carcar Leather" is naming a reason to buy, not a product, so the extension
 * is word-wise on those two fields and nothing else.
 */

/**
 * A query split into its lowercase words — `'Formal  Shoes '` → `['formal',
 * 'shoes']`. Empty for a blank query.
 *
 * Lowercasing happens once here so every comparison downstream can use
 * `includes`, and so `'Formal'` and `'formal'` cannot match differently on two
 * surfaces.
 */
export function searchWords(query) {
  return String(query ?? '')
    .toLowerCase()
    .split(/\s+/)
    .filter((word) => word.length > 0)
}

/**
 * Whether `product` matches `query`.
 *
 * A product matches when **any** of these holds:
 *
 *  * its name contains the whole query (`'formal derby'` → "Formal Derby");
 *  * its name contains any query word (so `'leather formal'` still finds
 *    "Formal Leather Derby");
 *  * its **category** contains any query word — the one that stops "Formal
 *    Shoes" being a dead end, since `Formal` is a category value;
 *  * one of its **tags** contains any query word.
 *
 * Any single word matching is enough, so a two-word query is a wider net than
 * either word alone — the opposite of an AND, deliberately: a customer typing
 * more words is narrowing in their head, not asking for a conjunction, and an
 * empty page is the worse failure.
 *
 * A blank query matches **nothing** (not everything): "no query" is not a
 * search, and a caller that wants the whole catalog should ask for the
 * catalog. Unknown fields (no `category`, `tags` not an array) simply do not
 * match.
 */
export function matchesSearchQuery(product, query) {
  const words = searchWords(query)
  if (words.length === 0) return false

  const name = String(product?.name ?? '').toLowerCase()
  const category = String(product?.category ?? '').toLowerCase()
  const tags = Array.isArray(product?.tags)
    ? product.tags.map((tag) => String(tag).toLowerCase())
    : []

  if (name.includes(String(query).trim().toLowerCase())) return true

  for (const word of words) {
    if (name.includes(word)) return true
    if (category.length > 0 && category.includes(word)) return true
    if (tags.some((tag) => tag.includes(word))) return true
  }
  return false
}

/**
 * The storefront's search: the app's rule, plus the two fields only this
 * surface has.
 *
 * `store_name` and `collection` are matched word-wise rather than by whole
 * phrase, for the same reason the name is: `'janella boots'` should find
 * Janella's boots and not require the customer to spell the workshop exactly.
 * Behaviour for a blank query is unchanged — `false`.
 */
export function matchesStorefrontSearch(product, query) {
  if (matchesSearchQuery(product, query)) return true

  const words = searchWords(query)
  if (words.length === 0) return false

  const storeName = String(product?.store_name ?? '').toLowerCase()
  const collection = String(product?.collection ?? '').toLowerCase()

  return words.some(
    (word) =>
      (storeName.length > 0 && storeName.includes(word)) ||
      (collection.length > 0 && collection.includes(word)),
  )
}

/**
 * What a suggestion *is*, so a panel can label a row without guessing from the
 * string. The values are RANKING positions, exactly as the Dart enum's `index`
 * is: a category outranks a tag, which outranks a product name when the count
 * and the prefix test tie.
 */
export const SEARCH_SUGGESTION_KIND = Object.freeze({
  category: 0,
  tag: 1,
  product: 2,
})

/**
 * Ranked search suggestions for a partially typed `query`, derived from the
 * catalog already in memory — **no query, no network**, so a panel can update
 * on every keystroke.
 *
 * Candidates are the categories, tags and product names whose text contains
 * any typed word. Ranking, in order:
 *
 *  1. **prefix before substring** — typing `boo` should offer `Boots` above
 *     `bamboo`; matching the start of a word is a stronger signal than matching
 *     its middle;
 *  2. **popularity** — how many products the term would return, so a live
 *     category outranks a tag used once;
 *  3. **kind** — categories, then tags, then product names;
 *  4. **alphabetical**, so the order is stable between renders.
 *
 * The typed query itself is never returned as a suggestion (a panel renders
 * "search for what I typed" as its own first row), and a blank query returns
 * nothing — a panel shows recent/trending terms instead.
 */
export function searchSuggestionsFor(products, { query, limit = 8 } = {}) {
  const words = searchWords(query)
  if (words.length === 0 || limit <= 0) return []

  const typed = String(query ?? '').trim().toLowerCase()

  // term (lowercased) → the display term, its kind, and how many products back it
  const counts = new Map()

  const consider = (rawTerm, kind) => {
    const term = String(rawTerm ?? '').trim()
    if (term.length === 0) return

    const lower = term.toLowerCase()
    // The thing they already typed is not a suggestion.
    if (lower === typed) return
    if (!words.some((word) => lower.includes(word))) return

    const existing = counts.get(lower)
    counts.set(lower, {
      // First sighting wins: a category that is also a product name stays a
      // category, because searching it returns the whole shelf.
      term: existing?.term ?? term,
      kind: existing?.kind ?? kind,
      count: (existing?.count ?? 0) + 1,
    })
  }

  for (const product of products ?? []) {
    // Category and tags are per-value, not per-product, so they are deduped by
    // the map above while still counting how many products back them.
    const category = String(product?.category ?? '')
    if (category.length > 0) consider(category, SEARCH_SUGGESTION_KIND.category)

    if (Array.isArray(product?.tags)) {
      for (const tag of product.tags) consider(tag, SEARCH_SUGGESTION_KIND.tag)
    }

    const name = String(product?.name ?? '')
    if (name.length > 0) consider(name, SEARCH_SUGGESTION_KIND.product)
  }

  const startsAWord = (term) => {
    const lower = term.toLowerCase()
    return words.some(
      (word) =>
        lower.startsWith(word) ||
        new RegExp(`(^|\\s)${escapeRegExp(word)}`).test(lower),
    )
  }

  return [...counts.values()]
    .sort((a, b) => {
      const byPrefix = Number(startsAWord(b.term)) - Number(startsAWord(a.term))
      if (byPrefix !== 0) return byPrefix

      const byCount = b.count - a.count
      if (byCount !== 0) return byCount

      const byKind = a.kind - b.kind
      if (byKind !== 0) return byKind

      const left = a.term.toLowerCase()
      const right = b.term.toLowerCase()
      return left < right ? -1 : left > right ? 1 : 0
    })
    .slice(0, limit)
    .map((candidate) => ({ term: candidate.term, kind: candidate.kind }))
}

/**
 * What a row in the suggestion panel is. A string, not the numeric ranking
 * above, because this is what a component switches on:
 *
 *  * `query` — "search for what I typed", always the panel's first row;
 *  * `category` / `tag` / `product` — the catalog's own words, from
 *    `searchSuggestionsFor`, carrying the kind so a row can be labelled.
 */
export const SEARCH_PANEL_ROW = Object.freeze({
  query: 'query',
  category: 'category',
  tag: 'tag',
  product: 'product',
})

/** The panel kinds, indexed by `SEARCH_SUGGESTION_KIND`'s ranking values. */
const SUGGESTION_KIND_NAMES = [
  SEARCH_PANEL_ROW.category,
  SEARCH_PANEL_ROW.tag,
  SEARCH_PANEL_ROW.product,
]

/**
 * The suggestion panel's rows, in the order they are rendered.
 *
 * The typed query is the FIRST row and not a suggestion: a customer who types
 * "sgandal" and sees nothing useful still needs a way to run what they typed,
 * and the panel must never render their text back at them as if the catalog had
 * suggested it (`searchSuggestionsFor` already excludes it, so this row is the
 * only place it appears). A blank query yields no rows at all — an empty panel
 * is not a panel, and the app shows recent/trending terms in its place, which
 * this portal has no history for yet.
 *
 * The shape is `[{ term, kind }]` with `kind` from `SEARCH_PANEL_ROW`, so the
 * list itself is testable without a DOM and the component only maps a kind to
 * an icon and a label.
 */
export function searchPanelRows(query, products, { limit = 8 } = {}) {
  const typed = String(query ?? '').trim()
  if (typed.length === 0) return []

  return [
    { term: typed, kind: SEARCH_PANEL_ROW.query },
    ...searchSuggestionsFor(products, { query: typed, limit }).map(
      (suggestion) => ({
        term: suggestion.term,
        kind: SUGGESTION_KIND_NAMES[suggestion.kind] ?? SEARCH_PANEL_ROW.product,
      }),
    ),
  ]
}

/** `RegExp.escape`'s job, for the word-boundary test above. */
function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}
