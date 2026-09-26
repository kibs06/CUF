import { useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import {
  AlertTriangle,
  ArrowRight,
  Banknote,
  Loader2,
  Lock,
  ShoppingBag,
  Smartphone,
} from 'lucide-react'

import AddressSection from '../components/checkout/AddressSection'
import OrderSummaryCard from '../components/checkout/OrderSummaryCard'
import EmptyState from '../components/ui/EmptyState'
import { useAuth } from '../hooks/useAuth.jsx'
import { useCart } from '../hooks/useCart.jsx'
import { useStore } from '../hooks/useCatalog.js'
import {
  useAddresses,
  useCancelPaymentIntent,
  useGcashFee,
  useCreatePaymentIntent,
  usePendingIntent,
  usePlaceCashOrder,
  useSaveAddress,
} from '../hooks/useCheckout.js'
import { unavailableReason } from '../lib/cart.js'
import {
  DEFAULT_PAYMENT_METHOD,
  PAYMENT_METHODS,
  addressErrors,
  addressFromRow,
  addressInsert,
  chargedTotal,
  checkoutError,
  checkoutGroups,
  checkoutItems,
  emptyAddressDraft,
  feeLabel,
  fetchPendingIntent,
  formatDeliveryAddress,
  isOnlinePayment,
  quotedTotal,
  reconcileServerTotal,
  shippingSnapshot,
  shortOrderId,
  summaryLines,
} from '../lib/checkout.js'
import { formatCurrency } from '../lib/constants'

/**
 * Checkout.
 *
 * ## One maker at a time, because the flow is shaped that way
 *
 * An order belongs to one store, and so does the PayMongo session charged for
 * it. A cart mixing makers cannot become one payment, so it is split here, the
 * customer picks who they are buying from, and the rest of the cart stays
 * exactly where it is.
 *
 * ## GCash through PayMongo, which is the live path
 *
 * `create-gcash-payment-intent` creates the order in `awaiting_payment` and a
 * hosted checkout session, and returns the URL the customer pays on. Stock is
 * deliberately NOT reserved yet — the webhook inserts the order's lines and
 * decrements inventory only once PayMongo confirms the money moved — which is
 * also why the cart keeps its lines until the payment resolves.
 *
 * The hosted page is opened in a NEW TAB and this tab goes to the waiting page.
 * That is not a quirk: PayMongo redirects back to the app's own deep link
 * (`PAYMONGO_SUCCESS_URL`, a `solvision://` URL), which a browser cannot follow,
 * so the customer would be stranded by a same-tab redirect. With two tabs, the
 * waiting page polls `get-payment-status` and knows the answer regardless of
 * where the other tab goes.
 *
 * ## The amount is the server's, and we check it
 *
 * The customer is shown a total the storefront computed from its own sale-aware
 * rules — the same number the cart showed — plus the GCash fee it read from the
 * server. The intent returns the amount it will actually charge. If those
 * disagree, this page stops before sending anyone to a payment page and shows
 * both figures: an overcharge the customer cannot see is the one failure a
 * checkout must never ship with.
 */
export default function Checkout() {
  const navigate = useNavigate()
  const { user } = useAuth()
  /*
    Only the SELECTED lines, not the whole cart. The selection is made in the
    cart (`useCart`'s `selectedItems`), which is the app's order of operations:
    choose what you are buying, then pay for it. Reading `items` here would put
    the choice back on this screen, where the customer has already been shown a
    total.
  */
  const {
    items,
    selectedItems,
    selectedUnitCount,
    isLoading: cartLoading,
    removeLines,
  } = useCart()

  const addressesQuery = useAddresses()
  const saveAddress = useSaveAddress()
  const createIntent = useCreatePaymentIntent()
  const placeCash = usePlaceCashOrder()
  const pendingQuery = usePendingIntent()
  const cancelIntent = useCancelPaymentIntent()

  /*
    The payment method, defaulting to the app's own initial value (`GCash`). It
    lives in state rather than in the URL because the address does too: this is
    a form. The two methods are not a label on one flow — GCash creates a
    PayMongo intent and reserves nothing until it is paid, while Cash on Pickup
    places the order now and reserves the pair — so the choice decides which
    code path runs, not how one is worded.
  */
  const [method, setMethod] = useState(DEFAULT_PAYMENT_METHOD)
  const [selectedStoreId, setSelectedStoreId] = useState(null)
  const [selectedAddressId, setSelectedAddressId] = useState(null)
  const [addingAddress, setAddingAddress] = useState(false)
  const [draft, setDraft] = useState(() => emptyAddressDraft())
  const [saveToBook, setSaveToBook] = useState(true)
  const [showErrors, setShowErrors] = useState(false)
  const [problem, setProblem] = useState(null)
  const [mismatch, setMismatch] = useState(null)
  const [cancelling, setCancelling] = useState(false)

  // One idempotency key per checkout attempt: a double-tap or a retry after a
  // failure returns the SAME PayMongo session instead of creating a second
  // charge. Cleared once an attempt succeeds.
  const idempotencyKey = useRef(null)

  const groups = checkoutGroups(selectedItems)
  const rows = (addressesQuery.data ?? []).map(addressFromRow).filter(Boolean)
  const chosenRow =
    rows.find((row) => row.id === selectedAddressId) ?? rows[0] ?? null

  // The picked maker, or the only one there is. Derived rather than stored in
  // state so a cart change can never leave this pointing at a maker that is no
  // longer in the cart.
  const activeGroup =
    groups.find((group) => group.storeId === selectedStoreId) ?? groups[0] ?? null
  const lines = activeGroup?.items ?? []
  const cardLines = summaryLines(lines)
  const totals = quotedTotal(lines)

  /*
    The GCash surcharge is fetched only when GCash is the chosen method. It is a
    request per order total, and asking for a fee that will never be charged —
    cash orders have none — would be the checkout paying for a number it has
    decided not to use.
  */
  const online = isOnlinePayment(method)
  const feeQuery = useGcashFee(online ? totals.total : 0)
  const fee = online ? (feeQuery.data ?? null) : null
  const charged = chargedTotal({
    orderTotal: totals.total,
    feeAmount: fee?.feeAmount ?? 0,
  })

  /*
    Where the customer collects a cash order from — the store's own `location`,
    read only once cash is selected (the hook is keyed on the id and disabled
    without one). The app hardcodes its studio name; this says the maker's
    place instead, which is the same fact from the row that owns it.
  */
  const storeQuery = useStore(online ? null : activeGroup?.storeId)

  const blocked = lines.filter((line) => unavailableReason(line))
  const formOpen = addingAddress || rows.length === 0
  const addressDraft = formOpen ? draft : chosenRow
  const errors = showErrors && addressDraft ? addressErrors(addressDraft) : {}

  const submitting =
    createIntent.isPending ||
    placeCash.isPending ||
    saveAddress.isPending ||
    (online && feeQuery.isLoading)

  /**
   * Cash on Pickup — placed now, paid at the studio.
   *
   * No tab, no PayMongo, no polling: the order is a real order the moment the
   * insert lands, and the customer goes straight to it. The lines are removed
   * from the cart **after** the order exists, which is the one ordering that
   * cannot leave a customer looking at pairs they have already bought — or
   * having paid for pairs the cart quietly dropped.
   */
  async function onSubmitCash() {
    try {
      if (saveToBook && formOpen && user?.id) {
        try {
          await saveAddress.mutateAsync(addressInsert(user.id, addressDraft))
        } catch {
          // Saving a convenience, never a precondition.
        }
      }

      const order = await placeCash.mutateAsync({
        userId: user.id,
        storeId: activeGroup.storeId,
        lines,
        deliveryAddress: formatDeliveryAddress(addressDraft),
        shippingAddress: shippingSnapshot(addressDraft),
      })

      await removeLines(lines.map((line) => ({ id: line.id })))

      navigate(`/orders/${order.id}`, {
        replace: true,
        state: { placed: 'cash', total: order.totalAmount },
      })
    } catch (error) {
      setProblem({
        message:
          error?.message ??
          'We could not place that order. Please try again.',
        to: error?.soldOut ? '/cart' : undefined,
        soldOut: Boolean(error?.soldOut),
      })
    }
  }

  async function onSubmit(event) {
    event.preventDefault()
    setProblem(null)

    if (!activeGroup) return
    if (blocked.length > 0) {
      setProblem({
        message:
          'Some items in this order are no longer available. Update your cart and try again.',
        to: '/cart',
      })
      return
    }

    const errorsFound = addressErrors(addressDraft)
    if (Object.keys(errorsFound).length > 0) {
      setShowErrors(true)
      setProblem({ message: 'Check the address fields marked below.' })
      return
    }

    if (!online) {
      await onSubmitCash()
      return
    }

    // Opened synchronously, in the click handler, before any await — a window
    // opened after an async gap is a popup the browser blocks. The cash path
    // never reaches this line, which is why it is after the branch above.
    const tab = window.open('', '_blank')

    try {
      if (saveToBook && formOpen && user?.id) {
        try {
          await saveAddress.mutateAsync(addressInsert(user.id, addressDraft))
        } catch {
          // Saving a convenience, never a precondition: the order still goes
          // through with the snapshot the server stores.
        }
      }

      const result = await createIntent.mutateAsync({
        idempotencyKey: (idempotencyKey.current ??= crypto.randomUUID()),
        items: checkoutItems(lines),
        deliveryAddress: formatDeliveryAddress(addressDraft),
        shippingAddress: shippingSnapshot(addressDraft),
      })

      // Two comparisons, because the charged amount is the order total plus a
      // fee read from a different place. `amount - fee_amount` is the order's
      // own total as the server computed it, which is what our quote covers —
      // so this check works even when the fee read failed.
      const orderVerdict = reconcileServerTotal({
        quoted: totals.total,
        server: result.amount - result.feeAmount,
      })
      const chargeVerdict = fee
        ? reconcileServerTotal({ quoted: charged, server: result.amount })
        : null

      if (!orderVerdict.matches || (chargeVerdict && !chargeVerdict.matches)) {
        tab?.close()
        setMismatch({
          ...(orderVerdict.matches ? chargeVerdict : orderVerdict),
          orderId: result.orderId,
        })
        return
      }

      idempotencyKey.current = null
      if (result.checkoutUrl && tab) {
        tab.location.href = result.checkoutUrl
      } else if (result.checkoutUrl) {
        window.open(result.checkoutUrl, '_blank', 'noopener')
      } else {
        tab?.close()
      }

      navigate(`/checkout/pay/${result.orderId}`, {
        replace: true,
        state: { checkout: result, lines: cardLines },
      })
    } catch (error) {
      tab?.close()
      const mapped = checkoutError(
        error,
        'We could not start the GCash payment. Please check your connection and try again.',
      )

      if (mapped.openOrder && user?.id) {
        // A payment is already pending, so a second one cannot be created.
        // Send the customer to the order they already have.
        try {
          const pending = await fetchPendingIntent(user.id)
          if (pending?.orderId) {
            navigate(`/checkout/pay/${pending.orderId}`, {
              replace: true,
              state: { resumed: true },
            })
            return
          }
        } catch {
          // Fall through to the message below rather than hiding the failure.
        }
      }

      setProblem({ message: mapped.message })
    }
  }

  async function onCancelMismatch() {
    if (!mismatch?.orderId) return
    setCancelling(true)
    try {
      await cancelIntent.mutateAsync(mismatch.orderId)
      setMismatch(null)
      idempotencyKey.current = null
      setProblem({
        message:
          'That checkout was cancelled and nothing was charged. Your cart is untouched.',
      })
    } catch (error) {
      setProblem({
        message: checkoutError(error, 'We could not cancel that checkout.').message,
      })
    } finally {
      setCancelling(false)
    }
  }

  /*
    ── Nothing to check out ────────────────────────────────────────────────

    Two different situations, and they deserve different words: an empty cart,
    and a cart full of pairs the customer has not ticked yet. Collapsing them
    into "Your cart is empty" would be a lie on the second — and a customer
    arriving here by URL, with a full cart and nothing selected, is exactly who
    this screen now has to explain itself to.
  */
  if (!cartLoading && selectedUnitCount === 0) {
    const cartEmpty = items.length === 0

    return (
      <div className="mx-auto max-w-3xl px-4 py-16 sm:px-6 lg:px-8">
        <EmptyState
          Icon={ShoppingBag}
          title={cartEmpty ? 'Your cart is empty' : 'Nothing selected yet'}
          description={
            cartEmpty
              ? 'Add a pair from the catalog and it will be waiting here — and in the CUFMAI app, because it is the same cart.'
              : 'Checkout pays for the pairs you tick in your cart. Pick the ones you want and come back — nothing is charged until then.'
          }
          action={
            <Link to={cartEmpty ? '/shop' : '/cart'} className="btn btn-primary">
              {cartEmpty ? 'Browse the catalog' : 'Back to your cart'}
              <ArrowRight size={16} strokeWidth={2.5} />
            </Link>
          }
        />
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6 lg:px-8">
      <header>
        <p className="overline">Checkout</p>
        <h1 className="mt-2 font-display text-3xl font-semibold text-ink sm:text-4xl">
          How would you like to pay?
        </h1>
        <p className="mt-2 max-w-2xl text-sm leading-relaxed text-muted">
          GCash through PayMongo, or cash when you collect the pair — the same
          two the CUFMAI app offers. The maker is paid directly either way, and
          CUFMAI never handles the money.
        </p>
      </header>

      {pendingQuery.data?.orderId && (
        <div className="mt-6 flex flex-wrap items-center justify-between gap-4 rounded-card border border-amber/40 bg-amber/[0.08] px-5 py-4">
          <p className="text-sm text-ink">
            A GCash payment for order #{shortOrderId(pendingQuery.data.orderId)}{' '}
            is still open.
          </p>
          <Link
            to={`/checkout/pay/${pendingQuery.data.orderId}`}
            className="btn btn-outline h-9 px-4 py-0 text-xs"
          >
            Open that payment
          </Link>
        </div>
      )}

      {mismatch && (
        <section className="mt-6 rounded-card border border-crimson/30 bg-crimson/[0.06] p-5">
          <div className="flex items-start gap-3">
            <AlertTriangle size={18} className="mt-0.5 shrink-0 text-crimson" />
            <div>
              <p className="font-semibold text-ink">
                We stopped before payment — the amounts do not match
              </p>
              <p className="mt-2 text-sm leading-relaxed text-muted-strong">
                Your cart came to{' '}
                <span className="num font-semibold text-ink">
                  {formatCurrency(mismatch.quoted)}
                </span>{' '}
                and the checkout for order{' '}
                <span className="num">#{shortOrderId(mismatch.orderId)}</span>{' '}
                came to{' '}
                <span className="num font-semibold text-ink">
                  {formatCurrency(mismatch.server)}
                </span>
                . Nothing has been charged, and we will not send you to a payment
                page for more than you were quoted.
              </p>
              <p className="mt-2 text-xs leading-relaxed text-muted">
                Cancel it below and your cart is exactly as you left it, or
                message the maker and they will settle it with you.
              </p>
              <button
                type="button"
                onClick={onCancelMismatch}
                disabled={cancelling}
                className="btn btn-primary mt-4"
              >
                {cancelling && <Loader2 size={15} className="animate-spin" />}
                {cancelling ? 'Cancelling…' : 'Cancel this checkout'}
              </button>
            </div>
          </div>
        </section>
      )}

      {problem && (
        <div
          role="status"
          className="mt-6 rounded-card border border-clay/30 bg-clay/[0.06] px-5 py-4 text-sm text-ink"
        >
          {problem.message}
          {problem.to && (
            <>
              {' '}
              <Link
                to={problem.to}
                className="font-semibold text-clay-ink underline underline-offset-4"
              >
                Go to your cart
              </Link>
            </>
          )}
        </div>
      )}

      <form onSubmit={onSubmit} className="mt-8 grid gap-6 lg:grid-cols-[1fr_22rem]">
        <div className="space-y-6">
          {groups.length > 1 && (
            <section className="rounded-card border border-hairline bg-raised p-6 shadow-card">
              <h2 className="font-display text-xl font-semibold text-ink">
                Who are you buying from?
              </h2>
              <p className="mt-1 text-sm leading-relaxed text-muted">
                Your cart has pairs from {groups.length} makers. An order — and
                the payment for it — belongs to one maker, so pay for them one
                at a time. The rest of your cart stays put until then.
              </p>

              <ul className="mt-5 space-y-3">
                {groups.map((group) => {
                  const selected = group.storeId === activeGroup?.storeId
                  return (
                    <li key={group.storeId ?? 'unknown'}>
                      <button
                        type="button"
                        onClick={() => setSelectedStoreId(group.storeId)}
                        aria-pressed={selected}
                        className={`flex w-full items-center justify-between gap-4 rounded-field border p-4 text-left transition-[border-color,background-color,box-shadow] duration-200 ease-out-cubic ${
                          selected
                            ? 'border-clay/45 bg-clay/[0.05] shadow-warm'
                            : 'border-hairline hover:border-card-edge hover:bg-subtle/60'
                        }`}
                      >
                        <span>
                          <span className="block text-sm font-semibold text-ink">
                            {group.storeName}
                          </span>
                          <span className="mt-0.5 block text-xs text-muted">
                            {group.items.length}{' '}
                            {group.items.length === 1 ? 'pair' : 'pairs'} ·{' '}
                            {formatCurrency(group.subtotal)}
                          </span>
                        </span>
                        <span className="text-xs font-semibold uppercase tracking-[0.08em] text-clay-ink">
                          {selected ? 'Paying this one' : 'Choose'}
                        </span>
                      </button>
                    </li>
                  )
                })}
              </ul>
            </section>
          )}

          <AddressSection
            addresses={addressesQuery.data}
            selectedId={chosenRow?.id ?? null}
            onSelect={(id) => {
              setSelectedAddressId(id)
              setAddingAddress(false)
            }}
            adding={addingAddress}
            onAddStart={() => setAddingAddress(true)}
            onCancelAdd={() => {
              setAddingAddress(false)
              setShowErrors(false)
            }}
            formProps={{
              draft,
              errors,
              onChange: setDraft,
              saveToBook,
              onSaveToBookChange: setSaveToBook,
            }}
          />

          {/*
            ── Payment method ────────────────────────────────────────────

            Two options, drawn as two cards rather than a select: the choice
            changes what happens to the order (one reserves the pair now, the
            other reserves nothing until the money moves), so both consequences
            have to be readable before the choice is made, not after.
          */}
          <section className="rounded-card border border-hairline bg-raised p-6 shadow-card">
            <h2 className="font-display text-xl font-semibold text-ink">
              Payment
            </h2>

            <fieldset className="mt-4">
              <legend className="sr-only">How would you like to pay?</legend>
              <div className="space-y-3">
                {PAYMENT_METHODS.map((option) => {
                  const selected = method === option.value
                  const Icon = option.value === 'cash' ? Banknote : Smartphone

                  return (
                    <label
                      key={option.value}
                      className={`flex cursor-pointer items-start gap-3 rounded-field border p-4 transition-[border-color,background-color,box-shadow] duration-200 ease-out-cubic ${
                        selected
                          ? 'border-clay/45 bg-clay/[0.05] shadow-warm'
                          : 'border-hairline hover:border-card-edge hover:bg-subtle/60'
                      }`}
                    >
                      <input
                        type="radio"
                        name="payment-method"
                        value={option.value}
                        checked={selected}
                        onChange={() => {
                          setMethod(option.value)
                          setProblem(null)
                        }}
                        className="mt-1 h-4 w-4 shrink-0 accent-clay"
                      />

                      <span className="min-w-0 flex-1">
                        <span className="flex items-center gap-2 text-sm font-semibold text-ink">
                          <Icon size={15} strokeWidth={2} className="shrink-0 text-clay-ink" />
                          {option.label}
                        </span>
                        <span className="mt-1 block text-sm leading-relaxed text-muted-strong">
                          {option.hint}
                        </span>

                        {/*
                          The consequence of the choice, in the customer's
                          terms. Both say what happens to the order, because
                          "paid now" and "paid at the studio" are not the same
                          promise and the rest of this page behaves differently
                          depending on which one is ticked.
                        */}
                        {option.value === 'gcash' && selected && (
                          <span className="mt-2 block text-xs leading-relaxed text-muted">
                            A PayMongo page opens in a new tab and hands you to
                            GCash. Keep this tab open — it watches for the
                            confirmation and tells you the moment the order is
                            paid.
                          </span>
                        )}
                        {option.value === 'cash' && selected && (
                          <span className="mt-2 block text-xs leading-relaxed text-muted">
                            Pay {activeGroup?.storeName ?? 'the maker'} in cash
                            when you collect it
                            {storeQuery.data?.location
                              ? ` in ${storeQuery.data.location}`
                              : ''}
                            . Your order is placed now and the maker starts on
                            it — nothing is charged online.
                          </span>
                        )}
                      </span>
                    </label>
                  )
                })}
              </div>
            </fieldset>

            <p className="mt-4 flex items-start gap-2 text-xs leading-relaxed text-muted">
              <Lock size={13} strokeWidth={2} className="mt-0.5 shrink-0" />
              {online
                ? 'CUFMAI never handles the money and never sees your GCash account. The order is only marked paid when PayMongo confirms the payment server-side.'
                : 'Cash is handed to the maker when you collect the pair. No payment page opens, and nothing is charged to you here.'}
            </p>
          </section>
        </div>

        {/* ── Summary ────────────────────────────────────────────────────── */}
        <aside className="lg:sticky lg:top-24 lg:self-start">
          <OrderSummaryCard
            lines={cardLines}
            subtotal={totals.subtotal}
            deliveryFee={totals.deliveryFee}
            feeAmount={fee ? fee.feeAmount : null}
            feeLabel={fee ? feeLabel(fee) : 'GCash fee'}
            total={charged}
            totalLabel={online ? 'You pay' : 'Pay at pickup'}
            note={
              online
                ? fee
                  ? groups.length > 1
                    ? `Includes the GCash fee. This payment covers ${
                        activeGroup?.storeName ?? 'one maker'
                      } only — ${groups.length - 1} more stay in your cart.`
                    : 'Includes the GCash fee and the fixed ₱100 delivery fee.'
                  : 'The GCash fee is added at payment and shown on the PayMongo page before you pay.'
                : 'No GCash fee on a cash order — you pay the maker in person, and the ₱100 delivery fee is already in this total.'
            }
          />

          <button
            type="submit"
            disabled={submitting || blocked.length > 0 || mismatch !== null}
            className="btn btn-primary mt-5 w-full"
          >
            {(submitting || createIntent.isPending) && (
              <Loader2 size={16} className="animate-spin" />
            )}
            {submitting
              ? 'Starting…'
              : online
                ? `Pay ${formatCurrency(charged)} with GCash`
                : `Place order · ${formatCurrency(charged)} at pickup`}
          </button>

          <p className="mt-3 text-center text-xs leading-relaxed text-muted">
            {online
              ? 'Opens PayMongo in a new tab. Nothing is reserved or charged until you finish there.'
              : 'Placed immediately, and the pair is set aside. Pay the maker when you collect it.'}
          </p>

          <Link
            to="/cart"
            className="mt-4 block text-center text-xs font-semibold text-clay-ink underline-offset-4 hover:underline"
          >
            Back to cart
          </Link>
        </aside>
      </form>
    </div>
  )
}
