import { useMemo, useState } from 'react'
import { Link, useOutletContext } from 'react-router-dom'
import { ClipboardList, Plus, Store } from 'lucide-react'

import StatusPill from '../../components/orders/StatusPill'
import SellerAttentionQueue from '../../components/seller/SellerAttentionQueue.jsx'
import SellerPeriodPills from '../../components/seller/SellerPeriodPills.jsx'
import SellerTrendChart from '../../components/seller/SellerTrendChart.jsx'
import {
  SellerFigure,
  SellerPageBody,
  SellerPageHeader,
  SellerSection,
} from '../../components/seller/SellerPage.jsx'
import {
  lowStockRowMenuItems,
  orderRowMenuItems,
  orderRowPath,
} from '../../components/seller/sellerRowMenus.js'
import { useContextMenu } from '../../components/ui/ContextMenu.jsx'
import CountUp from '../../components/ui/CountUp.jsx'
import EmptyState from '../../components/ui/EmptyState.jsx'
import Reveal from '../../components/ui/Reveal.jsx'
import { formatCurrency, formatCurrencyCompact, pluralize } from '../../lib/constants.js'
import { shortOrderRef } from '../../lib/orderRules.js'
import {
  dashboardTotals,
  lowStockRows,
  outOfStockRows,
  salesSummary,
  salesTrend,
  sellerPeriod,
  sortSellerOrders,
  statusBreakdown,
  storeCompleteness,
} from '../../lib/seller.js'
import { useSellerOrders, useSellerProducts } from '../../hooks/useSeller.js'

const RECENT_LIMIT = 6

/**
 * The seller's dashboard.
 *
 * Every figure on it is derived from the two queries the rest of the portal
 * already shares — orders and products — so opening this page costs no request
 * the seller is not about to make anyway, and no number here can disagree with
 * the list it came from.
 *
 * ## The page reads top to bottom as three questions
 *
 *   1. **What needs me, and how am I doing?** One row answering both: the queue
 *      on the right, the day's takings on the left. They share a row because
 *      they are one question at 8am, and because the queue is only *half* a
 *      dashboard on its own — "17 orders are blocked on you" lands differently
 *      beside "₱0 today" than under it. The queue is actionable rather than a
 *      sentence about itself: each row carries the single next step, so a maker
 *      no longer has to leave the page to understand the alarm.
 *   2. **How is the business going?** The window the seller picks — a week, a
 *      month or a quarter — as a chart plus the three readings a chart cannot
 *      give: what an order comes to, how many pairs left the workshop, and which
 *      pair is actually selling.
 *   3. **What is the state of the shop?** Columns below: **time** on the left
 *      (the window's sales, then the orders that just came in) and **state** on
 *      the right (where the order book sits, what is running out, what the
 *      storefront is still missing). Splitting by time and state rather than by
 *      size is what makes the left column readable as a sequence and the right
 *      column readable as a checklist.
 *
 * ## The period is state, not a URL parameter
 *
 * Every filter in this portal lives in the URL, and this one is the exception
 * for the reason the reports page's is: it is not a filter on a list, it is a
 * choice about how much of the same data to draw, and the page underneath is
 * identical at every setting. A pasted link that reopened somebody else's window
 * would be a setting, not a link.
 *
 * ## The first-run state
 *
 * A seller who has just been approved has no orders and no products, and the
 * full dashboard renders for them as four zeroes above four empty cards. That is
 * not a dashboard, it is a list of what they have not done, so they get one
 * panel that says what to do instead — and it disappears the moment there is
 * anything at all to report on.
 *
 * ## The title is the date
 *
 * It was a greeting — "Good evening, demo_storeName" — and a greeting is the one
 * thing every dashboard has and no dashboard needs: it takes the biggest type on
 * the page to say nothing the seller did not already know, and it is wrong for
 * anyone working past midnight. The date is the same shape of fact and is
 * *useful*: a seller who has not slept reads what day it is, and "orders today"
 * below it has something to be today relative to.
 *
 * ## One number leads, three support it, and the sizes say so
 *
 * `SellerFigure`'s arrangements are used as ranks here, not as styles: **Sales
 * today** is `hero` (60px, the accent) and stands alone, the three counts under
 * it are a `row` list (24px, one right edge), and the section headings below are
 * small caps. The support list is a *list* as well as a smaller one — label
 * left, figure right, an inset rule between them and a boundary rule above the
 * set — which is what makes "17 open orders" read as the state behind "₱0
 * today" rather than as a second headline.
 *
 * Every figure counts up when it arrives, which is the one animation here doing
 * work rather than decorating: the data lands after the first paint, so a count
 * is what tells the seller the page has finished filling in, and it is the only
 * cue that a refetched total has changed. `CountUp` fails open, so no figure is
 * ever a zero waiting for an animation that may not run.
 */
