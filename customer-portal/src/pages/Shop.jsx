import { useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { motion } from 'motion/react'
import { PackageOpen } from 'lucide-react'

import ProductGrid from '../components/product/ProductGrid'
import { useTransitionTiming } from '../components/motion/transitions'
import EmptyState from '../components/ui/EmptyState'
import { ProductGridSkeleton } from '../components/ui/Skeleton'
import { useProducts } from '../hooks/useCatalog'
import { useMySize } from '../hooks/useMySize.js'
import { catalogCategories } from '../lib/catalog'
import { pluralize } from '../lib/constants'
import { effectivePrice, isOnSale } from '../lib/pricing'
import { matchesStorefrontSearch } from '../lib/searchRules'
import { randomSeed, shuffled } from '../lib/shuffleRules'
import { euSizeLabel, euSizeValue, stocksMySize } from '../lib/sizeMatchRules'

const SORTS = [
  { value: 'shuffled', label: 'Shuffled' },
  { value: 'newest', label: 'Newest first' },
  { value: 'price-asc', label: 'Price: low to high' },
  { value: 'price-desc', label: 'Price: high to low' },
  { value: 'discount', label: 'Biggest discount' },
]

/**
 * The catalog.
 *
 * All of the state lives in the URL (`?q=&category=&sort=&onSale=&size=`) rather
 * than in component state. That is what makes a filtered catalog shareable — a
 * customer can send "the sandals under this filter" to a friend, land on it
 * with the back button, and bookmark it. Component state would make every one
 * of those a dead link back to an unfiltered list.
 *
 * Filtering and sorting run on the already-cached catalog, so changing a chip
 * is instant and issues no request.
 *
 * What a query *matches* is not decided here — it is `lib/searchRules.js`, a
 * port of the app's `product_search.dart`. It used to be one `includes()` test
 * against the whole typed string, which meant a two-word search like "Formal
 * Shoes" only matched if those words happened to sit adjacent in a product
 * name, so the catalog's own vocabulary (its categories) found nothing. See
 * "Business rules are ported, never re-implemented" in the README.
 *
 * `?size=` is what the home page's "In your size" shelf links to, and it filters
 * with the SAME rule that built it (`stocksMySize`), so the shelf and the
 * page it opens can never disagree. Its chip follows the app's dead-end rule: it
 * is offered only when the customer has a size on file AND the catalog actually
 * stocks something in it — a filter that can only ever return an empty page is
 * worse than no filter at all.
 *
 * `?sort=` defaults to **shuffled** rather than newest-first: a shelf in
 * insertion order is the same shelf every visit, and on a fifteen-product
 * catalog the first row is the whole visit. See `lib/shuffleRules.js` for why
 * the order is a seeded value and not a `Math.random()` comparator.
 *
 * The deal is cut from the whole catalog ONCE and the filters then subtract
 * from it, so a category narrows the shelf the customer was already looking at
 * rather than rearranging it — and the seed is fixed for the life of the page,
 * so nothing moves under a cursor either. The seed is deliberately NOT in the
 * URL: a random order is not a shareable arrangement, and a link that opened
 * onto one particular shuffle of the catalog would be a stranger page to land
 * on than the catalog itself. The filters still round-trip exactly as before;
 * only the arrangement is per-visit.
 */
export default function Shop() {
  const [params, setParams] = useSearchParams()
  const productsQuery = useProducts()

  const query = params.get('q') ?? ''
  const category = params.get('category') ?? ''
  const sort = params.get('sort') ?? 'shuffled'
  // One deal per visit, held for the life of the page: a new seed per render
  // would move the cards under the cursor every time anything re-rendered.
  const [seed] = useState(randomSeed)
  const onSaleOnly = params.get('onSale') === '1'
  // A hand-edited `?size=abc` is not a filter, it is a typo: NaN is dropped
  // rather than compared against every product.
  const sizeParam = Number(params.get('size'))
  const sizeFilter = Number.isFinite(sizeParam) && sizeParam > 0 ? sizeParam : null

  const products = productsQuery.data ?? []
  const categories = useMemo(() => catalogCategories(products), [products])

  const mySize = useMySize()
  const mySizeCount = useMemo(
    () =>
      mySize === null
        ? 0
        : products.filter((product) => stocksMySize(product, mySize)).length,
    [products, mySize],
  )

  /*
    The deal. One shuffle of the whole catalog, memoised on the catalog and the
    seed — NOT a shuffle of whatever survives the filters.

    That distinction is the whole reason this is a separate memo. Shuffling the
    filtered list would deal `shuffled(filtered)` a first time on every filter
    change, and Fisher–Yates over three items does not preserve the relative
    order of those three in a shuffle of fifteen — so choosing a category would
    not narrow the shelf the customer was looking at, it would rearrange it.
    Dealing the catalog once and filtering the deal means a filter genuinely
    subtracts cards and leaves the rest where they were.
  */
  const deal = useMemo(() => shuffled(products, seed), [products, seed])

  const visible = useMemo(() => {
    // An empty query is not a search: it shows the whole catalog. The rule
    // itself treats blank as "matches nothing" on purpose — a caller that wants
    // the catalog asks for the catalog, which is what this branch is.
    const searching = query.trim().length > 0

    // Filter the ORDER the chosen sort implies: the deal when shuffled, the
    // query's own `created_at` order otherwise.
    const source = sort === 'shuffled' ? deal : products

    const filtered = source.filter((product) => {
      if (category && product.category !== category) return false
      if (onSaleOnly && !isOnSale(product)) return false
      if (sizeFilter !== null && !stocksMySize(product, sizeFilter)) return false
      if (!searching) return true

      return matchesStorefrontSearch(product, query)
    })

    switch (sort) {
      case 'price-asc':
        return [...filtered].sort(
          (a, b) => effectivePrice(a) - effectivePrice(b),
        )
      case 'price-desc':
        return [...filtered].sort(
          (a, b) => effectivePrice(b) - effectivePrice(a),
        )
      case 'discount':
        return [...filtered].sort(
          (a, b) => discountOf(b) - discountOf(a),
        )
      case 'newest':
        // `created_at` descending, which is also the order the query returns.
        return filtered
      default:
        // Shuffled — already in the deal's order, and filtered in place.
        return filtered
    }
  }, [products, deal, query, category, sort, onSaleOnly, sizeFilter])

  /** Update one URL param without dropping the others. */
  const setParam = (key, value) => {
    const next = new URLSearchParams(params)
    if (value) next.set(key, value)
    else next.delete(key)
    setParams(next, { replace: true })
  }

  const hasFilters = Boolean(query || category || onSaleOnly || sizeFilter)

  return (
    <div className="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
      <header>
        <p className="overline">The catalog</p>
        <h1 className="mt-2 font-display text-3xl font-semibold text-ink sm:text-4xl">
          {category ||
            (query
              ? `Results for “${query}”`
              : sizeFilter !== null
                ? `In your size — ${euSizeLabel(sizeFilter)}`
                : 'Every pair')}
        </h1>
        {!productsQuery.isLoading && (
          <p className="mt-2 text-sm text-muted">
            {pluralize(visible.length, 'product')}
            {onSaleOnly && ' on sale'}
          </p>
        )}
      </header>

      {/* ── Filters ─────────────────────────────────────────────── */}
      <div className="mt-7 flex flex-col gap-4 border-b border-hairline pb-5 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Filter by category">
          <Chip
            label="All"
            active={!category}
            onClick={() => setParam('category', '')}
          />
          {/*
            `My size · EU 42` — the app's P2 label, naming the size the app
            believes so a wrong profile is visible and correctable rather than
            silently filtering the catalog. Shown while the filter is on even if
            nothing matches (otherwise the off switch disappears with the
            results), and otherwise only when it can yield something.
          */}
          {mySize !== null && (mySizeCount > 0 || sizeFilter !== null) && (
            <Chip
              label={`My size · ${euSizeLabel(mySize)}`}
              active={sizeFilter !== null}
              onClick={() =>
                setParam('size', sizeFilter !== null ? '' : euSizeValue(mySize))
              }
            />
          )}
          {categories.map((value) => (
            <Chip
              key={value}
              label={value}
              active={category === value}
              onClick={() =>
                setParam('category', category === value ? '' : value)
              }
            />
          ))}
        </div>

        <div className="flex shrink-0 items-center gap-3">
          <button
            type="button"
            onClick={() => setParam('onSale', onSaleOnly ? '' : '1')}
            aria-pressed={onSaleOnly}
            className={`rounded-full border px-3.5 py-2 text-xs font-semibold transition-colors duration-200 ease-out-cubic ${
              onSaleOnly
                ? 'border-clay bg-clay text-ink-inverse'
                : 'border-hairline text-muted-strong hover:border-card-edge hover:text-ink'
            }`}
          >
            On sale
          </button>

          <label htmlFor="sort" className="sr-only">
            Sort products
          </label>
          {/* "Shuffled" is here so the default is legible and reversible: after
              picking a price order there has to be a way back to the deal. */}
          <select
            id="sort"
            value={sort}
            onChange={(event) => setParam('sort', event.target.value)}
            className="h-9 rounded-field border border-hairline bg-raised px-3 text-xs font-medium text-ink transition-colors duration-200 hover:border-card-edge"
          >
            {SORTS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      {hasFilters && (
        <button
          type="button"
          onClick={() => setParams({}, { replace: true })}
          className="mt-4 text-xs font-semibold text-clay-ink underline-offset-4 hover:underline"
        >
          Clear all filters
        </button>
      )}

      {/* ── Results ─────────────────────────────────────────────── */}
      <div className="mt-8">
        {productsQuery.isLoading ? (
          <ProductGridSkeleton count={8} />
        ) : productsQuery.isError ? (
          <EmptyState
            Icon={PackageOpen}
            title="Could not load the catalog"
            description="Please check your connection and try again."
          />
        ) : visible.length > 0 ? (
          <ProductGrid products={visible} />
        ) : (
          <EmptyState
            Icon={PackageOpen}
            title="Nothing matches yet"
            description={
              hasFilters
                ? 'Try a different category, or clear the filters to see everything in stock.'
                : 'No products are available right now. Check back shortly.'
            }
          />
        )}
      </div>
    </div>
  )
}

/**
 * A category chip with a pill that SLIDES between chips.
 *
 * `layoutId` is what does it: motion matches the two elements across renders
 * and animates the geometry, so the fill travels instead of blinking off one
 * chip and on to the next.
 *
 * The reduced-motion branch swaps the spring for a zero duration rather than
 * simply letting it run — a travelling pill is exactly the kind of large,
 * continuous movement the preference exists to stop.
 */
function Chip({ label, active, onClick }) {
  const { reduce } = useTransitionTiming()

  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`relative rounded-full px-3.5 py-2 text-xs font-semibold transition-colors duration-200 ease-out-cubic ${
        active ? 'text-ink-inverse' : 'text-muted-strong hover:text-ink'
      }`}
    >
      {active && (
        <motion.span
          layoutId="category-chip"
          className="absolute inset-0 rounded-full bg-clay"
          transition={
            reduce ? { duration: 0 } : { type: 'spring', stiffness: 420, damping: 34 }
          }
        />
      )}
      <span className="relative">{label}</span>
    </button>
  )
}

function discountOf(product) {
  if (!isOnSale(product)) return -1
  const original = Number(product.price) || 0
  if (original <= 0) return -1
  return (original - effectivePrice(product)) / original
}
