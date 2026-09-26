import { useState } from 'react'
import { Link, useOutletContext } from 'react-router-dom'
import {
  LayoutGrid,
  List,
  PackageOpen,
  Plus,
  Search,
  X,
} from 'lucide-react'

import ProductGridCard from '../../components/seller/ProductGridCard.jsx'
import ProductListRow from '../../components/seller/ProductListRow.jsx'
import {
  SellerFigure,
  SellerPageBody,
  SellerPageHeader,
} from '../../components/seller/SellerPage.jsx'
import EmptyState from '../../components/ui/EmptyState.jsx'
import useProductView from '../../hooks/useProductView.js'
import { useSellerProducts } from '../../hooks/useSeller.js'
import { PRODUCT_CATEGORIES } from '../../lib/constants.js'
import { catalogSummary } from '../../lib/sellerRules.js'

/** The two ways the catalogue is drawn, in the order the toggle offers them. */
const VIEW_OPTIONS = [
  { id: 'grid', label: 'Photos', Icon: LayoutGrid },
  { id: 'list', label: 'Table', Icon: List },
]

/** Published state, as a filter — the axis a seller actually triages on. */
const STATUS_OPTIONS = [
  { id: 'all', label: 'All' },
  { id: 'published', label: 'On the storefront' },
  { id: 'hidden', label: 'Hidden' },
]

/**
 * The seller's product list.
 *
 * ## What this page is for
 *
 * Two questions, and they are different questions:
 *
 *  * *Is this the pair I meant?* — answered by photographs (`ProductGridCard`),
 *    which is also what the storefront itself shows a customer.
 *  * *Which of these is missing a size 42?* — answered by columns
 *    (`ProductListRow`), where the sizes, the price and the publish state of
 *    every product line up under each other.
 *
 * So both exist and the toolbar switches between them, with the choice
 * remembered per device (`useProductView`). A catalogue page that offers only
 * one of the two is a page half its owners cannot use properly: a maker with
 * twelve pairs works in pictures, and a seller with ninety works in numbers.
 *
 * ## The page says what state the catalogue is in before it lists it
 *
 * `catalogSummary` counts published, hidden and the two kinds of stock trouble
 * from the rows already fetched — no second query, so the summary cannot
 * disagree with the list underneath it. The two stock figures are counted per
 * **size**, because that is what the fix is: a product running low in one size
 * out of eight is one restock, not three.
 *
 * ## There is no card around the list
 *
 * It used to be a `SellerSection` — a card holding a grid of cards, which is a
 * box inside a box and one border doing nothing. The products are the page here,
 * so they sit on the page, and the summary above them is a tinted band rather
 * than a box, so nothing on this page is a card except the products themselves.
 *
 * Publishing is still toggled from the list rather than only from the product
 * form, because turning a product off is a thing sellers do in a hurry and
 * going three pages deep to do it is the friction that makes a catalog go stale.
 * The write is a partial update, so it cannot clobber a description someone is
 * editing in another tab.
 */