export default function SellerDashboard() {
  const { store } = useOutletContext()
  const storeId = store?.id ?? null

  const ordersQuery = useSellerOrders(storeId)
  const productsQuery = useSellerProducts(storeId)

  const [periodId, setPeriodId] = useState('7')
  const period = sellerPeriod(periodId)

  const orders = ordersQuery.data ?? []
  const products = productsQuery.data ?? []

  const totals = dashboardTotals(orders)
  const trend = useMemo(
    () => salesTrend(orders, { days: period.days }),
    [orders, period.days],
  )
  const summary = useMemo(
    () => salesSummary(orders, { days: period.days }),
    [orders, period.days],
  )

  const statuses = statusBreakdown(orders)
  const low = lowStockRows(products)
  const out = outOfStockRows(products)
  const completeness = storeCompleteness(store)
  const recent = sortSellerOrders(orders).slice(0, RECENT_LIMIT)

  const loading = ordersQuery.isLoading || productsQuery.isLoading
  const isFirstRun = !loading && orders.length === 0 && products.length === 0

  return (
    <SellerPageBody>
      <SellerPageHeader
        title={today()}
        description={
          loading
            ? 'Loading your workshop…'
            : `${pluralize(totals.orderCountToday, 'order')} today · ${totals.openCount} still open.`
        }
        actions={
          <>
            <Link to="/seller/orders" className="btn btn-outline">
              <ClipboardList className="h-4 w-4" aria-hidden="true" />
              Orders
            </Link>
            {/* One primary action per page, and this is the one that makes
                money: adding a pair beats re-reading the list. */}
            <Link to="/seller/products/new" className="btn btn-primary">
              <Plus className="h-4 w-4" aria-hidden="true" />
              New product
            </Link>
          </>
        }
      />

      {isFirstRun ? (
        <FirstRunPanel completeness={completeness} hasStore={Boolean(store)} />
      ) : (
        <>
          {/*
            One row, two readings of "where do I stand": the day's money on the
            left, the work on the right.

            The queue is first in the DOM and second on screen from `lg` up,
            which is the order a phone wants. A seller opening this on a phone is
            more often asking what needs them than what they have taken, and the
            swap costs the tab order nothing: the money panel is words, not
            controls, and the queue's rows all lead to the same place the list
            does.

            **The row is as tall as the taller card, and the money panel fills it.**
            Left to its own height it ended a third of the way down the queue and
            left a hole under it — the gap was not padding, it was the row. So the
            panel stretches and its own content is anchored at both ends: the
            figure at the top, the three readings on the bottom rule, which is the
            same rule the queue's last row sits above. The one card that must not
            stretch is the calm "nothing is blocked on you" strip, which asks for
            `self-start` itself.
          */}
          <div className="grid gap-5 lg:grid-cols-2">
            <SellerAttentionQueue orders={orders} loading={ordersQuery.isLoading} />

            {/*
              The hero stands alone as one big figure and the three readings sit
              under it behind a rule, stacked at every width. It used to lay the
              three out beside the hero from `lg` up, which stopped being right
              the moment this panel shared a row: half the page is not enough for
              a 60px total and a 240px column of captions next to it, and a hero
              that has to shrink to fit is not the figure the page is built
              around.
            */}
            <div className="flex flex-col rounded-premium border border-hairline bg-raised p-5 shadow-premium sm:p-7 lg:order-first">
              <div className="flex flex-1 flex-col gap-6">
                <SellerFigure
                  label="Sales today"
                  value={
                    <CountUp value={totals.salesToday} format={formatCurrencyCompact} />
                  }
                  tone="accent"
                  size="hero"
                  hint={
                    totals.unpaidToday > 0
                      ? `${totals.unpaidToday} of today's orders ${
                          totals.unpaidToday === 1 ? 'is' : 'are'
                        } unpaid · cancelled orders excluded.`
                      : 'Orders placed today · cancelled orders excluded.'
                  }
                />

                {/* The state behind the figure: label left, reading right, one
                    inset rule between them, and a boundary rule above the set.
                    `mt-auto` is what pins the set to the bottom of a stretched
                    panel — see the row's docblock. */}
                <div className="mt-auto flex flex-col divide-y divide-hairline-soft border-t border-hairline-soft pt-1">
                  <SellerFigure
                    layout="row"
                    className="py-2.5"
                    label="Waiting on you"
                    value={<CountUp value={totals.needsActionCount} />}
                    tone={totals.needsActionCount > 0 ? 'alert' : 'neutral'}
                  />
                  <SellerFigure
                    layout="row"
                    className="py-2.5"
                    label="Open orders"
                    value={<CountUp value={totals.openCount} />}
                  />
                  <SellerFigure
                    layout="row"
                    className="py-2.5"
                    label="Running out"
                    value={<CountUp value={low.length} />}
                    tone={low.length > 0 ? 'alert' : 'neutral'}
                  />
                </div>
              </div>
            </div>
          </div>

          {/* Tighter than the page's own rhythm (the body gaps its children by
              6). The columns are *groups of cards*, and cards inside a group
              belong to each other more closely than the groups belong to the
              page — which is the whole use of two different gaps. */}
          <div className="grid gap-5 lg:grid-cols-[1.4fr_1fr]">
            {/* ── Time: the window, then the orders that just landed. ── */}
            <div className="flex flex-col gap-5">
              {loading ? (
                <div className="shimmer h-72 rounded-premium" />
              ) : (
                <SellerSection
                  title="Sales"
                  description="What was ordered in the window, against the window before it."
                  actions={
                    <div className="flex flex-wrap items-center gap-3">
                      <SellerPeriodPills
                        value={period.id}
                        onChange={setPeriodId}
                        label="Sales window"
                      />
                      <Link
                        to="/seller/reports"
                        className="text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
                      >
                        Full report
                      </Link>
                    </div>
                  }
                >
                  <SellerTrendChart
                    trend={trend}
                    label={`Sales, last ${pluralize(period.days, 'day')}`}
                  />

                  {/*
                    The three readings the chart cannot give. `Sales` opens the
                    door to the money; these answer what a maker asks next, and
                    they re-derive from the same period pills above them — which
                    is why they count up like the rest of the page: switching
                    windows changes numbers that a silent re-render would change
                    invisibly.

                    The best seller is a *name*, so it is the one reading here
                    not set in the numeric face — `SellerFigure`'s figures are all
                    figures, and a product name in Sora would be a price
                    pretending to be a shoe. It keeps the same size, so the row
                    still reads as one line of three.
                  */}
                  <dl className="mt-6 grid gap-5 border-t border-hairline-soft pt-5 sm:grid-cols-3">
                    <Reading
                      label="Average order"
                      value={
                        <CountUp
                          value={summary.average}
                          format={formatCurrency}
                          className="num text-2xl font-semibold text-ink"
                        />
                      }
                      hint={`Across ${pluralize(summary.orderCount, 'order')}.`}
                    />
                    <Reading
                      label="Pairs sold"
                      value={
                        <CountUp
                          value={summary.pairs}
                          className="num text-2xl font-semibold text-ink"
                        />
                      }
                      hint="Counted from the lines on those orders."
                    />
                    <Reading
                      label="Best seller"
                      value={
                        <span className="block truncate text-2xl font-semibold text-ink">
                          {summary.topProduct ? summary.topProduct.name : '—'}
                        </span>
                      }
                      hint={
                        summary.topProduct
                          ? `${pluralize(summary.topProduct.pairs, 'pair')} — the pair to keep in stock.`
                          : 'Nothing sold in this window yet.'
                      }
                    />
                  </dl>
                </SellerSection>
              )}

              <Reveal>
                <SellerSection
                  title="Recent orders"
                  description="The newest orders against your storefront."
                  actions={
                    <Link
                      to="/seller/orders"
                      className="text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
                    >
                      See all
                    </Link>
                  }
                >
                  {ordersQuery.isLoading ? (
                    <div className="space-y-3">
                      {[0, 1, 2].map((key) => (
                        <div key={key} className="shimmer h-16 rounded-card" />
                      ))}
                    </div>
                  ) : recent.length === 0 ? (
                    <EmptyState
                      Icon={ClipboardList}
                      title="No orders yet"
                      description="When a customer buys from your storefront, the order lands here and on your phone at the same time."
                      className="py-10"
                    />
                  ) : (
                    /*
                      Two things per row: the order's own identity on the **very
                      left**, its money on the right. The ref and the customer
                      line are the first column; the status goes *under* them,
                      so the six refs, the six names and the six statuses all
                      start on one vertical line at the card's left edge, and the
                      six amounts all end on another at its right edge.

                      A status is not a column of numbers — it is part of what the
                      order *is*, and "Cancelled" belongs beside the order that
                      was cancelled rather than floating in the right margin where
                      its only alignment is with other statuses. Both remaining
                      edges line up by construction rather than by measurement:
                      the identity column is the `1fr`, the amount is the last
                      track and `text-right`, and `.num` keeps the figures tabular
                      so they do not shift as they count.
                    */
                    <ul className="divide-y divide-hairline-soft">
                      {recent.map((order) => (
                        <RecentOrderRow key={order.id} order={order} />
                      ))}
                    </ul>
                  )}
                </SellerSection>
              </Reveal>
            </div>

            {/* ── State: where the book sits, what is short, what is missing. ── */}
            <div className="flex flex-col gap-5">
              <Reveal delay={0.04}>
                <SellerSection
                  title="Where your orders are"
                  description="Every order on the book, by status."
                >
                  {ordersQuery.isLoading ? (
                    <div className="shimmer h-24 rounded-card" />
                  ) : statuses.length === 0 ? (
                    <p className="text-sm text-muted">No orders on the book right now.</p>
                  ) : (
                    /* Wraps rather than scrolls: a status mix is read at a glance,
                       and a strip that hides half of itself behind a scroll is the
                       one thing a mix is useless as. */
                    <ul className="flex flex-wrap gap-2">
                      {statuses.map((row) => (
                        <li key={row.status}>
                          {/* The chip is a door into the tab that actually holds
                              these orders (`tabForStatus`), not a link to the
                              unfiltered list — "3 cancelled" opening the same
                              page as every other chip teaches a seller the chips
                              do nothing. */}
                          <Link
                            to={`/seller/orders?tab=${row.tab}`}
                            aria-label={`${pluralize(row.count, 'order')} in this status — open the queue`}
                            className="inline-flex items-center gap-2 rounded-full bg-subtle/70 py-1 pl-1.5 pr-3 transition-colors duration-200 ease-out-cubic hover:bg-subtle"
                          >
                            <StatusPill status={row.status} />
                            <span
                              aria-hidden="true"
                              className="num text-sm font-semibold text-ink"
                            >
                              {row.count}
                            </span>
                          </Link>
                        </li>
                      ))}
                    </ul>
                  )}
                </SellerSection>
              </Reveal>

              <Reveal delay={0.06}>
                <SellerSection
                  title="Running out"
                  description={
                    out.length > 0
                      ? `Sizes with 5 pairs or fewer. ${pluralize(out.length, 'size')} already sold out — a different job, on the products page.`
                      : 'Sizes with 5 pairs or fewer — not the sold-out ones, which are a different job.'
                  }
                  actions={
                    out.length > 0 ? (
                      <Link
                        to="/seller/products"
                        className="text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
                      >
                        {pluralize(out.length, 'size')} sold out
                      </Link>
                    ) : null
                  }
                >
                  {productsQuery.isLoading ? (
                    <div className="shimmer h-24 rounded-card" />
                  ) : low.length === 0 ? (
                    <p className="text-sm text-muted">
                      Nothing is running low. Sizes that are already sold out are
                      on the products page.
                    </p>
                  ) : (
                    <ul className="divide-y divide-hairline-soft">
                      {low.slice(0, 6).map((row) => (
                        <LowStockRow key={`${row.productId}-${row.size}`} row={row} />
                      ))}
                    </ul>
                  )}
                  {low.length > 6 && (
                    <Link
                      to="/seller/products"
                      className="mt-4 inline-block text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
                    >
                      {low.length - 6} more
                    </Link>
                  )}
                </SellerSection>
              </Reveal>

              {/* The storefront checklist only appears while something is
                  missing. Once the store is complete it would be a card telling
                  a seller that nothing is wrong, which is a card worth deleting
                  rather than reading. */}
              {!completeness.complete && (
                <Reveal delay={0.08}>
                  <SellerSection
                    title="Finish your storefront"
                    description="Customers see these before they see your shoes."
                  >
                    <ul className="space-y-2.5">
                      {completeness.missing.map((item) => (
                        <li key={item} className="flex items-start gap-2.5 text-sm">
                          <span
                            aria-hidden="true"
                            className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-clay"
                          />
                          <span className="text-muted-strong">{item}</span>
                        </li>
                      ))}
                    </ul>
                    <Link
                      to="/seller/store"
                      className="mt-5 inline-flex items-center gap-1.5 text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
                    >
                      <Store className="h-4 w-4" aria-hidden="true" />
                      Edit the storefront
                    </Link>
                  </SellerSection>
                </Reveal>
              )}
            </div>
          </div>
        </>
      )}
    </SellerPageBody>
  )
}

