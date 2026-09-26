import { useMemo, useState } from 'react'
import { useOutletContext } from 'react-router-dom'
import { Info } from 'lucide-react'

import {
  SellerPageBody,
  SellerPageHeader,
  SellerMetric,
  SellerSection,
} from '../../components/seller/SellerPage.jsx'
import CountUp from '../../components/ui/CountUp.jsx'
import { formatCurrency } from '../../lib/constants.js'
import { orderLines } from '../../lib/orderRules.js'
import { dailyBuckets } from '../../lib/seller.js'
import { useSellerOrders } from '../../hooks/useSeller.js'

const PERIODS = [
  { id: '7', label: 'Last 7 days', days: 7 },
  { id: '30', label: 'Last 30 days', days: 30 },
  { id: '90', label: 'Last 90 days', days: 90 },
]

/**
 * Revenue for the seller's online orders.
 *
 * ## What this is, and what it is not
 *
 * It is **online orders only**. The app's `ReportsScreen` adds in-person POS
 * takings from `sales_transactions` and reports the two channels side by side
 * (`channelOnline` / `channelInStore` are the same two colours in every chart
 * there). The seller portal has no POS: a point of sale is a counter, a barcode
 * scanner and a receipt printer, and a browser tab at a market stall is not a
 * substitute. So this page reports one channel and says so, rather than
 * printing an online-only figure under a heading that implies it is the day's
 * takings.
 *
 * ## Why the money is derived, not stored
 *
 * `orders` carries `total_amount` and no per-line revenue roll-up, so every
 * figure here is summed from the orders already in the cache — no extra request,
 * and no number that can disagree with the orders list it came from. Cancelled
 * orders are excluded everywhere, for the reason `dashboardTotals` gives.
 *
 * Line revenue comes from `orderLines`, which is the *customer's* rule and
 * prefers the real `order_items` rows over `items_snapshot`. Re-deriving it here
 * would be a second opinion about what a line costs.
 *
 * The day bucketing is `dailyBuckets` from `sellerRules.js`, shared with the
 * dashboard's chart. This page used to carry its own copy of it, and the copy
 * was already a fourth opinion about what "a day" means (local midnight, empty
 * days present) — three of which existed only here.
 */