export default function SellerProducts() {
  const { store } = useOutletContext()
  const storeId = store?.id ?? null

  const productsQuery = useSellerProducts(storeId)
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('all')
  const [status, setStatus] = useState('all')
  const [view, setView] = useProductView()

  const products = productsQuery.data ?? []
  const summary = catalogSummary(products)

  const needle = query.trim().toLowerCase()
  const visible = products.filter((product) => {
    if (category !== 'all' && product.category !== category) return false
    if (status === 'published' && !product.is_published) return false
    if (status === 'hidden' && product.is_published) return false
    if (!needle) return true
    return (
      String(product.name ?? '').toLowerCase().includes(needle) ||
      String(product.sku ?? '').toLowerCase().includes(needle)
    )
  })

  const categories = [
    'all',
    ...new Set(
      products
        .map((product) => product.category)
        .filter((value) => Boolean(value)),
    ),
  ]

  const filtering = needle !== '' || category !== 'all' || status !== 'all'

  const clearFilters = () => {
    setQuery('')
    setCategory('all')
    setStatus('all')
  }

  return (
    <SellerPageBody>
      <SellerPageHeader
        eyebrow={`${products.length} ${
          products.length === 1 ? 'product' : 'products'
        }`}
        title="Products"
        description="What your storefront is showing, and how many of each size you have left."
        actions={
          <Link to="/seller/products/new" className="btn btn-primary">
            <Plus className="h-4 w-4" aria-hidden="true" />
            New product
          </Link>
        }
      />

      {products.length > 0 && <CatalogueSummary summary={summary} />}

      {products.length > 0 && (
        <div className="flex flex-col gap-3 border-b border-hairline pb-5 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex flex-wrap items-center gap-2.5">
            <label className="relative min-w-[13rem] flex-1 sm:max-w-xs">
              <span className="sr-only">Search your products</span>
              <Search
                className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted"
                aria-hidden="true"
              />
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search by name or SKU"
                className="h-10 w-full rounded-field border border-hairline bg-raised pl-9 pr-4 text-sm text-ink transition-colors duration-200 placeholder:text-muted/60 hover:border-card-edge"
              />
            </label>

            <label>
              <span className="sr-only">Filter by category</span>
              <select
                value={category}
                onChange={(event) => setCategory(event.target.value)}
                className="h-10 rounded-field border border-hairline bg-raised px-3 text-sm text-ink transition-colors duration-200 hover:border-card-edge"
              >
                {categories.map((value) => (
                  <option key={value} value={value}>
                    {value === 'all'
                      ? 'All categories'
                      : PRODUCT_CATEGORIES.includes(value)
                        ? value
                        : `${value} (other)`}
                  </option>
                ))}
              </select>
            </label>

            <div
              role="group"
              aria-label="Filter by publish state"
              className="flex flex-wrap items-center gap-2"
            >
              {STATUS_OPTIONS.map((option) => (
                <FilterChip
                  key={option.id}
                  label={option.label}
                  active={status === option.id}
                  count={
                    option.id === 'published'
                      ? summary.published
                      : option.id === 'hidden'
                        ? summary.hidden
                        : null
                  }
                  onClick={() => setStatus(option.id)}
                />
              ))}
            </div>
          </div>

          <div className="flex shrink-0 flex-wrap items-center gap-3">
            {filtering && (
              <>
                <p className="num text-xs text-muted">
                  {visible.length} of {products.length}
                </p>
                <button
                  type="button"
                  onClick={clearFilters}
                  className="inline-flex items-center gap-1 text-xs font-semibold text-clay-ink underline-offset-4 hover:underline"
                >
                  <X className="h-3.5 w-3.5" aria-hidden="true" />
                  Clear
                </button>
              </>
            )}

            <ViewToggle value={view} onChange={setView} />
          </div>
        </div>
      )}

      {productsQuery.isLoading ? (
        <CatalogueSkeleton view={view} />
      ) : productsQuery.isError ? (
        <div
          role="alert"
          className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm text-ink"
        >
          We could not load your products. Reload the page to try again.
        </div>
      ) : products.length === 0 ? (
        <EmptyState
          Icon={PackageOpen}
          title="No products yet"
          description="Add your first pair and it appears on the storefront straight away."
          action={
            <Link to="/seller/products/new" className="btn btn-primary">
              <Plus className="h-4 w-4" aria-hidden="true" />
              New product
            </Link>
          }
        />
      ) : visible.length === 0 ? (
        <div className="py-10 text-center">
          <p className="text-sm text-muted">Nothing matches those filters.</p>
          <button
            type="button"
            onClick={clearFilters}
            className="mt-3 text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
          >
            Show everything
          </button>
        </div>
      ) : view === 'list' ? (
        <ul className="divide-y divide-hairline-soft">
          {visible.map((product) => (
            <ProductListRow
              key={product.id}
              product={product}
              storeId={storeId}
            />
          ))}
        </ul>
      ) : (
        <ul className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
          {visible.map((product) => (
            <ProductGridCard
              key={product.id}
              product={product}
              storeId={storeId}
            />
          ))}
        </ul>
      )}
    </SellerPageBody>
  )
}

/**
 * The catalogue in four figures, as one line of readings.
 *
 * Deliberately not clickable. Each one describes a state the seller can already
 * filter to from the toolbar, and a figure that filters when clicked *and* reads
 * as a number when not is the sort of control that gets clicked once by mistake
 * and then distrusted. The tone is the message: published and hidden are always
 * neutral, and the two stock figures only turn crimson when they are not zero —
 * a summary that shouts on a healthy catalogue is a summary nobody reads.
 *
 * ## What changed, and why it is one band rather than four cells
 *
 * It was a bordered box of four equal cells separated by full-height 1px rules
 * (`gap-px` over a hairline colour) — which is a *table*, and it said so: four
 * columns of equal weight, every one carrying an uppercase heading, a figure and a
 * sentence, so the eye had to read all twelve lines to find the one that mattered.
 * The lines were also the wrong way round. A seller opens this page to see two
 * things — *is anything hidden* and *is anything running out* — and both were
 * written under a heading they had to match against a number first.
 *
 * So: **the figure leads and its label follows it**, four to a row with whitespace
 * where the rules were (`SellerFigure layout="inline"`), on a tinted band with no
 * border at all. Nothing is boxed, so the strip reads as part of the page rather
 * than as a table sitting on it, and the two figures that can be a problem are the
 * only coloured things in it.
 *
 * The hints stay, because they are not repetition: *of 5 in the catalogue* is what
 * makes "5 published" a proportion, and *sizes · 1 product* is what turns a count
 * of sizes into a number of things to go and fix.
 */