/**
 * One reading beside a chart: a label, a figure, and the line that qualifies it.
 *
 * A `dt`/`dd` pair inside the dashboard's own `<dl>`, rather than a
 * `SellerMetric` card: three cards would be three more surfaces on a page that
 * already has nine, and they all report the *same window* as the chart directly
 * above them — which is a heading, not three boxes.
 */
function Reading({ label, value, hint }) {
  return (
    <div>
      <dt className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
        {label}
      </dt>
      <dd className="mt-2">{value}</dd>
      {hint && <p className="mt-1 text-xs leading-relaxed text-muted">{hint}</p>}
    </div>
  )
}

/**
 * One of the newest orders: the same row the orders page draws, at a smaller
 * size.
 *
 * It exists as a component rather than as markup inside the list's `map` for one
 * reason — it carries the pointer's own menu (`useContextMenu`), and a hook needs
 * a component to live in. The menu is the same `orderRowMenuItems` the orders page
 * and the queue use, so an order offers the same things wherever it is spotted: no
 * fifth control on a row that is mostly two lines of text.
 */
function RecentOrderRow({ order }) {
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
            {order.customer_name} · {formatDate(order.created_at)}
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

/**
 * One size that is nearly gone.
 *
 * The row is a link to the product rather than a number in a list: "3 left in EU
 * 40" is a job, and the page that does the job is one tap away — and right-click
 * is the shortcut for the two things a seller does with a low-stock line away from
 * the product page, which is copying the name to a restock list and opening it.
 */
function LowStockRow({ row }) {
  const to = `/seller/products/${row.productId}`
  const { onContextMenu, menu } = useContextMenu({
    items: lowStockRowMenuItems(row),
    link: to,
    label: `${row.name}, size ${row.size}`,
  })

  return (
    <li>
      <Link
        to={to}
        onContextMenu={onContextMenu}
        className="-mx-2 flex items-center justify-between gap-3 rounded-field px-2 py-2.5 transition-colors duration-200 ease-out-cubic hover:bg-subtle/60"
      >
        <span className="min-w-0">
          <span className="block truncate text-sm font-medium text-ink">
            {row.name}
          </span>
          <span className="block text-xs text-muted">Size {row.size}</span>
        </span>
        <span className="num shrink-0 text-sm font-semibold text-amber">
          {row.stock} left
        </span>
      </Link>
      {menu}
    </li>
  )
}

/**
 * What a brand-new seller sees instead of a dashboard full of zeroes.
 *
 * The single job of this panel is to name the next action. Everything a seller
 * needs to do to start trading is one of two things — put a pair on the shelf,
 * or fill in the storefront — so it offers exactly those two, and the checklist
 * only when there is something on it.
 */
function FirstRunPanel({ completeness, hasStore }) {
  return (
    <div className="overflow-hidden rounded-premium border border-hairline bg-raised shadow-premium">
      <div className="p-6 sm:p-8">
        <p className="overline">Getting started</p>
        <h2 className="mt-2 font-display text-2xl font-semibold text-ink">
          {hasStore
            ? 'Your storefront is set up — now put something on the shelf.'
            : 'Let’s get your shop trading.'}
        </h2>
        <p className="mt-3 max-w-2xl text-sm leading-relaxed text-muted">
          Nothing here yet, which is exactly what a new shop looks like. Two
          things stand between you and your first order: a pair for customers to
          buy, and a storefront they can find. Anything you list shows up on the
          storefront and in the CUFMAI app at the same time — there is no
          publishing step.
        </p>

        <div className="mt-7 flex flex-wrap gap-3">
          <Link to="/seller/products/new" className="btn btn-primary">
            <Plus className="h-4 w-4" aria-hidden="true" />
            Add your first product
          </Link>
          <Link to="/seller/store" className="btn btn-outline">
            <Store className="h-4 w-4" aria-hidden="true" />
            Finish the storefront
          </Link>
        </div>
      </div>

      {!completeness.complete && (
        <div className="border-t border-hairline-soft bg-subtle/60 px-6 py-5 sm:px-8">
          <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
            Still to do on your storefront
          </p>
          <ul className="mt-3 flex flex-wrap gap-x-6 gap-y-2">
            {completeness.missing.map((item) => (
              <li
                key={item}
                className="flex items-center gap-2 text-sm text-muted-strong"
              >
                <span
                  aria-hidden="true"
                  className="h-1.5 w-1.5 shrink-0 rounded-full bg-clay"
                />
                {item}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}

/**
 * The date, as the page's own title: "Wednesday, September 24".
 *
 * `en-PH`, which is the locale every other date on the portal is written in, and
 * a `now` parameter because the one thing this function does — ask the clock — is
 * exactly what makes it untestable and unrenderable anywhere but now.
 */
function today(now = new Date()) {
  return now.toLocaleDateString('en-PH', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  })
}

function formatDate(value) {
  if (!value) return '—'
  return new Date(value).toLocaleDateString('en-PH', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}
