import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ImageOff, Package, Pencil } from 'lucide-react'

import QuickStockPanel from './QuickStockPanel.jsx'
import SizeStockChips from './SizeStockChips.jsx'
import { useProductRowMenu } from './useProductRowMenu.jsx'
import Switch from '../ui/Switch.jsx'
import { formatCurrency } from '../../lib/constants.js'
import { stockState, stockSummary } from '../../lib/sizeSystems.js'
import { isOnTheStorefront } from '../../lib/stock.js'
import { useUpdateSellerProduct } from '../../hooks/useSeller.js'

/**
 * A product, as a photograph.
 *
 * A card rather than a row, for the reason the list has always been cards: a
 * product is a photograph before it is a row of numbers, and a maker checking
 * their own catalog is doing what a shopper does — recognising a pair. The list
 * view exists for the other question (`ProductListRow`), and this is the default
 * because this is the one that answers *is this the pair I meant?*
 *
 * ## The whole tile is the edit button
 *
 * A stretched link covers the card and the visible controls sit above it, which
 * is the same pattern the storefront's `ProductCard` uses. A card that is also a
 * button is two tab stops and two announcements for one destination; a card
 * where only a small "Edit" word is clickable makes the photograph — the biggest,
 * most obvious target on the page — do nothing.
 *
 * The switch is the exception, and it is why the stretched link is `z-20` and the
 * footer is `z-30`: publishing is the one thing a seller does *from* this page
 * without leaving it, so it has to win the click. `Pencil` beside it is
 * `pointer-events-none` and `aria-hidden` — it is an affordance for the link
 * underneath, not a second link.
 *
 * ## The badges moved onto the photograph
 *
 * "Hidden", "Sold out", "Running low" and "Not visible" are states of the
 * *product*, and the photograph is where a seller's eye already is. They used to
 * be small grey words under the price, which is the part of a tile nobody reads.
 * On the image they are unmissable and they cost no vertical space, which is what
 * pays for the size chips underneath.
 *
 * **"Hidden" and "Not visible" are two different ways to be off the storefront,
 * and this card is the only place that says so.** "Hidden" is the switch: the
 * seller turned the product off. "Not visible" is the storefront's own rule: the
 * product is switched ON and still not in the shop, because `purchasableProducts`
 * drops anything with zero stock — which is every product that has not been given
 * a size yet, and every one sold out. Both read `isOnTheStorefront`, the same
 * rule the customer surfaces apply, so the badge cannot disagree with the
 * catalog about whether a pair is on it.
 *
 * ## Right-click, and why it is on the `li`
 *
 * The card has four interactive things in it already (a stretched link, a switch,
 * a stock button, and the panel that button opens), so the menu hangs off the
 * `li` and catches the whole tile rather than the link's own box. The primitive
 * steps aside for text fields, which matters here: the quick-stock panel's inputs
 * keep the browser's menu, and its paste.
 *
 * The menu itself — items, and the 3D-model request prompt one of them opens — is
 * `useProductRowMenu`, so this card and `ProductListRow` cannot offer different
 * things about the same product.
 */
