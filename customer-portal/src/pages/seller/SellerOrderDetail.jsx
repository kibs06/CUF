import { useState } from 'react'
import { Link, useOutletContext, useParams } from 'react-router-dom'
import { ArrowLeft, Loader2, PackageOpen } from 'lucide-react'

import StatusPill from '../../components/orders/StatusPill'
import {
  SellerPageBody,
  SellerSection,
} from '../../components/seller/SellerPage.jsx'
import EmptyState from '../../components/ui/EmptyState.jsx'
import { formatCurrency, formatDate } from '../../lib/constants.js'
import {
  orderLines,
  orderTimeline,
  shippingAddressLines,
  shortOrderRef,
} from '../../lib/orderRules.js'
import {
  sellerOrderActions,
  sellerOrderFee,
  statusWriteError,
} from '../../lib/seller.js'
import {
  useSellerOrder,
  useUpdateSellerOrderStatus,
} from '../../hooks/useSeller.js'

/**
 * One order, and the one or two things a maker can do to it.
 *
 * The actions come from `sellerOrderActions`, which is a port of the app's own
 * `_nextStatus` — so this page cannot offer a transition the phone would not,
 * and neither cannot offer one the `orders.status` CHECK would reject.
 *
 * What this page deliberately does NOT do:
 *
 *  - **It does not write customer notifications or pushes.** The `orders` table
 *    already has an `AFTER UPDATE OF status` trigger that writes the customer's
 *    notification row, so doing it here as well would send the customer two. The
 *    app does it client-side on top of the trigger, which is a duplicate the
 *    portal should not add to.
 *  - **It does not release inventory on a cancellation.** No path in this schema
 *    does for a paid order, and inventing one here would make the web disagree
 *    with the app about how many pairs are in the tray.
 *  - **It does not let the seller edit the money.** The amount was decided at
 *    checkout and `orders` has no seller policy for the columns that carry it.
 *  - **It does not link to a seller inbox, because the portal does not have
 *    one.** `lib/messages.js` filters every query on
 *    `conversations.customer_id = auth.uid()`, which is the customer's side of
 *    the same table — a seller opening `/messages` would find an empty inbox,
 *    because `conversations.customer_id` is the buyer, not them. Pointing at it
 *    would look like a link and behave like one that is broken, so the page says
 *    where the real one is instead.
 */
