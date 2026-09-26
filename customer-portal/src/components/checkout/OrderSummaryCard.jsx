import { ImageOff } from 'lucide-react'

import { formatCurrency } from '../../lib/constants'

/**
 * What is being bought, what it comes to, and what GCash will actually charge.
 *
 * Three numbers, kept apart deliberately, because they are three different
 * things and a customer is entitled to see the difference:
 *
 *   Subtotal      goods, at the sale price the storefront showed
 *   Delivery fee  the fixed ₱100 the order function adds
 *   GCash fee     the Model B surcharge, an amount we READ from the server and
 *                 never compute — a rate change must not need a web deploy
 *   Total         what the customer's GCash is charged: the sum of all three
 *
 * `feeAmount` is null while the fee is unknown (still loading, or the read
 * failed). The row is then omitted and the note says how it will be handled,
 * rather than printing ₱0.00 and calling an unknown surcharge free.
 */
export default function OrderSummaryCard({
  lines = [],
  subtotal,
  deliveryFee,
  feeAmount = null,
  feeLabel = 'GCash fee',
  total,
  totalLabel = 'Total',
  note,
  className = '',
}) {
  const showFee = feeAmount !== null && feeAmount !== undefined

  return (
    <div
      className={`rounded-card border border-hairline bg-raised shadow-card ${className}`}
    >
      {lines.length > 0 && (
        <ul className="divide-y divide-hairline-soft">
          {lines.map((line) => (
            <li key={line.id} className="flex gap-4 p-5">
              <div className="relative h-16 w-16 shrink-0 overflow-hidden rounded-product bg-subtle">
                {line.imageUrl ? (
                  <img
                    src={line.imageUrl}
                    alt=""
                    loading="lazy"
                    decoding="async"
                    className="h-full w-full object-cover"
                  />
                ) : (
                  <span className="flex h-full items-center justify-center">
                    <ImageOff size={20} className="text-muted/50" strokeWidth={1.5} />
                  </span>
                )}
              </div>

              <div className="min-w-0 flex-1">
                <p className="line-clamp-2 text-sm font-semibold leading-snug text-ink">
                  {line.name}
                </p>
                <p className="mt-1 text-xs text-muted">
                  {line.size ? `Size ${line.size}` : 'Size not set'} · Qty{' '}
                  {line.quantity}
                </p>
                {line.quantity > 1 && (
                  <p className="num mt-0.5 text-xs text-muted">
                    {formatCurrency(line.unitPrice)} each
                  </p>
                )}
              </div>

              <p className="num shrink-0 text-sm font-semibold text-ink">
                {formatCurrency(line.lineTotal)}
              </p>
            </li>
          ))}
        </ul>
      )}

      <dl className="space-y-3 border-t border-hairline p-5 text-sm">
        <div className="flex items-baseline justify-between">
          <dt className="text-muted">Subtotal</dt>
          <dd className="num font-semibold text-ink">
            {formatCurrency(subtotal)}
          </dd>
        </div>
        <div className="flex items-baseline justify-between">
          <dt className="text-muted">Delivery fee</dt>
          <dd className="num font-semibold text-ink">
            {formatCurrency(deliveryFee)}
          </dd>
        </div>
        {showFee && (
          <div className="flex items-baseline justify-between">
            <dt className="text-muted">{feeLabel}</dt>
            <dd className="num font-semibold text-ink">
              {formatCurrency(feeAmount)}
            </dd>
          </div>
        )}
        <div className="flex items-baseline justify-between border-t border-hairline pt-3">
          <dt className="font-semibold text-ink">{totalLabel}</dt>
          <dd className="num text-xl font-semibold text-ink">
            {formatCurrency(total)}
          </dd>
        </div>
        {note && <p className="pt-1 text-xs leading-relaxed text-muted">{note}</p>}
      </dl>
    </div>
  )
}
