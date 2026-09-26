import { Link } from 'react-router-dom'
import { motion } from 'motion/react'
import { Check, Minus, Plus, ShoppingBag, Trash2 } from 'lucide-react'

import EmptyState from '../components/ui/EmptyState'
import Reveal from '../components/ui/Reveal'
import { fadeUp, staggerChildren } from '../components/motion/transitions'
import { useCart } from '../hooks/useCart.jsx'
import { formatCurrency } from '../lib/constants'
import { cartItemKey, lineTotal, unavailableReason } from '../lib/cart'

/**
 * The cart — a checklist, exactly like the app's.
 *
 * ## The order of operations is the feature
 *
 * The app asks "which of these are you buying?" **in the cart**, with a tick per
 * line, a tri-state tick per store and a master tick, and only then a Checkout
 * button whose totals are the *selected* lines (`CartProvider.selectedKeys` and
 * friends). The portal had it the other way round: its cart totalled everything
 * and its checkout asked which maker to pay — the same question, asked one
 * screen later, with the whole cart already in the total. This page is that
 * port: the summary, the delivery fee and the button all read the selection.
 *
 * ## Grouped by store
 *
 * A CUFMAI order is not one shipment from one warehouse — it is several
 * artisans' work, each arranging their own delivery — so the cart is grouped
 * and each group has its own checkbox. A flat list would hide that until
 * checkout, which is the worst moment to discover it.
 *
 * Every line shows its own availability. The rule is the app's
 * (`unavailableReason`): unpublished, no stock, or fewer left than the customer
 * is asking for — the last of which a simple "in stock" badge would miss.
 */