export default function ProductGridCard({ product, storeId }) {
  const mutation = useUpdateSellerProduct(storeId)
  const [stockOpen, setStockOpen] = useState(false)
  /*
    The menu and its one prompt come from the hook — see `useProductRowMenu` for
    why the row does not assemble `useContextMenu` itself.
  */
  const { onContextMenu, menu } = useProductRowMenu(product)

  const cover = product.images?.[0] ?? null
  const stock = stockSummary(product.inventory)

  /*
    "Sold out" means every size is gone, and it says nothing at all about a
    product with no size rows yet — that one cannot be sold either, but calling it
    sold out would send the seller looking for stock to replace rather than for
    sizes to add, and the chips underneath already say "No sizes yet".
  */
  const states = (product.inventory ?? []).map((row) => stockState(row?.stock))
  const soldOut = stock.sizes > 0 && stock.total <= 0
  const runningLow = !soldOut && states.includes('low')
  /*
    Published, and still not on the storefront: `isOnTheStorefront` includes
    the stock half of the rule, which is the half this list does not apply. Said
    as the switch AND the storefront's rule rather than one call, because an
    unpublished product is "Hidden" and a published one that customers cannot
    see is a different thing worth a different word.
  */
  const notVisible =
    Boolean(product.is_published) && !isOnTheStorefront(product)

  const onTogglePublished = (next) =>
    mutation.mutate({ productId: product.id, patch: { is_published: next } })

  return (
    <li
      onContextMenu={onContextMenu}
      className="group relative flex flex-col overflow-hidden rounded-card border border-hairline bg-raised shadow-card transition-[border-color,box-shadow] duration-300 ease-out-cubic hover:border-card-edge hover:shadow-card-lift"
    >
      <Link
        to={`/seller/products/${product.id}`}
        className="absolute inset-0 z-20 rounded-card"
        aria-label={`Edit ${product.name}`}
      />

      <div className="relative aspect-[4/3] overflow-hidden bg-subtle">
        {cover ? (
          <img
            src={cover}
            alt=""
            loading="lazy"
            decoding="async"
            className="h-full w-full object-cover transition-transform duration-500 ease-out-cubic group-hover:scale-[1.04]"
          />
        ) : (
          <span className="flex h-full items-center justify-center">
            <ImageOff
              className="h-7 w-7 text-muted/50"
              strokeWidth={1.5}
              aria-hidden="true"
            />
          </span>
        )}

        {!product.is_published && (
          <span className="pointer-events-none absolute left-3 top-3 rounded-full bg-chrome/85 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.06em] text-ink-inverse backdrop-blur-sm">
            Hidden
          </span>
        )}

        {/*
          The other half of "is this in the shop", and the one with no switch to
          flip: it is published and customers still cannot see it. Opposite
          corner from "Hidden" so the two never read as one badge, and the same
          chrome tone because they answer the same question.
        */}
        {notVisible && (
          <span
            title="Not visible to customers — nothing in stock, so the storefront hides it."
            className="pointer-events-none absolute right-3 top-3 rounded-full bg-chrome/85 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.06em] text-ink-inverse backdrop-blur-sm"
          >
            Not visible
          </span>
        )}

        {soldOut && (
          <div className="pointer-events-none absolute inset-0 flex items-center justify-center bg-page/70">
            <span className="rounded-full border border-hairline bg-raised px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.08em] text-crimson">
              Sold out
            </span>
          </div>
        )}

        {runningLow && (
          <span className="pointer-events-none absolute bottom-3 left-3 rounded-full bg-raised/95 px-2.5 py-1 text-[11px] font-semibold text-amber ring-1 ring-hairline backdrop-blur-sm">
            Running low
          </span>
        )}
      </div>

      <div className="flex flex-1 flex-col gap-3 p-4">
        <div className="min-w-0">
          {product.category && <p className="overline">{product.category}</p>}

          <h3 className="mt-1 line-clamp-2 font-medium leading-snug text-ink">
            {product.name}
          </h3>

          <p className="num mt-1.5 text-sm font-semibold text-ink">
            {formatCurrency(product.price)}
          </p>

          {product.sku && (
            <p className="num mt-0.5 truncate text-xs text-muted" title={product.sku}>
              {product.sku}
            </p>
          )}
        </div>

        <div className="mt-auto">
          <SizeStockChips inventory={product.inventory} size="sm" limit={8} />
          {/* Only beside chips. A product with no size rows already gets the
              sentence above, and "No sizes" under it is the same news twice. */}
          {stock.sizes > 0 && (
            <p className="mt-2 text-xs text-muted">{stock.label}</p>
          )}
        </div>

        <div className="relative z-30 flex items-center justify-between gap-3 border-t border-hairline-soft pt-3">
          <Switch
            size="sm"
            checked={Boolean(product.is_published)}
            disabled={mutation.isPending}
            onChange={onTogglePublished}
            label="On the storefront"
          />

          <span className="inline-flex shrink-0 items-center gap-2">
            <button
              type="button"
              onClick={() => setStockOpen((open) => !open)}
              aria-expanded={stockOpen}
              /* Only while the panel exists — see `ProductListRow`. */
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

            <span
              aria-hidden="true"
              className="pointer-events-none inline-flex items-center gap-1.5 text-xs font-semibold text-clay-ink"
            >
              <Pencil className="h-3.5 w-3.5" />
              Edit
            </span>
          </span>
        </div>

        {/* In the tile's own flow, so the card grows downwards and the grid
            pushes its neighbours rather than covering them. */}
        {stockOpen && (
          <div id={`stock-${product.id}`} className="relative z-30">
            <QuickStockPanel
              product={product}
              storeId={storeId}
              onDone={() => setStockOpen(false)}
            />
          </div>
        )}
      </div>
      {menu}
    </li>
  )
}
