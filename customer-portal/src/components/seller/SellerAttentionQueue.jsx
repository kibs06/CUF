import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowRight, Check } from 'lucide-react'

import StatusPill from '../orders/StatusPill.jsx'
import CountUp from '../ui/CountUp.jsx'
import { useContextMenu } from '../ui/ContextMenu.jsx'
import { SellerSection } from './SellerPage.jsx'
import { orderRowMenuItems, orderRowPath } from './sellerRowMenus.js'
import { formatCurrency, pluralize } from '../../lib/constants.js'
import { shortOrderRef } from '../../lib/orderRules.js'
import {
  ATTENTION_SORTS,
  attentionQueue,
  needsSellerAction,
  waitingLabel,
} from '../../lib/sellerRules.js'

/**
 * The orders blocked on the maker, oldest wait first — a preview, not a bench.
 *
 * ## What this card is for
 *
 * It answers one question — *what have I left standing?* — and hands the seller
 * over. The list is ordered by how long each order has waited (`waitingLabel`
 * says so on every row), so the row at the top is the customer who has been
 * waiting longest, which is the only piece of triage this card has to do.
 *
 * ## Why there are no status buttons here
 *
 * There were: each row carried the order's next step and could write it without
 * leaving the dashboard. It was removed because a dashboard row is the one place
 * where *every* piece of an order's context is off screen — who the customer is,
 * where it ships, what they wrote in the thread, whether the payment landed,
 * what they asked for in the customisation — and a status write is a claim about
 * somebody's shoes that the customer gets notified about. The order page has all
 * of that on one screen, with the same buttons, plus the confirmation dialog a
 * destructive one needs.
 *
 * What is left is a card half the height that does the *reading* well: four
 * rows, two lines each, and two doors — the row opens the order, and the header
 * and footer open the whole queue. Working happens where the work is visible.
 *
 * ## The rows are the recent-orders rows
 *
 * Same shape deliberately: identity on the very left, money on the right, the
 * status under the ref so every pill starts on the same vertical line. Two lists
 * on one dashboard that are read the same way should not be drawn two ways.
 *
 * ## Two ways to read it, and the choice is not in the URL
 *
 * `ATTENTION_SORTS` is the whole control: longest wait, or biggest order. It is
 * local state rather than a query parameter, and that is the same call the
 * products page makes for its grid/list view — a *sort* does not change which
 * rows exist, only what to look at first, so a pasted link that reopened
 * somebody else's ordering would be a setting rather than a link. A filter would
 * be the other way round, which is why there isn't one: seeing one status at a
 * time is what the orders page's tabs are for, and a filter chip row here would
 * also make this the tallest card on the page again.
 *
 * ## Loading, and being empty
 *
 * While the orders are still arriving the card draws placeholder rows rather
 * than appearing after them, so the page does not reflow as it fills. When
 * nothing is blocked on the maker the card says exactly that, in olive with a
 * tick — this is the one card on the dashboard whose emptiness is news, because
 * the seller opened it to check.
 */
