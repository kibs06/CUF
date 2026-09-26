import { useEffect, useRef, useState } from 'react'
import { Link, useLocation, useParams } from 'react-router-dom'
import {
  BadgeCheck,
  Check,
  Clock,
  ExternalLink,
  Loader2,
  RefreshCw,
  ShoppingBag,
  TimerOff,
  X,
} from 'lucide-react'

import OrderSummaryCard from '../components/checkout/OrderSummaryCard'
import { useCart } from '../hooks/useCart.jsx'
import {
  useCancelPaymentIntent,
  useOrder,
  usePaymentStatus,
} from '../hooks/useCheckout.js'
import {
  cartLinesToClear,
  checkoutError,
  summaryLines,
} from '../lib/checkout.js'
import {
  deadlineState,
  feeLabel,
  formatCountdown,
  paymentState,
  shortOrderId,
} from '../lib/checkoutRules.js'
import { formatCurrency } from '../lib/constants'

/**
 * Waiting on a GCash payment.
 *
 * This is one page for four states of the same payment, and the one that
 * matters most is the one nobody tests: a customer who pays, closes the tab,
 * and comes back later to a bookmark. `get-payment-status` is the only thing
 * that decides which state they see — never the redirect they landed on, which
 * may not have happened at all.
 *
 * It polls while the payment is open, and stops the moment the server has an
 * answer. The countdown is read from the server's `expires_at`, not started
 * here, so a resumed visit shows the true time left; and when the local clock
 * says the window has closed but the server has not swept the order yet, the
 * page says so and offers a re-check rather than declaring it dead.
 */