export default function SellerOrderDetail() {
  const { orderId } = useParams()
  const { store } = useOutletContext()
  const storeId = store?.id ?? null

  const orderQuery = useSellerOrder(orderId, storeId)
  const mutation = useUpdateSellerOrderStatus(storeId)
  const [error, setError] = useState(null)

  const order = orderQuery.data

  const runAction = async (action) => {
    setError(null)
    try {
      await mutation.mutateAsync({ orderId, status: action.status })
    } catch (failure) {
      setError(statusWriteError(failure).message)
    }
  }

  if (orderQuery.isLoading) {
    return (
      <SellerPageBody>
        <div className="shimmer h-64 rounded-premium" />
      </SellerPageBody>
    )
  }

  if (orderQuery.isError || !order) {
    return (
      <SellerPageBody>
        <EmptyState
          Icon={PackageOpen}
          title="We could not find that order"
          description="It may have been deleted, or it may not belong to your store."
          action={
            <Link to="/seller/orders" className="btn btn-outline">
              Back to orders
            </Link>
          }
        />
      </SellerPageBody>
    )
  }

  const lines = orderLines(order)
  const timeline = orderTimeline(order)
  const actions = sellerOrderActions(order.status)
  const fee = sellerOrderFee(order)
  const subtotal = lines.reduce((sum, line) => sum + line.lineTotal, 0)
  const address = shippingAddressLines(order.shipping_address)

  return (
    <SellerPageBody>
      <div>
        <Link
          to="/seller/orders"
          className="inline-flex items-center gap-1.5 text-sm font-medium text-muted transition-colors duration-200 ease-out-cubic hover:text-ink"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          All orders
        </Link>

        <div className="mt-4 flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="overline">{formatDate(order.created_at)}</p>
            <h1 className="num mt-1.5 font-display text-2xl font-semibold text-ink sm:text-3xl">
              {shortOrderRef(order.id)}
            </h1>
            <p className="mt-2 text-sm text-muted">
              {order.customer_name}
              {order.customer_email && ` · ${order.customer_email}`}
            </p>
          </div>

          <div className="flex flex-col items-end gap-3">
            <StatusPill status={order.status} />
            {/*
              The buttons are one row and the primary is first, matching the
              order `sellerOrderActions` returns them in. A disabled state is
              used while the write is in flight rather than a spinner per button,
              so the row does not change width mid-press.
            */}
            {actions.length > 0 && (
              <div className="flex flex-wrap justify-end gap-2">
                {actions.map((action) => (
                  <button
                    key={action.id}
                    type="button"
                    onClick={() => runAction(action)}
                    disabled={mutation.isPending}
                    className={`btn ${
                      action.tone === 'primary'
                        ? 'btn-primary'
                        : action.tone === 'danger'
                          ? 'btn-outline border-crimson/40 text-crimson hover:bg-crimson/[0.07]'
                          : 'btn-outline'
                    }`}
                  >
                    {mutation.isPending && (
                      <Loader2 size={15} className="animate-spin" />
                    )}
                    {action.label}
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {error && (
        <div
          role="alert"
          className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm leading-relaxed text-ink"
        >
          {error}
        </div>
      )}

      {/*
        Why there is no button. Waiting is a real state, and saying so is better
        than an empty space the seller reads as a missing feature.
      */}
      {actions.length === 0 && (
        <p className="rounded-field border border-hairline bg-subtle/50 px-4 py-3 text-sm text-muted">
          {statusExplanation(order.status)}
        </p>
      )}

      <div className="grid gap-6 lg:grid-cols-[1.5fr_1fr]">
        <SellerSection title="Items">
          {lines.length === 0 ? (
            <p className="text-sm text-muted">
              This order has no line items recorded yet. That is normal while a
              payment is still pending — the lines are written once the money
              moves.
            </p>
          ) : (
            <ul className="divide-y divide-hairline-soft">
              {lines.map((line) => (
                <li
                  key={line.id}
                  className="flex items-center gap-4 py-3 first:pt-0 last:pb-0"
                >
                  {line.imageUrl ? (
                    <img
                      src={line.imageUrl}
                      alt=""
                      className="h-14 w-14 shrink-0 rounded-product object-cover"
                    />
                  ) : (
                    <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-product bg-subtle">
                      <PackageOpen
                        className="h-5 w-5 text-muted"
                        aria-hidden="true"
                      />
                    </span>
                  )}

                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-ink">
                      {line.name}
                    </p>
                    <p className="mt-0.5 text-xs text-muted">
                      {line.size ? `Size ${line.size} · ` : ''}
                      {line.quantity}{' '}
                      {line.quantity === 1 ? 'pair' : 'pairs'}
                    </p>
                  </div>

                  <span className="num shrink-0 text-sm font-semibold text-ink">
                    {formatCurrency(line.lineTotal)}
                  </span>
                </li>
              ))}
            </ul>
          )}

          <dl className="mt-5 space-y-2 border-t border-hairline-soft pt-4 text-sm">
            <Row label="Subtotal" value={formatCurrency(subtotal)} />
            <Row label="Delivery fee" value={formatCurrency(fee)} />
            <Row
              label="Total"
              value={formatCurrency(order.total_amount)}
              strong
            />
          </dl>
        </SellerSection>

        <div className="flex flex-col gap-6">
          <SellerSection title="Fulfilment">
            <dl className="space-y-3 text-sm">
              <Row
                label="Method"
                value={order.fulfillment === 'delivery' ? 'Delivery' : 'Pickup'}
              />
              <Row
                label="Payment"
                value={order.payment_status === 'paid' ? 'Paid' : 'Unpaid'}
              />
              {order.notes && (
                <div>
                  <dt className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                    Customer note
                  </dt>
                  <dd className="mt-1 leading-relaxed text-ink">
                    {order.notes}
                  </dd>
                </div>
              )}
            </dl>

            {address.length > 0 && (
              <div className="mt-5 border-t border-hairline-soft pt-4">
                <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                  Deliver to
                </p>
                <address className="mt-2 space-y-0.5 text-sm not-italic leading-relaxed text-ink">
                  {address.map((line) => (
                    <p key={line}>{line}</p>
                  ))}
                </address>
              </div>
            )}

            {order.customer_email && (
              <p className="mt-5 border-t border-hairline-soft pt-4 text-xs leading-relaxed text-muted">
                To reach {order.customer_name.split(' ')[0]}, use the chat in the
                CUFMAI app — the seller inbox lives there.
              </p>
            )}
          </SellerSection>

          <SellerSection title="History">
            <ol className="space-y-4">
              {timeline.map((entry) => (
                <li key={entry.key} className="flex gap-3">
                  <span
                    aria-hidden="true"
                    className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-clay"
                  />
                  <div>
                    <p className="text-sm font-medium text-ink">
                      {entry.label}
                    </p>
                    <p className="mt-0.5 text-xs text-muted">
                      {entry.at.toLocaleString('en-PH', {
                        month: 'short',
                        day: 'numeric',
                        hour: 'numeric',
                        minute: '2-digit',
                      })}
                    </p>
                  </div>
                </li>
              ))}
            </ol>
          </SellerSection>
        </div>
      </div>
    </SellerPageBody>
  )
}

function Row({ label, value, strong = false }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <dt className={strong ? 'font-semibold text-ink' : 'text-muted'}>
        {label}
      </dt>
      <dd
        className={`num ${strong ? 'text-base font-semibold text-ink' : 'text-ink'}`}
      >
        {value}
      </dd>
    </div>
  )
}

/**
 * What the absence of a button means, per status.
 *
 * Each sentence names who is being waited on, because "no action available" and
 * "we are waiting for the buyer" look identical on a screen and only one of them
 * is worth the seller looking into.
 */
function statusExplanation(status) {
  switch (status) {
    case 'delivered':
    case 'received':
      return 'This order is out of your hands. It closes when the customer confirms they received it.'
    case 'awaiting_payment':
    case 'awaiting_payment_confirmation':
      return 'This order is waiting for the customer to pay. Nothing to do here yet.'
    case 'payment_conflict':
      return 'This order needs checking against the payment. Contact the customer or the association before shipping.'
    case 'cancelled':
      return 'This order was cancelled, and cannot be restored from this status.'
    default:
      return 'There is nothing to do with this order right now.'
  }
}
