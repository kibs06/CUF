import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Minus, Plus } from 'lucide-react'

import { formatSize, isStockDraftDirty, sizingSystemOf, stockDraftFrom, stockDraftTotals, stockState } from '../../lib/sizeSystems.js'
import { coloursFromVariants } from '../../lib/productVariants.js'
import { useSaveProductVariants } from '../../hooks/useSeller.js'

/**
 * Top up a product's stock without leaving the list.
 *
 * ## Why this is not the product form
 *
 * Restocking is the most frequent thing a seller does to a product and the least
 * like *editing* one: nothing about the pair changed, the workshop simply made
 * six more size 41s. The form costs a navigation, a full page of fields and a
 * save that writes the name, the price and the description back over themselves —
 * so a seller with eight products to top up after a delivery opens the form eight
 * times to type eight numbers.
 *
 * This is the same write (see `saveProductVariants`) with only the field that
 * changed: the whole size set, because the write replaces it, and nothing else.
 *
 * ## What it deliberately does not do
 *
 * **It cannot add or remove a size.** A stepper changes counts; deciding *which
 * sizes a product comes in* is a different job with a different error (a size
 * added here is instantly buyable, and a size removed here is a customer's
 * pending order that can no longer be filled) and it lives in `VariantEditor`,
 * where the seller is already looking at the whole product. This panel links
 * there for anything but a count.
 *
 * **It cannot touch a product with colours.** The panel is one count per size,
 * and a product with colours has one count per SIZE AND COLOUR — so there is no
 * answer to give it. It used to write one colourless row per size, which is the
 * same set replacement seen from the other side: the write is a delete and a
 * re-insert, so restocking a two-colour product from this panel would have
 * flattened it to one colour and zeroed the per-variant prices and SKUs. The
 * guard below is the fix, and it is the same shape as the no-sizes guard: say
 * why, and link to where the job belongs.
 *
 * ## Save is one write, and it is honest about it
 *
 * The steppers are local state and nothing is sent until Save, which is the
 * opposite of the tile's publish switch — and deliberately so. A count is a
 * number a seller types through (`3`, `4`, `5`), and three network writes for one
 * restock would be three chances to write `5` on top of `35`.
 *
 * The write is not optimistic: it is a set replacement, so pretending it landed
 * while the database still holds the old set would show the list and the
 * storefront disagreeing if the request failed.
 */