export default function GcashPay() {
  const { orderId } = useParams()
  const location = useLocation()
  const { items: cartItems, removeLines } = useCart()

  const state = location.state ?? {}
  const checkout = state.checkout ?? null
  const cartLines = state.lines ?? null

  const statusQuery = usePaymentStatus(orderId)
  const orderQuery = useOrder(orderId)
  const cancelIntent = useCancelPaymentIntent()

  const [now, setNow] = useState(() => new Date())
  const [error, setError] = useState(null)
  const [confirmingCancel, setConfirmingCancel] = useState(false)
  const [cancelledLocal, setCancelledLocal] = useState(false)
  const clearedRef = useRef(false)

  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 1000)
    return () => clearInterval(timer)
  }, [])

  const status = statusQuery.data ?? null
  const order = orderQuery.data ?? null

  const phase = paymentState(
    {
      paid: status?.paid,
      orderStatus: order?.status ?? status?.status,
      paymentStatus: order?.paymentStatus ?? status?.paymentStatus,
      intentStatus: status?.intentStatus,
      expiresAt: status?.expiresAt ?? checkout?.expiresAt,
    },
    now,
  )

  const amount = status?.amount ?? checkout?.amount ?? order?.totalAmount ?? 0
  const feeAmount =
    status?.feeAmount ?? checkout?.feeAmount ?? order?.feeAmount ?? null
  const orderTotal = order?.totalAmount ?? null
  const feeInfo =
    order && order.feeRateBps
      ? { rate_bps: order.feeRateBps, vat_bps: order.feeVatBps }
      : null
  const checkoutUrl = status?.checkoutUrl ?? checkout?.checkoutUrl ?? null

  // The order's own lines once its snapshot has loaded, the cart's copy before
  // that (and only while they are the same lines — see `cartLinesToClear`).
  const lines = order?.items?.length
    ? order.items
    : summaryLines(cartLines ?? [])

  const deadline = deadlineState(
    status?.expiresAt ?? checkout?.expiresAt ?? null,
    now,
  )

  /**
   * When the payment lands, the pairs have been bought — so the cart's copies
   * come out. The app's timing, kept: items stay in the cart while the payment
   * is pending (so the customer can see what they are paying for, and retry or
   * cancel freely) and are removed only once the server says paid.
   *
   * Which lines that means is decided by matching the order's lines back to the
   * cart on `(product_id, size)` — not by trusting a list passed through
   * navigation state, so it also works on a resumed visit days later.
   */
  useEffect(() => {
    if (phase !== 'paid' || clearedRef.current) return
    if (!order?.items?.length || !cartItems.length) return

    clearedRef.current = true
    const ids = cartLinesToClear(cartItems, order.items)
    if (ids.length > 0) {
      const lines = cartItems.filter((line) => ids.includes(line.id))
      removeLines(lines).catch(() => {})
    }
  }, [phase, order, cartItems, removeLines])

  async function onCancel() {
    setError(null)
    try {
      const didCancel = await cancelIntent.mutateAsync(orderId)
      setCancelledLocal(true)
      if (!didCancel) {
        setError('That payment had already resolved — check the status below.')
      } else {
        statusQuery.refetch()
      }
    } catch (caught) {
      setError(checkoutError(caught, 'We could not cancel that payment.').message)
    } finally {
      setConfirmingCancel(false)
    }
  }

  if (statusQuery.isLoading && !checkout) {
    return (
      <Shell>
        <div className="shimmer h-64 rounded-premium" />
      </Shell>
    )
  }

  if (statusQuery.isError && !checkout) {
    return (
      <Shell>
        <Panel tone="crimson" Icon={TimerOff} title="We could not check that payment">
          {checkoutError(statusQuery.error, 'Please reload and try again. Nothing has been charged.').message}
        </Panel>
        <Actions />
      </Shell>
    )
  }

  const paid = phase === 'paid'
  const closed = cancelledLocal || phase === 'cancelled'
  const lapsed = !paid && !closed && (phase === 'expired' || (deadline.known && deadline.expired))

  // ── Paid ────────────────────────────────────────────────────────────────
  if (paid) {
    return (
      <Shell>
        <Panel tone="olive" Icon={Check} title="Payment received">
          PayMongo confirmed the payment and {order?.storeName ?? 'the maker'}{' '}
          has your order. You will see it move through preparing and ready in
          your notifications.
        </Panel>

        {order?.items?.length > 0 && (
          <div className="mt-6">
            <OrderSummaryCard
              lines={order.items}
              subtotal={Math.round(
                order.items.reduce((sum, line) => sum + line.lineTotal, 0) * 100,
              ) / 100}
              deliveryFee={Math.max(
                0,
                Math.round((order.totalAmount -
                  order.items.reduce((sum, line) => sum + line.lineTotal, 0)) * 100) / 100,
              )}
              total={order.totalAmount}
              totalLabel="Paid"
              note={`Order #${shortOrderId(orderId)} · ${order.storeName}`}
            />
          </div>
        )}

        {!order?.items?.length && (
          <div className="mt-6 rounded-card border border-hairline bg-raised p-6 shadow-card">
            <dl className="space-y-3 text-sm">
              <div className="flex items-baseline justify-between">
                <dt className="text-muted">Order</dt>
                <dd className="num font-semibold text-ink">
                  #{shortOrderId(orderId)}
                </dd>
              </div>
              <div className="flex items-baseline justify-between border-t border-hairline pt-3">
                <dt className="font-semibold text-ink">Paid</dt>
                <dd className="num text-xl font-semibold text-ink">
                  {formatCurrency(amount)}
                </dd>
              </div>
            </dl>
          </div>
        )}

        <Actions />
      </Shell>
    )
  }

  // ── Cancelled, or never started ─────────────────────────────────────────
  if (closed) {
    return (
      <Shell>
        <Panel tone="crimson" Icon={X} title="This checkout was cancelled">
          Nothing was charged, and no pairs were reserved. Your cart is exactly
          as you left it.
          {order?.cancellationReason && (
            <span className="mt-2 block text-xs text-muted">
              Reason: {order.cancellationReason}
            </span>
          )}
        </Panel>
        <Actions />
      </Shell>
    )
  }

  // ── Waiting on the customer ─────────────────────────────────────────────
  return (
    <Shell>
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <h1 className="font-display text-3xl font-semibold text-ink">
          {lapsed ? 'Payment window closed' : 'Waiting for your GCash payment'}
        </h1>
        <p className="num text-xs text-muted">Order #{shortOrderId(orderId)}</p>
      </div>

      {lapsed ? (
        <Panel tone="crimson" Icon={TimerOff} title="The payment page has timed out">
          PayMongo sessions expire after 15 minutes, and this one has. Nothing
          was charged. You can cancel below to release the order and try again,
          or check once more in case it went through just before the deadline.
        </Panel>
      ) : (
        <div className="mt-6 rounded-premium bg-clay p-6 text-ink-inverse shadow-warm">
          <p className="text-xs uppercase tracking-[0.14em] text-white/75">
            Amount to pay in GCash
          </p>
          <p className="num mt-2 text-4xl font-semibold">
            {formatCurrency(amount)}
          </p>
          {feeAmount ? (
            <p className="mt-2 text-xs text-white/75">
              {formatCurrency(orderTotal ?? amount - feeAmount)} order +{' '}
              {formatCurrency(feeAmount)} GCash fee
            </p>
          ) : null}
          {deadline.known && (
            <p className="mt-3 flex items-center gap-2 text-sm text-white/85">
              <Clock size={15} strokeWidth={2} />
              Pay within{' '}
              <span className="num font-semibold">
                {formatCountdown(deadline.msLeft)}
              </span>
            </p>
          )}
        </div>
      )}

      <section className="mt-6 rounded-card border border-hairline bg-raised p-6 shadow-card">
        <h2 className="font-display text-lg font-semibold text-ink">
          Finish in GCash
        </h2>
        <p className="mt-1 text-sm leading-relaxed text-muted">
          The PayMongo page opened in a new tab. If it did not, or it was closed,
          reopen it here — this page keeps checking either way.
        </p>

        <div className="mt-5 flex flex-wrap gap-3">
          {checkoutUrl && (
            <a
              href={checkoutUrl}
              target="_blank"
              rel="noreferrer noopener"
              className="btn btn-primary"
            >
              <ExternalLink size={15} strokeWidth={2.5} />
              {lapsed ? 'Reopen the payment page' : 'Open the payment page'}
            </a>
          )}
          <button
            type="button"
            onClick={() => statusQuery.refetch()}
            disabled={statusQuery.isFetching}
            className="btn btn-outline"
          >
            {statusQuery.isFetching ? (
              <Loader2 size={15} className="animate-spin" />
            ) : (
              <RefreshCw size={15} strokeWidth={2.5} />
            )}
            Check again
          </button>
        </div>

        <p className="mt-4 text-xs leading-relaxed text-muted">
          This page checks with PayMongo every few seconds and will switch to
          &ldquo;payment received&rdquo; the moment it is confirmed. You can also
          pay from the CUFMAI app with the same account.
        </p>
      </section>

      {lines.length > 0 && (
        <section className="mt-6">
          <OrderSummaryCard
            lines={lines}
            subtotal={round(
              lines.reduce((sum, line) => sum + line.lineTotal, 0),
            )}
            deliveryFee={round(
              Math.max(0, (orderTotal ?? amount - (feeAmount ?? 0)) - lines.reduce((sum, line) => sum + line.lineTotal, 0)),
            )}
            feeAmount={feeAmount}
            feeLabel={feeInfo ? feeLabel(feeInfo) : 'GCash fee'}
            total={amount}
            totalLabel="You pay"
            note="Your pairs stay in the cart until the payment is confirmed."
          />
        </section>
      )}

      {error && (
        <p role="alert" className="mt-6 text-sm font-medium text-crimson">
          {error}
        </p>
      )}

      {/* ── Cancel ──────────────────────────────────────────────────────── */}
      <div className="mt-8 rounded-card border border-hairline bg-subtle/50 p-5">
        {confirmingCancel ? (
          <div>
            <p className="text-sm font-semibold text-ink">Cancel this payment?</p>
            <p className="mt-1 text-xs leading-relaxed text-muted">
              The PayMongo session is closed and the order released. If you have
              already paid, do not cancel — it will be confirmed within moments.
            </p>
            <div className="mt-4 flex flex-wrap gap-3">
              <button
                type="button"
                onClick={onCancel}
                disabled={cancelIntent.isPending}
                className="btn btn-primary"
              >
                {cancelIntent.isPending && (
                  <Loader2 size={15} className="animate-spin" />
                )}
                {cancelIntent.isPending ? 'Cancelling…' : 'Yes, cancel it'}
              </button>
              <button
                type="button"
                onClick={() => setConfirmingCancel(false)}
                className="btn btn-outline"
              >
                Keep waiting
              </button>
            </div>
          </div>
        ) : (
          <div className="flex flex-wrap items-center justify-between gap-4">
            <p className="text-xs leading-relaxed text-muted">
              Changed your mind, or could not finish in GCash? Cancel and nothing
              is charged.
            </p>
            <button
              type="button"
              onClick={() => setConfirmingCancel(true)}
              className="btn btn-outline h-9 px-4 py-0 text-xs"
            >
              Cancel this payment
            </button>
          </div>
        )}
      </div>
    </Shell>
  )
}