export default function SellerReports() {
  const { store } = useOutletContext()
  const ordersQuery = useSellerOrders(store?.id ?? null)
  const [periodId, setPeriodId] = useState('30')

  const period = PERIODS.find((entry) => entry.id === periodId) ?? PERIODS[1]
  const orders = ordersQuery.data ?? []

  const report = useMemo(() => buildReport(orders, period.days), [orders, period.days])

  /*
   * The four readings of the period.
   *
   * All four count up, and here that is more than a flourish: the period pills
   * above them re-derive every figure from the same cached orders, so the count
   * is how a seller sees that changing the period actually changed the numbers.
   * Silent re-renders of `₱12,480.00` → `₱28,905.50` look like the click did
   * nothing until they read both.
   *
   * The money is still the rounded, two-decimal formatter's output — mid-count
   * values included, so the figure never shows a precision it will not settle on.
   */
  return (
    <SellerPageBody>
      <SellerPageHeader
        eyebrow="Reports"
        title="Revenue"
        description="From your storefront orders only. In-person POS sales are recorded in the CUFMAI app."
      />

      <div className="flex flex-wrap gap-1.5">
        {PERIODS.map((entry) => (
          <button
            key={entry.id}
            type="button"
            onClick={() => setPeriodId(entry.id)}
            aria-pressed={entry.id === periodId}
            className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors duration-200 ease-out-cubic ${
              entry.id === periodId
                ? 'bg-clay text-ink-inverse'
                : 'text-muted-strong hover:bg-subtle hover:text-ink'
            }`}
          >
            {entry.label}
          </button>
        ))}
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <SellerMetric
          label="Ordered"
          value={<CountUp value={report.revenue} format={formatCurrency} />}
          tone="accent"
          hint={`${report.orderCount} ${
            report.orderCount === 1 ? 'order' : 'orders'
          }, cancellations excluded.`}
        />
        <SellerMetric
          label="Ready to collect or delivered"
          value={<CountUp value={report.settled} format={formatCurrency} />}
          hint="Orders the customer has received."
        />
        <SellerMetric
          label="Average order"
          value={<CountUp value={report.average} format={formatCurrency} />}
          hint="Across the orders in this period."
        />
        <SellerMetric
          label="Still unpaid"
          value={<CountUp value={report.unpaidCount} />}
          tone={report.unpaidCount > 0 ? 'alert' : 'neutral'}
          hint="Orders placed but not paid for."
        />
      </div>

      {/*
        The caveat is on the page, not only in this docblock. A maker comparing
        this figure against the app's total would otherwise find a difference
        and have no way to know it is their counter sales.
      */}
      <p className="flex items-start gap-2.5 rounded-field border border-hairline bg-subtle/50 px-4 py-3 text-xs leading-relaxed text-muted">
        <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
        <span>
          This total will be lower than the one in the CUFMAI app whenever you
          have taken walk-in sales, because those are not orders and are not
          counted here.
        </span>
      </p>

      <div className="grid gap-6 lg:grid-cols-2">
        <SellerSection
          title="By day"
          description="What was ordered on each day in this period."
        >
          {report.byDay.length === 0 ? (
            <p className="text-sm text-muted">No orders in this period.</p>
          ) : (
            <ul className="space-y-3">
              {report.byDay.map((day) => (
                <li key={day.key}>
                  <div className="flex items-baseline justify-between gap-3 text-sm">
                    <span className="text-ink">{day.label}</span>
                    <span className="num font-semibold text-ink">
                      {formatCurrency(day.total)}
                    </span>
                  </div>
                  {/*
                    A bar, not a chart library. One series over at most ninety
                    points needs no axes, no legend and no dependency — and the
                    honest scale for it is the period's own peak, which is what
                    these percentages are computed against.
                  */}
                  <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-subtle">
                    <div
                      className="h-full rounded-full bg-rust"
                      style={{ width: `${day.share}%` }}
                    />
                  </div>
                  <p className="mt-1 text-xs text-muted">
                    {day.count} {day.count === 1 ? 'order' : 'orders'}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </SellerSection>

        <SellerSection
          title="What sold"
          description="Ranked by what each product brought in."
        >
          {report.topProducts.length === 0 ? (
            <p className="text-sm text-muted">Nothing sold in this period.</p>
          ) : (
            <ul className="divide-y divide-hairline-soft">
              {report.topProducts.map((product) => (
                <li
                  key={product.name}
                  className="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0"
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-ink">
                      {product.name}
                    </p>
                    <p className="mt-0.5 text-xs text-muted">
                      {product.pieces}{' '}
                      {product.pieces === 1 ? 'pair' : 'pairs'}
                    </p>
                  </div>
                  <span className="num shrink-0 text-sm font-semibold text-ink">
                    {formatCurrency(product.revenue)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </SellerSection>
      </div>
    </SellerPageBody>
  )
}

/**
 * Everything the page shows, from the orders already in hand.
 *
 * Exported-shape rather than inline JSX so the arithmetic is in one place and
 * can be reasoned about (and later tested) without a browser. Days are bucketed
 * by LOCAL date: a seller in Cebu closing at 11pm is still selling "today", and a
 * UTC bucket would move the last eight hours of their day onto tomorrow.
 */
function buildReport(orders, days, now = new Date()) {
  /*
    The days come from the shared rule rather than a local loop, and the period's
    orders are read back off it — so "this period" is defined in exactly one
    place. `dailyBuckets` already excludes cancelled orders and keeps the empty
    days, which is what the day list below relies on.
  */
  const buckets = dailyBuckets(orders, { now, days })
  const since = buckets[0]?.date.getTime() ?? 0

  const inPeriod = (orders ?? []).filter((order) => {
    if (order?.status === 'cancelled') return false
    const at = new Date(order?.created_at ?? 0)
    return Number.isFinite(at.getTime()) && at.getTime() >= since
  })

  const revenue = buckets.reduce((sum, day) => sum + day.revenue, 0)

  const settled = inPeriod
    .filter((order) => ['delivered', 'received'].includes(order.status))
    .reduce((sum, order) => sum + (Number(order.total_amount) || 0), 0)

  const unpaidCount = inPeriod.filter(
    (order) => order.payment_status !== 'paid',
  ).length

  const peak = Math.max(0, ...buckets.map((day) => day.revenue))

  const byDay = [...buckets]
    .filter((day) => day.orderCount > 0)
    .sort((a, b) => b.date.getTime() - a.date.getTime())
    .map((day) => ({
      key: day.key,
      label: day.date.toLocaleDateString('en-PH', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
      }),
      total: day.revenue,
      count: day.orderCount,
      share: peak > 0 ? Math.round((day.revenue / peak) * 100) : 0,
    }))

  const productTotals = new Map()
  for (const order of inPeriod) {
    for (const line of orderLines(order)) {
      const name = line.name || 'Product'
      const current = productTotals.get(name) ?? { revenue: 0, pieces: 0 }
      current.revenue += Number(line.lineTotal) || 0
      current.pieces += Number(line.quantity) || 0
      productTotals.set(name, current)
    }
  }

  const topProducts = [...productTotals.entries()]
    .map(([name, totals]) => ({ name, ...totals }))
    .sort((a, b) => b.revenue - a.revenue)
    .slice(0, 8)

  return {
    revenue,
    settled,
    orderCount: inPeriod.length,
    average: inPeriod.length > 0 ? revenue / inPeriod.length : 0,
    unpaidCount,
    byDay,
    topProducts,
  }
}