export default function QuickStockPanel({ product, storeId, onDone }) {
  const mutation = useSaveProductVariants(storeId)

  const [draft, setDraft] = useState(() => stockDraftFrom(product.inventory))
  const [error, setError] = useState(null)

  const dirty = isStockDraftDirty(draft, product.inventory)
  const totals = stockDraftTotals(draft)
  const busy = mutation.isPending

  const step = (size, delta) => {
    setDraft((rows) =>
      rows.map((row) =>
        row.size === size
          ? { ...row, stock: Math.max(0, row.stock + delta) }
          : row,
      ),
    )
  }

  const setCount = (size, raw) => {
    const stock = Math.max(0, Math.trunc(Number(raw) || 0))
    setDraft((rows) =>
      rows.map((row) => (row.size === size ? { ...row, stock } : row)),
    )
  }

  const onSave = async () => {
    setError(null)
    try {
      await mutation.mutateAsync({
        productId: product.id,
        /*
          The size draft is a variant list: one row per size with the colour the
          product already has, which is none (this panel never reaches a product
          that has colours — see the guard below).
        */
        variants: draft.map((row) => ({
          size: row.size,
          color: null,
          stock: row.stock,
        })),
      })
      onDone?.()
    } catch (failure) {
      setError(failure?.message ?? 'We could not save that stock.')
    }
  }

  const colours = coloursFromVariants(product.variants)

  /*
    A product with colours has no single answer to "how many EU 41 have I got",
    and this panel's write is a set replacement — so the honest move is to stop
    rather than to answer with one colour's count and delete the others. Before
    this guard existed, restocking a two-colour product from here flattened it to
    a single colour. See the doc comment above.
  */
  if (colours.length > 0) {
    return (
      <div className="rounded-field border border-hairline bg-subtle/40 p-4 text-sm text-muted">
        <p>
          This product comes in{' '}
          {colours.length === 1 ? 'a colour' : 'colours'} ({colours.join(', ')}),
          so its stock is a count per size <em>and</em> colour — and this panel
          only has one count per size. Restocking it here would leave the other
          colours holding the old numbers.
        </p>
        <Link
          to={`/seller/products/${product.id}`}
          className="mt-3 inline-block text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
        >
          Set stock per colour in the product form
        </Link>
      </div>
    )
  }

  /*
    No sizes is a dead end for a count editor, and it is a real state: the write
    would replace an empty set with an empty set and look like it worked. The
    honest answer is where to go instead.
  */
  if (draft.length === 0) {
    return (
      <div className="rounded-field border border-hairline bg-subtle/40 p-4 text-sm text-muted">
        <p>
          This product has no sizes yet, so there is no stock to top up. Add the
          sizes it comes in first — that is in the product form, because a size
          added here would be buyable the moment it landed.
        </p>
        <Link
          to={`/seller/products/${product.id}`}
          className="mt-3 inline-block text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
        >
          Open the product form
        </Link>
      </div>
    )
  }

  return (
    <div className="rounded-field border border-hairline bg-subtle/40 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
          Stock by size
        </p>
        <p className="num text-xs text-muted">
          {totals.sizes} {totals.sizes === 1 ? 'size' : 'sizes'} ·{' '}
          {totals.pairs} {totals.pairs === 1 ? 'pair' : 'pairs'}
        </p>
      </div>

      <ul className="mt-3 flex flex-wrap gap-2">
        {draft.map((row) => {
          const state = stockState(row.stock)
          const label = sizingSystemOf(row.size) === 'Other' ? row.size : formatSize(row.size)

          return (
            <li
              key={row.size}
              className={`flex items-center gap-1 rounded-field border bg-raised py-1 pl-2.5 pr-1 transition-colors duration-200 ease-out-cubic ${
                state === 'out'
                  ? 'border-crimson/30'
                  : state === 'low'
                    ? 'border-amber/35'
                    : 'border-hairline'
              }`}
            >
              <span className="num text-xs font-semibold text-ink">{label}</span>

              <button
                type="button"
                onClick={() => step(row.size, -1)}
                disabled={busy || row.stock === 0}
                aria-label={`One fewer ${label}`}
                className="inline-flex h-6 w-6 items-center justify-center rounded text-muted transition-colors duration-200 hover:text-ink disabled:opacity-40"
              >
                <Minus className="h-3.5 w-3.5" aria-hidden="true" />
              </button>

              <input
                type="number"
                min="0"
                step="1"
                inputMode="numeric"
                value={row.stock}
                disabled={busy}
                onChange={(event) => setCount(row.size, event.target.value)}
                aria-label={`Stock for ${label}`}
                className={`num h-7 w-12 rounded border-0 bg-transparent px-1 text-center text-sm font-semibold focus:ring-0 ${
                  state === 'out'
                    ? 'text-crimson'
                    : state === 'low'
                      ? 'text-amber'
                      : 'text-ink'
                }`}
              />

              <button
                type="button"
                onClick={() => step(row.size, 1)}
                disabled={busy}
                aria-label={`One more ${label}`}
                className="inline-flex h-6 w-6 items-center justify-center rounded text-muted transition-colors duration-200 hover:text-ink disabled:opacity-40"
              >
                <Plus className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
            </li>
          )
        })}
      </ul>

      {error && (
        <p
          role="alert"
          className="mt-3 rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs text-ink"
        >
          {error}
        </p>
      )}

      <div className="mt-4 flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={onSave}
          disabled={busy || !dirty}
          className="btn btn-primary h-9 px-4 py-0 text-xs"
        >
          {busy ? 'Saving…' : 'Save stock'}
        </button>

        <button
          type="button"
          onClick={() => onDone?.()}
          disabled={busy}
          className="btn btn-outline h-9 px-4 py-0 text-xs"
        >
          {dirty ? 'Discard' : 'Close'}
        </button>

        <Link
          to={`/seller/products/${product.id}`}
          className="ml-auto text-xs font-semibold text-clay-ink underline-offset-4 hover:underline"
        >
          Add or remove sizes
        </Link>
      </div>
    </div>
  )
}
