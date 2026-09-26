import { Link, useOutletContext, useSearchParams } from 'react-router-dom'
import { ClipboardList, Truck } from 'lucide-react'

import StatusPill from '../../components/orders/StatusPill'
import {
  SellerPageBody,
  SellerPageHeader,
  SellerSection,
} from '../../components/seller/SellerPage.jsx'
import EmptyState from '../../components/ui/EmptyState.jsx'
import { formatCurrency } from '../../lib/constants.js'
import { orderLines, shortOrderRef } from '../../lib/orderRules.js'
import {
  availableSellerOrderTabs,
  filterSellerOrders,
  primarySellerAction,
  sortSellerOrders,
} from '../../lib/seller.js'
import { useSellerOrders } from '../../hooks/useSeller.js'

/**
 * The seller's order queue.
 *
 * The tab lives in the query string (`?tab=attention`) rather than in state, for
 * the reason the customer's orders page gives: a tab that only exists in React
 * state cannot be linked to, and "look at the ones waiting on you" is exactly the
 * sentence a dashboard alert wants to be a link. The dashboard's alert already
 * relies on this.
 *
 * The rows are lightweight on purpose — reference, who, how much, where it
 * stands — because this page's job is triage. Everything a maker needs to decide
 * what to do sits one click away on the order itself, and a list that tried to
 * carry the whole order would be a list nobody scans.
 */
export default function SellerOrders() {
  const { store } = useOutletContext()
  const ordersQuery = useSellerOrders(store?.id ?? null)
  const [params, setParams] = useSearchParams()

  const requestedTab = params.get('tab') ?? 'all'
  const orders = ordersQuery.data ?? []

  const tabs = availableSellerOrderTabs(orders)
  // A tab the URL asks for that no longer exists falls back to All rather than
  // rendering an empty page under a selected tab.
  const activeTab = tabs.some((tab) => tab.id === requestedTab)
    ? requestedTab
    : 'all'

  const visible = sortSellerOrders(filterSellerOrders(orders, activeTab))
  const counts = new Map(
    tabs.map((tab) => [tab.id, orders.filter(tab.match).length]),
  )

  return (
    <SellerPageBody>
      <SellerPageHeader
        eyebrow={`${orders.length} ${
          orders.length === 1 ? 'order' : 'orders'
        } all time`}
        title="Orders"
        description="Every order placed against your storefront, newest first."
      />

      <SellerSection>
        <div
          role="tablist"
          aria-label="Order status"
          className="-mx-1 flex flex-wrap gap-1.5"
        >
          {tabs.map((tab) => {
            const active = tab.id === activeTab
            return (
              <button
                key={tab.id}
                type="button"
                role="tab"
                aria-selected={active}
                onClick={() =>
                  setParams(tab.id === 'all' ? {} : { tab: tab.id }, {
                    replace: true,
                  })
                }
                className={[
                  'rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors duration-200 ease-out-cubic',
                  active
                    ? 'bg-clay text-ink-inverse'
                    : 'text-muted-strong hover:bg-subtle hover:text-ink',
                ].join(' ')}
              >
                {tab.label}
                <span
                  className={`num ml-1.5 text-xs ${
                    active ? 'text-ink-inverse/75' : 'text-muted'
                  }`}
                >
                  {counts.get(tab.id) ?? 0}
                </span>
              </button>
            )
          })}
        </div>

        <div className="mt-5">
          {ordersQuery.isLoading ? (
            <div className="space-y-3">
              {[0, 1, 2, 3].map((key) => (
                <div key={key} className="shimmer h-20 rounded-card" />
              ))}
            </div>
          ) : ordersQuery.isError ? (
            <div
              role="alert"
              className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm text-ink"
            >
              We could not load your orders. Check your connection and reload the
              page.
            </div>
          ) : visible.length === 0 ? (
            <EmptyState
              Icon={ClipboardList}
              title={
                activeTab === 'attention'
                  ? 'Nothing needs you'
                  : 'Nothing in this list'
              }
              description={
                activeTab === 'attention'
                  ? 'No cancellations to approve and no payments to check. This list fills up when a customer asks for something.'
                  : 'Try another tab, or wait for the next order to come in.'
              }
              className="py-10"
            />
          ) : (
            <ul className="divide-y divide-hairline-soft">
              {visible.map((order) => (
                <OrderRow key={order.id} order={order} />
              ))}
            </ul>
          )}
        </div>
      </SellerSection>
    </SellerPageBody>
  )
}

/**
 * One order in the queue.
 *
 * The next step is printed on the row, not only on the order page, because the
 * common case is a seller working down the list — going into each order to find
 * out what it needs is the friction this line removes. It is a *label* here, not
 * a button: the write belongs on the order, where the customer, the address and
 * the lines are all in front of the person pressing it.
 */
function OrderRow({ order }) {
  const lines = orderLines(order)
  const pieces = lines.reduce(
    (sum, line) => sum + (Number(line.quantity) || 0),
    0,
  )
  const next = primarySellerAction(order.status)

  return (
    <li>
      <Link
        to={`/seller/orders/${order.id}`}
        className="flex flex-wrap items-center gap-x-5 gap-y-3 py-4 transition-colors duration-200 ease-out-cubic hover:bg-subtle/50"
      >
        <div className="min-w-[9rem] flex-1">
          <p className="num text-sm font-semibold text-ink">
            {shortOrderRef(order.id)}
          </p>
          <p className="mt-0.5 truncate text-xs text-muted">
            {order.customer_name}
          </p>
        </div>

        <div className="min-w-[7rem] text-xs text-muted">
          <p>
            {pieces} {pieces === 1 ? 'pair' : 'pairs'}
          </p>
          <p className="mt-0.5 inline-flex items-center gap-1">
            <Truck className="h-3.5 w-3.5" aria-hidden="true" />
            {order.fulfillment === 'delivery' ? 'Delivery' : 'Pickup'}
          </p>
        </div>

        <div className="min-w-[6rem] text-right">
          <p className="num text-sm font-semibold text-ink">
            {formatCurrency(order.total_amount)}
          </p>
          <p className="mt-0.5 text-xs text-muted">
            {order.payment_status === 'paid' ? 'Paid' : 'Unpaid'}
          </p>
        </div>

        <div className="flex min-w-[12rem] items-center justify-end gap-3">
          {next && (
            <span className="hidden text-xs font-medium text-clay-ink sm:inline">
              {next.label}
            </span>
          )}
          <StatusPill status={order.status} />
        </div>
      </Link>
    </li>
  )
}