export default function Cart() {
  const {
    groups,
    count,
    isLoading,
    error,
    clearError,
    setQuantity,
    removeLine,
    pendingIds,
    selectedKeys,
    selectedUnitCount,
    selectedSubtotal,
    selectedDeliveryFee,
    selectedTotal,
    allSelected,
    storeSelection,
    toggleItem,
    toggleStore,
    toggleAll,
  } = useCart()

  const hasSelection = selectedUnitCount > 0

  if (isLoading) {
    return (
      <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6 lg:px-8">
        <div className="shimmer h-8 w-40 rounded-lg" />
        <div className="mt-8 space-y-4">
          {Array.from({ length: 3 }).map((_, index) => (
            <div key={index} className="shimmer h-28 rounded-card" />
          ))}
        </div>
      </div>
    )
  }

  if (count === 0) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-16 sm:px-6">
        <EmptyState
          Icon={ShoppingBag}
          title="Your cart is empty"
          description="Anything you add here also appears in the CUFMAI app — it is the same cart."
          action={
            <Link to="/shop" className="btn btn-primary">
              Browse the catalog
            </Link>
          }
        />
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 lg:px-8">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="overline">Your cart</p>
          <h1 className="mt-2 font-display text-3xl font-semibold text-ink sm:text-4xl">
            {count} {count === 1 ? 'pair' : 'pairs'}
          </h1>
        </div>

        {/*
          The master checkbox, the app's `allSelected` / `toggleAll`. It is here
          rather than in the summary because it selects lines, and the lines are
          the left-hand column — a control that acts on everything should sit
          with the everything it acts on.
        */}
        <button
          type="button"
          onClick={toggleAll}
          aria-pressed={allSelected}
          className="inline-flex items-center gap-2 text-xs font-semibold text-muted-strong transition-colors duration-200 hover:text-ink"
        >
          <Tick state={allSelected ? 'all' : selectedKeys.size > 0 ? 'some' : 'none'} />
          {allSelected ? 'Deselect all' : 'Select all'}
        </button>
      </header>

      {error && (
        <div
          role="alert"
          className="mt-6 flex items-start justify-between gap-4 rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm text-ink"
        >
          <span>{error}</span>
          <button
            type="button"
            onClick={clearError}
            className="shrink-0 text-xs font-semibold text-crimson underline-offset-4 hover:underline"
          >
            Dismiss
          </button>
        </div>
      )}

      <div className="mt-8 grid gap-8 lg:grid-cols-[1fr_20rem] lg:gap-10">
        <div className="space-y-8">
          {groups.map((group) => (
            <Reveal key={group.storeId ?? 'unknown'}>
              <section>
                <div className="flex items-baseline justify-between gap-4">
                  {/*
                    The store's own tri-state checkbox: fully, partly or not at
                    all selected — and a partly selected store is *completed* by
                    a click, not cleared, which is `CartProvider.toggleStore`.
                  */}
                  <button
                    type="button"
                    onClick={() => toggleStore(group.storeId)}
                    className="group/head flex min-w-0 items-center gap-2.5 text-left"
                  >
                    <Tick
                      state={storeSelection(group.storeId)}
                      label={`${group.storeName} — ${storeSelection(group.storeId) === 'all' ? 'deselect' : 'select'} all`}
                    />
                    <h2 className="truncate font-display text-lg font-semibold text-ink">
                      {group.storeName}
                    </h2>
                  </button>
                  <Link
                    to={`/makers/${group.storeId}`}
                    className="shrink-0 text-xs font-semibold text-clay-ink underline-offset-4 hover:underline"
                  >
                    Visit workshop
                  </Link>
                </div>

                <motion.ul
                  variants={staggerChildren(0.04)}
                  initial="hidden"
                  animate="show"
                  className="mt-4 space-y-3"
                >
                  {group.items.map((item) => {
                    const problem = unavailableReason(item)
                    const pending = pendingIds.has(item.id)
                    const selected = selectedKeys.has(cartItemKey(item))

                    return (
                      <motion.li
                        key={item.id}
                        variants={fadeUp}
                        className={`flex gap-4 rounded-card border bg-raised p-4 shadow-card transition-opacity duration-200 ${
                          problem ? 'border-crimson/25' : 'border-hairline'
                        } ${pending ? 'opacity-60' : 'opacity-100'} ${
                          selected ? 'ring-1 ring-clay/25' : ''
                        }`}
                      >
                        {/* The line's own tick, which is what makes the summary add up. */}
                        <button
                          type="button"
                          onClick={() => toggleItem(item)}
                          aria-pressed={selected}
                          className="mt-0.5 shrink-0"
                        >
                          <Tick
                            state={selected ? 'all' : 'none'}
                            label={`${selected ? 'Deselect' : 'Select'} ${item.productName}`}
                          />
                        </button>

                        <Link
                          to={`/product/${item.productId}`}
                          className="shrink-0 overflow-hidden rounded-field border border-hairline bg-subtle"
                        >
                          {item.imageUrl ? (
                            <img
                              src={item.imageUrl}
                              alt=""
                              loading="lazy"
                              className="h-20 w-20 object-cover transition-transform duration-500 ease-out-cubic hover:scale-105"
                            />
                          ) : (
                            <div className="h-20 w-20" />
                          )}
                        </Link>

                        <div className="min-w-0 flex-1">
                          <Link
                            to={`/product/${item.productId}`}
                            className="line-clamp-2 text-sm font-semibold text-ink hover:text-clay-ink"
                          >
                            {item.productName}
                          </Link>

                          <p className="mt-1 text-xs text-muted">
                            {item.size && (
                              <>
                                Size <span className="num">{item.size}</span>
                              </>
                            )}
                            {item.size && item.color && ' · '}
                            {item.color}
                          </p>

                          {problem && (
                            <p className="mt-1.5 text-xs font-semibold text-crimson">
                              {problem}
                            </p>
                          )}

                          <div className="mt-3 flex flex-wrap items-center gap-4">
                            <Stepper
                              quantity={item.quantity}
                              max={item.stock}
                              disabled={pending}
                              onChange={(next) => setQuantity(item, next)}
                            />

                            <span className="num text-sm font-semibold text-ink">
                              {formatCurrency(lineTotal(item))}
                            </span>

                            <span className="num text-xs text-muted">
                              {formatCurrency(item.unitPrice)} each
                            </span>

                            <button
                              type="button"
                              onClick={() => removeLine(item)}
                              disabled={pending}
                              className="ml-auto inline-flex items-center gap-1.5 text-xs font-semibold text-muted transition-colors duration-200 hover:text-crimson"
                            >
                              <Trash2 size={14} strokeWidth={2} />
                              Remove
                            </button>
                          </div>
                        </div>
                      </motion.li>
                    )
                  })}
                </motion.ul>
              </section>
            </Reveal>
          ))}
        </div>

        {/* ── Summary ─────────────────────────────────────────────── */}
        <aside className="lg:sticky lg:top-24 lg:self-start">
          <div className="rounded-card border border-hairline bg-raised p-6 shadow-card">
            <h2 className="font-display text-lg font-semibold text-ink">
              Summary
            </h2>

            <p className="mt-2 text-xs text-muted">
              {hasSelection
                ? `${selectedUnitCount} of ${count} ${count === 1 ? 'pair' : 'pairs'} selected`
                : 'Nothing selected yet'}
            </p>

            <dl className="mt-5 space-y-3 text-sm">
              <div className="flex items-baseline justify-between">
                <dt className="text-muted">Subtotal</dt>
                <dd className="num font-semibold text-ink">
                  {formatCurrency(selectedSubtotal)}
                </dd>
              </div>
              <div className="flex items-baseline justify-between">
                <dt className="text-muted">Delivery fee</dt>
                <dd className="num text-muted">
                  {formatCurrency(selectedDeliveryFee)}
                </dd>
              </div>
            </dl>

            {/*
              Estimated, and labelled as such: the server sets the final total
              when the order is created. It is the SELECTED lines plus ONE fee,
              which is the app's `selectedTotal` — and what the payment actually
              takes, because checkout creates a single order.
            */}
            <div className="mt-5 flex items-baseline justify-between border-t border-hairline pt-5">
              <span className="text-sm font-semibold text-ink">
                Estimated total
              </span>
              <span className="num text-xl font-semibold text-ink">
                {formatCurrency(selectedTotal)}
              </span>
            </div>

            {/*
              A link, not a button, while it can go nowhere: a disabled-looking
              link still reads as "there is more to see". With nothing selected
              it renders as a plain disabled button instead.
            */}
            {hasSelection ? (
              <Link to="/checkout" className="btn btn-primary mt-6 w-full">
                Checkout {selectedUnitCount}{' '}
                {selectedUnitCount === 1 ? 'pair' : 'pairs'}
              </Link>
            ) : (
              <button type="button" disabled className="btn btn-primary mt-6 w-full cursor-not-allowed opacity-50">
                Choose what to check out
              </button>
            )}
            <p className="mt-3 text-center text-xs leading-relaxed text-muted">
              Delivery is added at checkout. Pay by GCash — the maker is paid
              directly.
            </p>

            <Link
              to="/shop"
              className="mt-4 block text-center text-xs font-semibold text-clay-ink underline-offset-4 hover:underline"
            >
              Keep shopping
            </Link>
          </div>
        </aside>
      </div>
    </div>
  )
}