export default function SellerAttentionQueue({ orders, loading = false, className = '' }) {
  const [sort, setSort] = useState('oldest')

  const queue = useMemo(() => attentionQueue(orders, { sort }), [orders, sort])
  const totalWaiting = useMemo(
    () => (orders ?? []).filter((order) => needsSellerAction(order?.status)).length,
    [orders],
  )

  if (loading) {
    return (
      <section className={className}>
        <div className="shimmer h-40 rounded-premium" />
      </section>
    )
  }

  if (totalWaiting === 0) {
    /*
      `self-start` is load-bearing: this card shares a stretched grid row with
      the day's takings, and stretched a one-line strip would be a sentence above
      a hundred pixels of empty card. The money panel is the tall one — it should
      be.
    */
    return (
      <section
        className={`flex flex-wrap items-center gap-3 self-start rounded-premium border border-hairline bg-raised px-5 py-4 shadow-card ${className}`}
      >
        <Check className="h-5 w-5 shrink-0 text-olive" aria-hidden="true" />
        <p className="min-w-0 flex-1 text-sm leading-relaxed text-ink">
          <span className="font-semibold">Nothing is blocked on you.</span> Every
          order on the book is either finished or waiting on the customer.
        </p>
        <Link
          to="/seller/orders"
          className="text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
        >
          See the orders
        </Link>
      </section>
    )
  }

  return (
    <SellerSection
      className={className}
      title="Needs you now"
      description={`${pluralize(totalWaiting, 'order')} blocked on you.`}
      actions={
        <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
          {/* A segmented control rather than two loose pills: the two sorts are
              one choice, and a shared track says so. `aria-pressed` on each, so
              a screen reader hears which reading is on. */}
          <div
            role="group"
            aria-label="Sort the queue"
            className="flex items-center gap-0.5 rounded-full bg-subtle/70 p-0.5"
          >
            {ATTENTION_SORTS.map((option) => (
              <button
                key={option.id}
                type="button"
                onClick={() => setSort(option.id)}
                aria-pressed={sort === option.id}
                className={`rounded-full px-2.5 py-1 text-xs font-semibold transition-colors duration-200 ease-out-cubic ${
                  sort === option.id
                    ? 'bg-raised text-ink shadow-warm'
                    : 'text-muted-strong hover:text-ink'
                }`}
              >
                {option.label}
              </button>
            ))}
          </div>

          <Link
            to="/seller/orders?tab=attention"
            className="text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
          >
            The whole queue
          </Link>
        </div>
      }
    >
      <ul className="divide-y divide-hairline-soft">
        {queue.map((row) => (
          <QueueRow key={row.order.id} row={row} />
        ))}
      </ul>

      {totalWaiting > queue.length && (
        <Link
          to="/seller/orders?tab=attention"
          className="mt-4 inline-flex items-center gap-1.5 text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
        >
          {totalWaiting - queue.length} more waiting
          <ArrowRight className="h-4 w-4" aria-hidden="true" />
        </Link>
      )}
    </SellerSection>
  )
}

/**
 * One order waiting on the maker, as a door into the order.
 *
 * The whole row is the link — the ref and the customer line are not two targets,
 * because a row where "waiting 67d" is dead text beside a live ref is a row a
 * thumb gets wrong. `waitingLabel` is bare (`67d`) and the row phrases it, since
 * the sort is the priority and the label only has to rank the rows against each
 * other.
 *
 * It also carries the pointer's own menu (`useContextMenu`), which is how an
 * order can be opened, or its reference copied into the chat with the customer,
 * without the four rows of a preview card growing a fifth control each. The menu
 * is added to the row's *link* rather than the `li`, so the handler sits on the
 * one element that already covers the row.
 */
function QueueRow({ row }) {
  const { order, waitingMs } = row
  const wait = waitingLabel(waitingMs)
  const to = orderRowPath(order)
  const { onContextMenu, menu } = useContextMenu({
    items: orderRowMenuItems(order),
    link: to,
    label: `Order ${shortOrderRef(order.id)}`,
  })

  return (
    <li>
      <Link
        to={to}
        onContextMenu={onContextMenu}
        className="-mx-2 grid grid-cols-[minmax(0,1fr)_auto] items-start gap-x-3 gap-y-2 rounded-field px-2 py-3 transition-colors duration-200 ease-out-cubic hover:bg-subtle/60 sm:gap-x-5"
      >
        <div className="min-w-0">
          <p className="num text-sm font-semibold text-ink">
            {shortOrderRef(order.id)}
          </p>
          <p className="mt-0.5 truncate text-xs text-muted">
            {order.customer_name} · {wait === 'just now' ? 'just arrived' : `waiting ${wait}`}
          </p>
        </div>

        <CountUp
          value={order.total_amount}
          format={formatCurrency}
          className="num col-start-2 row-start-1 text-right text-sm font-semibold text-ink"
        />

        <StatusPill
          status={order.status}
          className="col-start-1 row-start-2 justify-self-start"
        />
      </Link>
      {menu}
    </li>
  )
}
