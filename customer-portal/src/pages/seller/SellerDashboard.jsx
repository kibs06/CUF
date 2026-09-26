import { Link, useOutletContext } from 'react-router-dom'
import {
  ArrowRight,
  CircleAlert,
  ClipboardList,
  Package,
  Plus,
  Store,
} from 'lucide-react'

import StatusPill from '../../components/orders/StatusPill'
import SellerTrendChart from '../../components/seller/SellerTrendChart.jsx'
import {
  SellerFigure,
  SellerPageBody,
  SellerPageHeader,
  SellerSection,
} from '../../components/seller/SellerPage.jsx'
import EmptyState from '../../components/ui/EmptyState.jsx'
import CountUp from '../../components/ui/CountUp.jsx'
import { formatCurrency, formatCurrencyCompact } from '../../lib/constants.js'
import { shortOrderRef } from '../../lib/orderRules.js'
import {
  dashboardTotals,
  lowStockRows,
  outOfStockRows,
  salesTrend,
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
 *   1. **Is anything on fire?** The alert strip, and only when it is. It is the
 *      first thing on the page because an order nobody started is the one thing
 *      that costs a seller money while they read.
 *   2. **How am I doing?** Four figures, then the week as a chart. The figures
 *      are what a maker quotes; the chart is what tells them whether the week is
 *      going well, and a summary line cannot carry a shape.
 *   3. **What is the state of the shop?** Columns below: **time** on the left
 *      (the week's trend, then the orders that just came in) and **state** on the
 *      right (where the order book sits, what is running out, what the storefront
 *      is still missing). Splitting by time and state rather than by size is
 *      what makes the left column readable as a sequence and the right column
 *      readable as a checklist.
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
 * below it has something to be today relative to. The three-way split by hour
 * went with it, so nothing on this page has to know what time it is.
 *
 * ## One number leads, three support it, and the sizes say so
 *
 * `SellerFigure`'s three arrangements are used as three ranks here, not as three
 * styles: **Sales today** is `hero` (60px, the accent) and stands alone, the three
 * counts beside it are a `row` list (24px, one right edge) rather than three more
 * figure stacks, and the section headings below are small caps. Before, the hero
 * was 60px next to three 30px figures — a 2× step between a number and the numbers
 * it is made of, which read as four readings of the same kind in a row, with the
 * eye left to guess where to start.
 *
 * The support column is a *list* as well as a smaller one: label left, figure
 * right, an inset rule between them and a boundary rule against the hero that
 * turns vertical at `lg`. That is what makes "17 open orders" read as the state
 * behind "₱0 today" rather than as a second headline.
 */
export default function SellerDashboard() {
  const { store } = useOutletContext()
  const storeId = store?.id ?? null

  const ordersQuery = useSellerOrders(storeId)
  const productsQuery = useSellerProducts(storeId)

  const orders = ordersQuery.data ?? []
  const products = productsQuery.data ?? []

  const totals = dashboardTotals(orders)
  const trend = salesTrend(orders)
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
            : `${totals.orderCountToday} ${
                totals.orderCountToday === 1 ? 'order' : 'orders'
              } today · ${totals.openCount} still open.`
        }
        actions={
          <>
            <Link to="/seller/orders" className="btn btn-outline">
              <ClipboardList className="h-4 w-4" aria-hidden="true" />
              Orders
            </Link>
            <Link to="/seller/products" className="btn btn-primary">
              <Package className="h-4 w-4" aria-hidden="true" />
              Products
            </Link>
          </>
        }
      />

      {isFirstRun ? (
        <FirstRunPanel completeness={completeness} hasStore={Boolean(store)} />
      ) : (
        <>
          {/*
            The alert strip exists only when there is something to act on. A
            permanent "0 orders need you" banner teaches the seller to ignore the
            space, which is the opposite of what it is for.
          */}
          {totals.needsActionCount > 0 && (
            <div className="flex flex-wrap items-center gap-3 rounded-card border border-amber/30 bg-amber/[0.10] px-5 py-4">
              <CircleAlert
                className="h-5 w-5 shrink-0 text-amber"
                aria-hidden="true"
              />
              <p className="flex-1 text-sm text-ink">
                <span className="font-semibold">
                  {totals.needsActionCount}{' '}
                  {totals.needsActionCount === 1 ? 'order is' : 'orders are'}
                </span>{' '}
                waiting on you — to be started, marked ready, or handed over.
              </p>
              <Link
                to="/seller/orders?tab=attention"
                className="inline-flex items-center gap-1.5 text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
              >
                Open the queue
                <ArrowRight className="h-4 w-4" aria-hidden="true" />
              </Link>
            </div>
          )}

          {/*
            The figures, with the hierarchy in the sizes.

            **Money is the hero** and the three counts are the state that produced
            it — and the arrangement says so rather than leaving it to size alone.
            `formatCurrencyCompact` for the hero specifically: cents are noise at
            60px, and it is the helper's documented purpose (`formatCurrency` stays
            on every line item, where the exact amount is the point).

            The three support the hero without repeating it, which is why they are
            `row` and not three more stacks: a label and a figure against one right
            edge reads as *a list of the shop's state*, where three stacks read as
            three more headline numbers. They carry no hints either — the label is
            the whole sentence ("Running out", "Waiting on you"), and the card below
            each of them already explains itself, so a hint repeated in two places
            is how the two start disagreeing.

            The padding is deliberately tighter than the cards below it (`p-5`
            against their `p-5` *plus* a header), because this panel is one reading
            and three figures rather than a section with a body — and the boundary
            between the two halves is a rule that turns from horizontal to vertical
            at `lg`, which is the gap that needed highlighting.

            Every figure counts up when it arrives. That is the one animation here
            that is doing work rather than decorating: the data lands after the
            first paint, so a count is what tells the seller the page has finished
            filling in — and it is the only cue that a refetched total has changed.
            `CountUp` fails open (see its docblock), so the number is never a zero
            waiting for an animation that may not run, and each figure is formatted
            by the same helper it would have been formatted by anyway.
          */}
          {/* `mt-1` on top of the body's `gap-6`: the page's own rhythm already
              separates its blocks, and the hero gets a little more than that — the
              one panel whose whole job is to be looked at first. */}
          <div className="mt-1 rounded-premium border border-hairline bg-raised p-5 shadow-premium sm:p-7">
            <div className="flex flex-col gap-6 lg:flex-row lg:items-center lg:gap-10">
              <SellerFigure
                label="Sales today"
                value={
                  <CountUp
                    value={totals.salesToday}
                    format={formatCurrencyCompact}
                  />
                }
                tone="accent"
                size="hero"
                className="lg:flex-1"
                hint={
                  totals.unpaidToday > 0
                    ? `${totals.unpaidToday} of today's orders ${
                        totals.unpaidToday === 1 ? 'is' : 'are'
                      } unpaid · cancelled orders excluded.`
                    : 'Orders placed today · cancelled orders excluded.'
                }
              />

              {/*
                The supporting readings, and the boundary that separates the two
                halves of this panel: a top rule while they sit under the hero,
                and a left rule once they sit beside it.
              */}
              <div className="flex flex-col divide-y divide-hairline-soft border-t border-hairline-soft pt-1 lg:min-w-[15rem] lg:border-l lg:border-t-0 lg:pl-10 lg:pt-0">
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

          {/*
            Tighter than the page's own rhythm (the body gaps its children by 6).
            The columns are *groups of cards*, and cards inside a group belong to
            each other more closely than the groups belong to the page — which is
            the whole use of two different gaps.
          */}
          <div className="grid gap-5 lg:grid-cols-[1.4fr_1fr]">
            {/* ── Time: the week, then the orders that just landed. ── */}
            <div className="flex flex-col gap-5">
              {loading ? (
                <div className="shimmer h-64 rounded-premium" />
              ) : (
                <SellerSection
                  title="This week"
                  description="What was ordered in the last seven days."
                  actions={
                    <Link
                      to="/seller/reports"
                      className="text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
                    >
                      Full report
                    </Link>
                  }
                >
                  <SellerTrendChart trend={trend} />
                </SellerSection>
              )}

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
                    left**, its money on the right.

                    The ref and the customer line are the first column; the
                    status goes *under* them, and the amount sits alone on the
                    right. So the six refs, the six names and the six statuses
                    all start on one vertical line at the card's left edge, and
                    the six amounts all end on another at its right edge.

                    ## Why the status went there, and not in a column of its own

                    It was a third column on the right, and it takes two forms
                    to learn the same lesson. Left to its own width, a pill's
                    size pushed its amount sideways, so six rows of "₱ amount +
                    pill" read as six ragged lines. Given a fixed track, the
                    pills still could not sit still: the labels differ by 100px
                    (measured, Sora loaded — `Ready` is 74px, `Needs review`
                    116, `Cancellation requested` 173.9), so lining **both**
                    edges up means a 176px capsule around a 74px word, which is
                    140px of empty ring on the common statuses.

                    The reason it is the wrong question is that a status is not
                    a column of numbers — it is part of **what the order is**.
                    "Cancelled" belongs beside the order that was cancelled, not
                    floating in the right-hand margin where its only alignment
                    is with other statuses. Put it under the ref and the
                    alignment it needs is free: every pill starts where every
                    ref starts, and no label has to be padded to fit a track.

                    Both remaining edges still line up by construction rather
                    than by measurement — the identity column is the `1fr`, the
                    amount is the last track and `text-right`, so the money ends
                    on the row's own right edge whatever its length, and `.num`
                    keeps the figures tabular so they do not shift as they
                    count. `items-start` keeps an amount on the ref's line rather
                    than the middle of a taller row.

                    The amounts count, for the reason the hero counts: the rows
                    land *after* the first paint, and figures that arrive
                    motionless under a total that just counted read as two kinds
                    of number. Each amount's length sets its own pace
                    (`lib/countUpRules.js`) and `CountUp` fails open, so a row
                    is never a `₱0.00` waiting for an animation.
                  */
                  <ul className="divide-y divide-hairline-soft">
                    {recent.map((order) => (
                      <li key={order.id}>
                        <Link
                          to={`/seller/orders/${order.id}`}
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
                          {/* Col 1, row 2: the same left edge as the ref above
                              it, which is the whole point of the move. */}
                          <StatusPill
                            status={order.status}
                            className="col-start-1 row-start-2 justify-self-start"
                          />
                        </Link>
                      </li>
                    ))}
                  </ul>
                )}
              </SellerSection>
            </div>

            {/* ── State: where the book sits, what is short, what is missing. ── */}
            <div className="flex flex-col gap-5">
              <SellerSection
                title="Where your orders are"
                description="Every order on the book, by status."
              >
                {ordersQuery.isLoading ? (
                  <div className="shimmer h-24 rounded-card" />
                ) : statuses.length === 0 ? (
                  <p className="text-sm text-muted">
                    No orders on the book right now.
                  </p>
                ) : (
                  /* Wraps rather than scrolls: a status mix is read at a glance,
                     and a strip that hides half of itself behind a scroll is the
                     one thing a mix is useless as. */
                  <ul className="flex flex-wrap gap-2">
                    {statuses.map((row) => (
                      <li key={row.status}>
                        {/*
                          The chip is a door into the tab that actually holds
                          these orders (`tabForStatus`), not a link to the
                          unfiltered list — "3 cancelled" opening the same page
                          as every other chip teaches a seller the chips do
                          nothing.
                        */}
                        <Link
                          to={`/seller/orders?tab=${row.tab}`}
                          aria-label={`${row.count} ${
                            row.count === 1 ? 'order' : 'orders'
                          } in this status — open the queue`}
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

              <SellerSection
                title="Running out"
                description={
                  out.length > 0
                    ? `Sizes with 5 pairs or fewer. ${out.length} more ${
                        out.length === 1 ? 'size is' : 'sizes are'
                      } already sold out — a different job, on the products page.`
                    : 'Sizes with 5 pairs or fewer — not the sold-out ones, which are a different job.'
                }
              >
                {productsQuery.isLoading ? (
                  <div className="shimmer h-24 rounded-card" />
                ) : low.length === 0 ? (
                  <p className="text-sm text-muted">
                    Nothing is running low. Sizes that are already sold out are on
                    the products page.
                  </p>
                ) : (
                  <ul className="divide-y divide-hairline-soft">
                    {low.slice(0, 6).map((row) => (
                      <li
                        key={`${row.productId}-${row.size}`}
                        className="flex items-center justify-between gap-3 py-2.5 first:pt-0"
                      >
                        <div className="min-w-0">
                          <p className="truncate text-sm font-medium text-ink">
                            {row.name}
                          </p>
                          <p className="text-xs text-muted">Size {row.size}</p>
                        </div>
                        <span className="num shrink-0 text-sm font-semibold text-amber">
                          {row.stock} left
                        </span>
                      </li>
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

              {/*
                The storefront checklist only appears while something is missing.
                Once the store is complete it would be a card telling a seller
                that nothing is wrong, which is a card worth deleting rather than
                reading.
              */}
              {!completeness.complete && (
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
              )}
            </div>
          </div>
        </>
      )}
    </SellerPageBody>
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