/**
 * The tick.
 *
 * A plain SVG-in-a-button rather than a real `<input type="checkbox">`, and it
 * is drawn in the three states a group can be in: empty, ticked, and the
 * indeterminate dash that means "some of these". The label is passed in by the
 * caller for screen readers, because the control has no text of its own.
 */
function Tick({ state, label }) {
  const filled = state === 'all' || state === 'some'

  return (
    <span
      className={`inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-[6px] border transition-colors duration-200 ease-out-cubic ${
        filled ? 'border-clay bg-clay text-ink-inverse' : 'border-card-edge text-transparent'
      }`}
    >
      {state === 'all' && <Check size={13} strokeWidth={3} aria-hidden="true" />}
      {state === 'some' && (
        <span aria-hidden="true" className="h-0.5 w-2.5 rounded-full bg-ink-inverse" />
      )}
      {label && <span className="sr-only">{label}</span>}
    </span>
  )
}

/**
 * The quantity stepper.
 *
 * The upper bound is the line's real stock: letting a customer ask for five of
 * something with three left is a promise the cart cannot keep, and finding that
 * out at checkout is worse than finding it out here.
 */
function Stepper({ quantity, max, disabled, onChange }) {
  const atMax = max > 0 && quantity >= max

  return (
    <div className="inline-flex items-center rounded-full border border-hairline">
      <button
        type="button"
        onClick={() => onChange(quantity - 1)}
        disabled={disabled}
        aria-label="Decrease quantity"
        className="inline-flex h-8 w-8 items-center justify-center rounded-full text-muted-strong transition-colors duration-200 hover:bg-subtle hover:text-ink"
      >
        <Minus size={14} strokeWidth={2.5} />
      </button>

      <span
        className="num w-8 text-center text-sm font-semibold text-ink"
        aria-live="polite"
      >
        {quantity}
      </span>

      <button
        type="button"
        onClick={() => onChange(quantity + 1)}
        disabled={disabled || atMax}
        aria-label="Increase quantity"
        title={atMax ? `Only ${max} available` : undefined}
        className={`inline-flex h-8 w-8 items-center justify-center rounded-full transition-colors duration-200 ${
          atMax
            ? 'cursor-not-allowed text-muted/40'
            : 'text-muted-strong hover:bg-subtle hover:text-ink'
        }`}
      >
        <Plus size={14} strokeWidth={2.5} />
      </button>
    </div>
  )
}
