import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ImageOff, Package, Pencil } from 'lucide-react'

import QuickStockPanel from './QuickStockPanel.jsx'
import SizeStockChips from './SizeStockChips.jsx'
import Switch from '../ui/Switch.jsx'
import { formatCurrency } from '../../lib/constants.js'
import { stockState, stockSummary } from '../../lib/sizeSystems.js'
import { useUpdateSellerProduct } from '../../hooks/useSeller.js'

/**
 * A product, as a row of numbers.
 *
 * The grid answers *is this the pair I meant?* — this answers the other
 * question a catalogue owner has: *which of these is missing a size 42?* Two
 * views because those are genuinely two questions, and the page lets the seller
 * pick which one they opened it for.
 *
 * ## The columns are fixed tracks, not `auto`
 *
 * This is the same lesson the dashboard's recent-orders list taught, and it cost
 * a second attempt there: an `auto` track is sized **per row**, so a "table" of
 * them lines up only while every cell in it happens to be the same width. Left to
 * themselves, a long product name pushes its price left and the next row's price
 * sits somewhere else, which is how a list of numbers stops being readable as a
 * column of numbers. Fixed tracks (`7rem` of price, `20rem` of chips) put every
 * price's decimal point and every chip strip's left edge on one line, and the
 * `minmax(0,1fr)` name column absorbs the rest without ever growing past its
 * share.
 *
 * ## What is hidden on a phone, and why that is not information lost
 *
 * Below `xl` the size chips go. A phone cannot show a name, a price, chips, a
 * switch and a pencil side by side at readable sizes, and the chips are the part
 * worth less than the rest *because* the badges stay: "Sold out" and "Running
 * low" are on every screen size, in the name's own line, and the per-size detail
 * is one tap away on the row itself. The row is a link to the product — that is
 * what the stretched link and the pencil mean.
 */
export default function ProductListRow({ product, storeId }) {
  const mutation = useUpdateSellerProduct(storeId)
  const [stockOpen, setStockOpen] = useState(false)

  const cover = product.images?.[0] ?? null
  const stock = stockSummary(product.inventory)

  const states = (product.inventory ?? []).map((row) => stockState(row?.stock))
  const soldOut = stock.sizes > 0 && stock.total <= 0
  const runningLow = !soldOut && states.includes('low')

  const onTogglePublished = (next) =>
    mutation.mutate({ productId: product.id, patch: { is_published: next } })

  return (
    <li className="relative transition-colors duration-200 ease-out-cubic hover:bg-subtle/50">
      <Link
        to={`/seller/products/${product.id}`}
        className="absolute inset-0 z-20"
        aria-label={`Edit ${product.name}`}
      />

      <div className="-mx-2 grid grid-cols-[3rem_minmax(0,1fr)_7rem_auto] items-center gap-x-4 gap-y-2 px-2 py-3 xl:grid-cols-[3rem_minmax(0,1fr)_20rem_7rem_auto]">
        <span className="relative block h-12 w-12 overflow-hidden rounded-card border border-hairline bg-subtle">
          {cover ? (
            <img
              src={cover}
              alt=""
              loading="lazy"
              decoding="async"
              className="h-full w-full object-cover"
            />
          ) : (
            <span className="flex h-full items-center justify-center">
              <ImageOff
                className="h-4 w-4 text-muted/60"
                strokeWidth={1.5}
                aria-hidden="true"
              />
            </span>
          )}
        </span>

        <div className="min-w-0">
          <p className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <span className="truncate font-medium text-ink">{product.name}</span>

            {!product.is_published && (
              <span className="shrink-0 rounded-full bg-chrome/85 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.06em] text-ink-inverse">
                Hidden
              </span>
            )}
            {soldOut && (
              <span className="shrink-0 rounded-full bg-crimson/[0.12] px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.06em] text-crimson">
                Sold out
              </span>
            )}
            {runningLow && (
              <span className="shrink-0 rounded-full bg-amber/[0.14] px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.06em] text-amber">
                Running low
              </span>
            )}
          </p>

          {/*
            Built from what exists rather than from placeholders: a missing SKU
            is not worth the words "No SKU" in a line that already has a
            category and a size count in it, and a `.filter(Boolean).join`
            cannot leave a separator pointing at nothing.
          */}
          <p className="mt-0.5 truncate text-xs text-muted">
            {[product.sku, product.category, stock.label]
              .filter(Boolean)
              .join(' · ')}
          </p>
        </div>

        {/* Below `xl` this cell is not rendered at all, which is why the row's
            own track list drops it there rather than hiding an empty box. */}
        <SizeStockChips
          inventory={product.inventory}
          size="sm"
          limit={6}
          className="hidden xl:flex"
        />

        <span className="num text-right text-sm font-semibold text-ink">
          {formatCurrency(product.price)}
        </span>

        <div className="relative z-30 flex items-center justify-end gap-3">
          <button
            type="button"
            onClick={() => setStockOpen((open) => !open)}
            aria-expanded={stockOpen}
            /* Only while the panel exists: `aria-controls` naming an element
               that is not in the DOM describes nothing. */
            aria-controls={stockOpen ? `stock-${product.id}` : undefined}
            title="Top up stock"
            className={`inline-flex h-8 w-8 items-center justify-center rounded-field border transition-colors duration-200 ease-out-cubic ${
              stockOpen
                ? 'border-clay bg-clay/[0.10] text-clay-ink'
                : 'border-hairline text-muted-strong hover:border-card-edge hover:text-ink'
            }`}
          >
            <Package className="h-4 w-4" aria-hidden="true" />
            <span className="sr-only">Top up stock for {product.name}</span>
          </button>

          <Switch
            size="sm"
            checked={Boolean(product.is_published)}
            disabled={mutation.isPending}
            onChange={onTogglePublished}
            ariaLabel={
              product.is_published
                ? `Remove ${product.name} from the storefront`
                : `Put ${product.name} on the storefront`
            }
          />

          <Pencil
            className="h-4 w-4 shrink-0 text-clay-ink"
            aria-hidden="true"
          />
        </div>

        {/*
          The panel is the last cell of the same grid, spanning every track, so
          it opens under the row it belongs to instead of in a dialog over the
          list. `col-span-full` rather than a track count: the row has four
          columns below `xl` and five above it, and the panel is full width in
          both.
        */}
        {stockOpen && (
          <div id={`stock-${product.id}`} className="relative z-30 col-span-full">
            <QuickStockPanel
              product={product}
              storeId={storeId}
              onDone={() => setStockOpen(false)}
            />
          </div>
        )}
      </div>
    </li>
  )
}