function CatalogueSummary({ summary }) {
  const figures = [
    {
      label: 'Published',
      value: summary.published,
      hint: `of ${summary.total} in the catalogue`,
    },
    {
      label: 'Hidden',
      value: summary.hidden,
      hint:
        summary.hidden === 0
          ? 'everything is on the storefront'
          : 'not on the storefront',
    },
    {
      label: 'Running low',
      value: summary.lowSizes,
      tone: summary.lowSizes > 0 ? 'alert' : 'neutral',
      hint:
        summary.lowSizes === 0
          ? 'no size is down to five'
          : `sizes · ${summary.lowProducts} ${
              summary.lowProducts === 1 ? 'product' : 'products'
            }`,
    },
    {
      label: 'Sold out',
      value: summary.outSizes,
      tone: summary.outSizes > 0 ? 'alert' : 'neutral',
      hint:
        summary.outSizes === 0
          ? 'no size is at zero'
          : `sizes · ${summary.outProducts} ${
              summary.outProducts === 1 ? 'product' : 'products'
            }`,
    },
  ]

  return (
    <div className="flex flex-wrap gap-x-10 gap-y-6 rounded-card bg-subtle/50 px-5 py-4 sm:px-6">
      {figures.map((figure) => (
        /*
          `flex-1` with a floor, so the four sit evenly across a wide page and
          fall to two and then one as the page narrows — no breakpoint decides
          that, the content does.
        */
        <div key={figure.label} className="min-w-[8.5rem] flex-1">
          <SellerFigure
            label={figure.label}
            value={figure.value}
            tone={figure.tone}
            layout="inline"
          />
          <p className="mt-1 text-xs leading-relaxed text-muted">{figure.hint}</p>
        </div>
      ))}
    </div>
  )
}

/** A filter chip with its own count — the toolbar's status axis. */
function FilterChip({ label, active, count = null, onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`inline-flex h-10 items-center gap-1.5 rounded-full border px-3.5 text-xs font-semibold transition-colors duration-200 ease-out-cubic ${
        active
          ? 'border-clay bg-clay text-ink-inverse'
          : 'border-hairline text-muted-strong hover:border-card-edge hover:text-ink'
      }`}
    >
      {label}
      {count !== null && (
        <span
          className={`num ${active ? 'text-ink-inverse/80' : 'text-muted'}`}
        >
          {count}
        </span>
      )}
    </button>
  )
}

/**
 * Photos or table — a two-state control, so `aria-pressed` on two buttons rather
 * than a `role="tablist"`: tabs are for panels, and these two draw the same
 * products.
 */
function ViewToggle({ value, onChange }) {
  return (
    <div
      role="group"
      aria-label="How to show your products"
      className="inline-flex items-center gap-0.5 rounded-full border border-hairline bg-raised p-0.5"
    >
      {VIEW_OPTIONS.map(({ id, label, Icon }) => {
        const active = value === id

        return (
          <button
            key={id}
            type="button"
            onClick={() => onChange(id)}
            aria-pressed={active}
            className={`inline-flex h-9 items-center gap-1.5 rounded-full px-3 text-xs font-semibold transition-colors duration-200 ease-out-cubic ${
              active
                ? 'bg-clay text-ink-inverse'
                : 'text-muted-strong hover:text-ink'
            }`}
          >
            <Icon className="h-4 w-4" aria-hidden="true" />
            <span className="hidden sm:inline">{label}</span>
            <span className="sr-only sm:hidden">{label}</span>
          </button>
        )
      })}
    </div>
  )
}

/** A loading placeholder shaped like the view that is coming. */
function CatalogueSkeleton({ view }) {
  if (view === 'list') {
    return (
      <div className="space-y-2">
        {[0, 1, 2, 3, 4, 5].map((key) => (
          <div key={key} className="shimmer h-16 rounded-card" />
        ))}
      </div>
    )
  }

  return (
    <div className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
      {[0, 1, 2].map((key) => (
        <div key={key} className="shimmer h-80 rounded-card" />
      ))}
    </div>
  )
}