/** Centavo-rounded, so a float sum cannot print ₱1,499.0000000000002. */
function round(value) {
  return Math.round((Number(value) || 0) * 100) / 100
}

/** The page frame: one column, centered, with room for the panels inside. */
function Shell({ children }) {
  return (
    <div className="mx-auto max-w-2xl px-4 py-10 sm:px-6 lg:px-8">{children}</div>
  )
}

/** A state banner — paid, cancelled, expired, unavailable. */
function Panel({ tone = 'muted', Icon, title, children }) {
  const tones = {
    olive: 'border-olive/35 bg-olive/[0.07] text-ink',
    crimson: 'border-crimson/30 bg-crimson/[0.06] text-ink',
    muted: 'border-hairline bg-subtle/60 text-ink',
  }

  return (
    <div className={`mt-6 rounded-card border p-6 ${tones[tone] ?? tones.muted}`}>
      <div className="flex items-start gap-3">
        {Icon && (
          <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-raised">
            <Icon size={17} strokeWidth={2.25} className="text-ink" />
          </span>
        )}
        <div>
          <p className="font-display text-lg font-semibold">{title}</p>
          <div className="mt-1.5 text-sm leading-relaxed text-muted-strong">
            {children}
          </div>
        </div>
      </div>
    </div>
  )
}

function Actions() {
  return (
    <div className="mt-6 flex flex-wrap justify-center gap-3">
      <Link to="/shop" className="btn btn-outline">
        <ShoppingBag size={15} strokeWidth={2} />
        Keep shopping
      </Link>
      <Link to="/cart" className="btn btn-outline">
        View your cart
      </Link>
    </div>
  )
}
