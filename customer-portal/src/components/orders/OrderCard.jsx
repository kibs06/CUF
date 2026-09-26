import { Link } from 'react-router-dom'
import { ImageOff, Store } from 'lucide-react'

import StatusPill, { OrderProgress } from './StatusPill'
import { formatCurrency } from '../../lib/constants'
import { formatMoment } from './OrderTimeline'
import {
  isUnpaidOrder,
  orderLines,
  orderPieces,
  orderTotals,
  shortOrderRef,
} from '../../lib/orders'

/**
 * One order in the history.
 *
 * The card answers the four questions a customer has about an order they are
 * scrolling past — which order, where it stands, what was in it, what it cost —
 * without opening it. Everything else lives on the detail page.
 *
 * The whole card is the link rather than a "View" button on it: a target the
 * size of the card is the difference between a list that works on a phone and
 * one that does not. The hover lift is the confirmation that it is clickable.
 */
export default function OrderCard({ order, className = '' }) {
  const lines = orderLines(order)
  const totals = orderTotals(order)
  const pieces = orderPieces(order)
  const first = lines[0]
  const extra = lines.length - 1

  return (
    <Link
      to={`/orders/${order.id}`}
      className={`group block rounded-card border border-hairline bg-raised p-5 shadow-card transition-[box-shadow,border-color,transform] duration-300 ease-out-cubic hover:-translate-y-0.5 hover:border-card-edge hover:shadow-card-lift ${className}`}
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="num text-xs text-muted">
            {shortOrderRef(order.id)}
          </p>
          <p className="mt-1 flex items-center gap-1.5 truncate text-sm font-semibold text-ink">
            <Store size={13} strokeWidth={2} className="shrink-0 text-muted" />
            <span className="truncate">{order.store_name ?? 'The maker'}</span>
          </p>
        </div>
        <StatusPill status={order.status} className="shrink-0" />
      </div>

      <div className="mt-4 flex items-center gap-3">
        <div className="relative h-14 w-14 shrink-0 overflow-hidden rounded-product bg-subtle">
          {first?.imageUrl ? (
            <img
              src={first.imageUrl}
              alt=""
              loading="lazy"
              decoding="async"
              className="h-full w-full object-cover transition-transform duration-500 ease-out-cubic group-hover:scale-[1.06]"
            />
          ) : (
            <span className="flex h-full items-center justify-center">
              <ImageOff size={18} className="text-muted/50" strokeWidth={1.5} />
            </span>
          )}
        </div>

        <div className="min-w-0 flex-1">
          <p className="line-clamp-1 text-sm text-ink">
            {first?.name ?? 'Order'}
            {extra > 0 && (
              <span className="text-muted"> and {extra} more</span>
            )}
          </p>
          <p className="mt-0.5 text-xs text-muted">
            {pieces} {pieces === 1 ? 'pair' : 'pairs'} ·{' '}
            <time dateTime={order.created_at ?? undefined}>
              {formatMoment(order.created_at)}
            </time>
          </p>
        </div>

        <p className="num shrink-0 text-base font-semibold text-ink">
          {formatCurrency(totals.total)}
        </p>
      </div>

      <OrderProgress status={order.status} className="mt-5" />

      {isUnpaidOrder(order.status) && (
        <p className="mt-4 text-xs font-semibold text-amber">
          Payment not completed — open to resume or cancel.
        </p>
      )}
    </Link>
  )
}
