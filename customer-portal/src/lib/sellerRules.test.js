import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  LOW_STOCK_THRESHOLD,
  PRODUCT_VIEWS,
  SELLER_ACCESS,
  TREND_WINDOW_DAYS,
  availableSellerOrderTabs,
  catalogSummary,
  dailyBuckets,
  dashboardTotals,
  filterSellerOrders,
  isApprovedSeller,
  lowStockRows,
  needsSellerAction,
  normalizeProductView,
  outOfStockRows,
  primarySellerAction,
  sellerAccess,
  sellerOrderActions,
  sellerOrderFee,
  sellerAccess as access,
  salesTrend,
  sortSellerOrders,
  statusBreakdown,
  statusWriteError,
  storeCompleteness,
  tabForStatus,
} from './sellerRules.js'

const profile = (over = {}) => ({
  role: 'customer',
  seller_status: 'none',
  ...over,
})

describe('sellerAccess', () => {
  it('admits an approved seller', () => {
    assert.equal(
      sellerAccess(profile({ role: 'seller', seller_status: 'approved' })),
      SELLER_ACCESS.APPROVED,
    )
    assert.equal(
      isApprovedSeller(profile({ role: 'seller', seller_status: 'approved' })),
      true,
    )
  })

  it('reports a pending application even on a customer row', () => {
    assert.equal(
      sellerAccess(profile({ role: 'customer', seller_status: 'pending' })),
      SELLER_ACCESS.PENDING,
    )
    assert.equal(
      isApprovedSeller(profile({ role: 'customer', seller_status: 'pending' })),
      false,
    )
  })

  it('reports a rejected application', () => {
    assert.equal(
      sellerAccess(profile({ seller_status: 'rejected' })),
      SELLER_ACCESS.REJECTED,
    )
  })

  it('does not admit a seller whose application is not approved', () => {
    // The row says seller; the lifecycle says otherwise. Showing this account a
    // dashboard would read as a broken account rather than an unfinished one.
    assert.equal(
      isApprovedSeller(profile({ role: 'seller', seller_status: 'pending' })),
      false,
    )
    assert.equal(
      isApprovedSeller(profile({ role: 'seller', seller_status: 'none' })),
      false,
    )
  })

  it('does not admit an admin, who has their own portal', () => {
    assert.equal(
      isApprovedSeller(profile({ role: 'admin', seller_status: 'approved' })),
      false,
    )
  })

  it('treats no profile as no access', () => {
    assert.equal(sellerAccess(null), SELLER_ACCESS.NONE)
    assert.equal(sellerAccess(undefined), SELLER_ACCESS.NONE)
  })

  it('is case-insensitive about the status column', () => {
    assert.equal(
      sellerAccess(profile({ role: 'seller', seller_status: 'Approved' })),
      SELLER_ACCESS.APPROVED,
    )
  })

  it('exposes one name per behaviour', () => {
    assert.equal(access, sellerAccess)
  })
})

describe('sellerOrderActions', () => {
  it('starts a pending order, collapsing placed into the same step', () => {
    assert.equal(primarySellerAction('pending').status, 'preparing')
    assert.equal(primarySellerAction('placed').status, 'preparing')
  })

  it('goes ready -> delivered, because receipt is the customer act', () => {
    // Part D: the seller hands the pair over and the order waits at `delivered`
    // until the buyer confirms. `seller_orders_screen.dart` still sends
    // `received` here and is the older of the two implementations.
    assert.equal(primarySellerAction('ready').status, 'delivered')
  })

  it('treats a cancellation request as a decision with two answers', () => {
    const actions = sellerOrderActions('cancellation_requested')
    assert.deepEqual(
      actions.map((action) => action.status),
      ['cancelled', 'preparing'],
    )
  })

  it('can restore a cancelled order, to placed rather than preparing', () => {
    const [restore] = sellerOrderActions('cancelled')
    assert.equal(restore.status, 'placed')
  })

  it('offers nothing to do on an order that has left the workshop', () => {
    for (const status of ['delivered', 'received']) {
      assert.deepEqual(sellerOrderActions(status), [])
      assert.equal(needsSellerAction(status), false)
    }
  })

  it('offers nothing while a payment is still the customer move', () => {
    for (const status of [
      'awaiting_payment',
      'awaiting_payment_confirmation',
      'payment_conflict',
    ]) {
      assert.deepEqual(sellerOrderActions(status), [])
    }
  })

  it('refuses to guess at a status it has not heard of', () => {
    // The CHECK has grown four times. Showing the order and refusing to move it
    // is the safe failure; inventing a transition is not.
    assert.deepEqual(sellerOrderActions('preparing_custom'), [])
    assert.deepEqual(sellerOrderActions(null), [])
    assert.deepEqual(sellerOrderActions(undefined), [])
  })

  it('never proposes a status the CHECK would reject', () => {
    const legal = new Set([
      'pending',
      'placed',
      'preparing',
      'ready',
      'delivered',
      'received',
      'cancelled',
      'cancellation_requested',
      'awaiting_payment',
      'payment_conflict',
      'awaiting_payment_confirmation',
    ])
    const statuses = [
      'pending',
      'placed',
      'preparing',
      'ready',
      'cancellation_requested',
      'cancelled',
    ]
    for (const status of statuses) {
      for (const action of sellerOrderActions(status)) {
        assert.ok(
          legal.has(action.status),
          `${status} -> ${action.status} is not a legal orders.status`,
        )
      }
    }
  })
})

describe('seller order tabs', () => {
  const orders = [
    { id: '1', status: 'placed' },
    { id: '2', status: 'preparing' },
    { id: '3', status: 'ready' },
    { id: '4', status: 'cancellation_requested' },
    { id: '5', status: 'received' },
    { id: '6', status: 'cancelled' },
  ]

  it('puts every order in exactly the tab it belongs to', () => {
    assert.equal(filterSellerOrders(orders, 'new').length, 1)
    assert.equal(filterSellerOrders(orders, 'progress').length, 1)
    assert.equal(filterSellerOrders(orders, 'ready').length, 1)
    assert.equal(filterSellerOrders(orders, 'attention').length, 1)
    assert.equal(filterSellerOrders(orders, 'done').length, 2)
    assert.equal(filterSellerOrders(orders, 'all').length, 6)
  })

  it('counts a tab from the same predicate that shows it', () => {
    for (const tab of availableSellerOrderTabs(orders)) {
      assert.equal(
        filterSellerOrders(orders, tab.id).length,
        orders.filter(tab.match).length,
      )
    }
  })

  it('drops a tab with nothing behind it', () => {
    const ids = availableSellerOrderTabs([{ id: '1', status: 'placed' }]).map(
      (tab) => tab.id,
    )
    assert.deepEqual(ids, ['all', 'new', 'attention'])
  })

  it('keeps Needs you when it is empty, because that is the good news', () => {
    const ids = availableSellerOrderTabs([{ id: '1', status: 'received' }]).map(
      (tab) => tab.id,
    )
    assert.ok(ids.includes('attention'))
  })

  it('falls back to all for a tab id that does not exist', () => {
    assert.equal(filterSellerOrders(orders, 'nonsense').length, 6)
  })

  it('sorts newest first', () => {
    const sorted = sortSellerOrders([
      { id: 'old', created_at: '2026-01-01T00:00:00Z' },
      { id: 'new', created_at: '2026-09-01T00:00:00Z' },
    ])
    assert.deepEqual(
      sorted.map((order) => order.id),
      ['new', 'old'],
    )
  })
})

describe('dashboardTotals', () => {
  const now = new Date('2026-09-26T10:00:00')

  const orders = [
    // Today, paid, still on the bench.
    { status: 'preparing', total_amount: 1200, payment_status: 'paid', created_at: '2026-09-26T08:00:00' },
    // Today, unpaid.
    { status: 'placed', total_amount: 800, payment_status: 'unpaid', created_at: '2026-09-26T09:00:00' },
    // Today but cancelled — not revenue.
    { status: 'cancelled', total_amount: 5000, payment_status: 'unpaid', created_at: '2026-09-26T07:00:00' },
    // Yesterday.
    { status: 'received', total_amount: 2000, payment_status: 'paid', created_at: '2026-09-25T08:00:00' },
  ]

  it("counts what was ordered today, not money banked today", () => {
    const totals = dashboardTotals(orders, { now })
    // preparing + placed. The cancelled one is not a sale.
    assert.equal(totals.orderCountToday, 2)
    assert.equal(totals.salesToday, 2000)
  })

  it('reports the unpaid today beside the figure rather than folding it in', () => {
    const totals = dashboardTotals(orders, { now })
    // The `placed` order. The cancelled one is excluded, not counted as unpaid.
    assert.equal(totals.unpaidToday, 1)
  })

  it('keeps a cancelled order out of the money', () => {
    const totals = dashboardTotals(orders, { now })
    // 1200 + 800 only; the 5000 cancelled order is excluded.
    assert.equal(totals.salesToday, 2000)
  })

  it('counts the whole open book, not just today', () => {
    const totals = dashboardTotals(orders, { now })
    // preparing + placed. Cancelled is finished and received is done.
    assert.equal(totals.openCount, 2)
  })

  it('counts the orders that are actually waiting on the maker', () => {
    const totals = dashboardTotals(orders, { now })
    // preparing and placed; received is done and cancelled is not an obligation.
    assert.equal(totals.needsActionCount, 2)
  })

  it('has open and needs-action mean different things', () => {
    // An order at `ready` is open — it is not finished — but nothing is
    // blocked on the maker, it is waiting for the buyer to collect.
    const ready = [
      { status: 'ready', total_amount: 100, created_at: '2026-09-26T08:00:00' },
    ]
    const totals = dashboardTotals(ready, { now })
    assert.equal(totals.openCount, 1)
    assert.equal(totals.needsActionCount, 1)

    const cancelled = [
      { status: 'cancelled', total_amount: 100, created_at: '2026-09-26T08:00:00' },
    ]
    const quiet = dashboardTotals(cancelled, { now })
    assert.equal(quiet.openCount, 0)
    assert.equal(quiet.needsActionCount, 0)
  })

  it('does not count a restorable cancellation as waiting on the maker', () => {
    assert.equal(needsSellerAction('cancelled'), false)
    // ...while still offering the restore itself.
    assert.equal(sellerOrderActions('cancelled').length, 1)
  })

  it('tallies every status, cancelled included', () => {
    const totals = dashboardTotals(orders, { now })
    assert.deepEqual(totals.byStatus, {
      preparing: 1,
      placed: 1,
      cancelled: 1,
      received: 1,
    })
  })

  it('survives an empty book and a missing timestamp', () => {
    assert.equal(dashboardTotals([], { now }).salesToday, 0)
    assert.equal(dashboardTotals(null, { now }).openCount, 0)

    const totals = dashboardTotals(
      [{ status: 'placed', total_amount: 100, created_at: null }],
      { now },
    )
    assert.equal(totals.orderCountToday, 0)
    assert.equal(totals.openCount, 1)
  })
})

describe('dailyBuckets', () => {
  const now = new Date('2026-09-26T10:00:00')
  const order = (createdAt, total, status = 'placed') => ({
    status,
    total_amount: total,
    created_at: createdAt,
  })

  it('returns one bucket per day, oldest first, including the empty ones', () => {
    const buckets = dailyBuckets([], { now, days: 7 })
    assert.equal(buckets.length, 7)
    assert.equal(buckets[0].date.getDate(), 20)
    assert.equal(buckets[6].date.getDate(), 26)
    assert.ok(buckets.every((bucket) => bucket.revenue === 0))
  })

  it('adds up a day rather than overwriting it', () => {
    const buckets = dailyBuckets(
      [
        order('2026-09-26T08:00:00', 100),
        order('2026-09-26T09:00:00', 250),
      ],
      { now, days: 7 },
    )
    const today = buckets[6]
    assert.equal(today.revenue, 350)
    assert.equal(today.orderCount, 2)
  })

  it('keeps a quiet day as an explicit zero rather than dropping it', () => {
    // A list of only the days that sold something draws a chart with no gaps,
    // so a quiet Tuesday disappears and the week reads as continuous trade.
    const buckets = dailyBuckets(
      [order('2026-09-20T08:00:00', 100), order('2026-09-26T08:00:00', 100)],
      { now, days: 7 },
    )
    assert.equal(buckets.length, 7)
    assert.equal(buckets.filter((bucket) => bucket.revenue === 0).length, 5)
  })

  it('marks today as projected, because the day is still running', () => {
    const buckets = dailyBuckets([], { now, days: 7 })
    assert.equal(buckets[6].isProjected, true)
    assert.equal(buckets[5].isProjected, false)
  })

  it('excludes a cancelled order from the money', () => {
    const buckets = dailyBuckets(
      [order('2026-09-26T08:00:00', 5000, 'cancelled')],
      { now, days: 7 },
    )
    assert.equal(buckets[6].revenue, 0)
    assert.equal(buckets[6].orderCount, 0)
  })

  it('ignores orders outside the window and orders with no date', () => {
    const buckets = dailyBuckets(
      [order('2026-01-01T08:00:00', 999), order(null, 999)],
      { now, days: 7 },
    )
    assert.equal(
      buckets.reduce((sum, bucket) => sum + bucket.revenue, 0),
      0,
    )
  })

  it('survives an empty or missing list', () => {
    assert.equal(dailyBuckets([], { now, days: 3 }).length, 3)
    assert.equal(dailyBuckets(null, { now, days: 3 }).length, 3)
  })
})

describe('salesTrend', () => {
  const now = new Date('2026-09-26T10:00:00')
  const order = (createdAt, total, status = 'placed') => ({
    status,
    total_amount: total,
    created_at: createdAt,
  })

  it('defaults to a week', () => {
    assert.equal(TREND_WINDOW_DAYS, 7)
    assert.equal(salesTrend([], { now }).points.length, 7)
  })

  it('compares against the same length of time immediately before', () => {
    const trend = salesTrend(
      [
        // this window: 19th–26th
        order('2026-09-26T08:00:00', 300),
        // the window before it: 12th–19th
        order('2026-09-13T08:00:00', 200),
        // outside both windows entirely
        order('2026-08-01T08:00:00', 9999),
      ],
      { now, days: 7 },
    )

    assert.equal(trend.total, 300)
    assert.equal(trend.previousTotal, 200)
    assert.equal(trend.percentChange, 50)
    assert.equal(trend.hasComparison, true)
  })

  it('refuses to invent a percentage when there is nothing to compare to', () => {
    // The first week a store ever trades: "+∞%" is nonsense and "0% growth"
    // is a lie, so the caller is told it cannot compare rather than given a
    // number that is always wrong.
    const trend = salesTrend([order('2026-09-26T08:00:00', 300)], { now })
    assert.equal(trend.previousTotal, 0)
    assert.equal(trend.hasComparison, false)
    assert.equal(trend.percentChange, 0)
  })

  it('reports a fall as a negative change, not an absolute one', () => {
    const trend = salesTrend(
      [
        order('2026-09-26T08:00:00', 100),
        order('2026-09-13T08:00:00', 400),
      ],
      { now },
    )
    assert.equal(trend.percentChange, -75)
  })

  it('knows when every day is empty, so no chart is drawn', () => {
    assert.equal(salesTrend([], { now }).isEmpty, true)
    assert.equal(
      salesTrend([order('2026-09-26T08:00:00', 1)], { now }).isEmpty,
      false,
    )
  })

  it('leaves a cancelled order out of both windows', () => {
    const trend = salesTrend(
      [order('2026-09-26T08:00:00', 5000, 'cancelled')],
      { now },
    )
    assert.equal(trend.total, 0)
    assert.equal(trend.isEmpty, true)
  })
})

describe('statusBreakdown', () => {
  it('orders the statuses the way a maker works them, not alphabetically', () => {
    const rows = statusBreakdown([
      { status: 'ready' },
      { status: 'cancelled' },
      { status: 'placed' },
      { status: 'preparing' },
    ])
    assert.deepEqual(
      rows.map((row) => row.status),
      ['placed', 'preparing', 'ready', 'cancelled'],
    )
  })

  it('counts repeats and says which tab each status lives under', () => {
    const rows = statusBreakdown([
      { status: 'preparing' },
      { status: 'preparing' },
      { status: 'placed' },
    ])
    assert.deepEqual(rows, [
      { status: 'placed', count: 1, tab: 'new' },
      { status: 'preparing', count: 2, tab: 'progress' },
    ])
  })

  it('tallies every order, cancelled included', () => {
    const rows = statusBreakdown([
      { status: 'cancelled' },
      { status: 'cancelled' },
    ])
    assert.deepEqual(rows, [
      { status: 'cancelled', count: 2, tab: 'done' },
    ])
  })

  it('sends every status to a tab that actually shows it', () => {
    // A chip that opens a tab the order is not in teaches a seller the chips
    // do nothing, so the mapping has to agree with the tab predicates.
    for (const status of [
      'pending',
      'placed',
      'preparing',
      'ready',
      'delivered',
      'received',
      'cancelled',
      'cancellation_requested',
      'awaiting_payment',
      'awaiting_payment_confirmation',
      'payment_conflict',
    ]) {
      const tab = tabForStatus(status)
      const shown = filterSellerOrders([{ status }], tab)
      assert.equal(shown.length, 1, `${status} -> ${tab} does not show the order`)
    }
  })

  it('opens the whole queue for a status it has not heard of', () => {
    // Not a tab that would show nothing: an empty list reads as "none of
    // these", and the order is right there.
    assert.equal(tabForStatus('preparing_custom'), 'all')
    assert.equal(tabForStatus(null), 'all')
  })

  it('puts a status it has not heard of last, visibly', () => {
    // The CHECK has grown four times; an unknown value that vanishes from the
    // tally is worse than one labelled oddly.
    const rows = statusBreakdown([
      { status: 'preparing_custom' },
      { status: 'placed' },
    ])
    assert.deepEqual(
      rows.map((row) => row.status),
      ['placed', 'preparing_custom'],
    )
  })

  it('is empty for no orders', () => {
    assert.deepEqual(statusBreakdown([]), [])
    assert.deepEqual(statusBreakdown(null), [])
  })
})

describe('lowStockRows', () => {
  const products = [
    {
      id: 'p1',
      name: 'Barong Slip-on',
      inventory: [
        { size: '40', stock: 3 },
        { size: '41', stock: 0 },
        { size: '42', stock: 9 },
        { size: '43', stock: 5 },
      ],
    },
    { id: 'p2', name: 'No inventory rows' },
  ]

  it("excludes zero, which is a different problem with a different fix", () => {
    const rows = lowStockRows(products)
    assert.deepEqual(
      rows.map((row) => `${row.name}|${row.size}|${row.stock}`),
      ['Barong Slip-on|40|3', 'Barong Slip-on|43|5'],
    )
  })

  it('includes the threshold itself, matching the app', () => {
    assert.equal(LOW_STOCK_THRESHOLD, 5)
    assert.ok(lowStockRows(products).some((row) => row.stock === 5))
  })

  it('lists the worst first', () => {
    const rows = lowStockRows([
      { id: 'p', name: 'x', inventory: [{ size: '40', stock: 4 }, { size: '41', stock: 1 }] },
    ])
    assert.deepEqual(rows.map((row) => row.stock), [1, 4])
  })

  it('honours an explicit threshold', () => {
    assert.equal(lowStockRows(products, { threshold: 3 }).length, 1)
  })

  it('sorts the sold-out rows into their own list', () => {
    const rows = outOfStockRows(products)
    assert.deepEqual(
      rows.map((row) => `${row.name}|${row.size}`),
      ['Barong Slip-on|41'],
    )
  })

  it('handles a product with no inventory rows', () => {
    assert.deepEqual(lowStockRows([{ id: 'p', name: 'x' }]), [])
    assert.deepEqual(lowStockRows(null), [])
  })
})

describe('catalogSummary', () => {
  const products = [
    {
      id: 'p1',
      name: 'Barong Slip-on',
      is_published: true,
      inventory: [
        { size: 'EU 40', stock: 3 },
        { size: 'EU 41', stock: 0 },
        { size: 'EU 42', stock: 9 },
      ],
    },
    {
      id: 'p2',
      name: 'Draft sandal',
      is_published: false,
      inventory: [{ size: 'EU 39', stock: 2 }],
    },
    { id: 'p3', name: 'No sizes', is_published: true },
  ]

  it('counts the catalogue, published and hidden', () => {
    const summary = catalogSummary(products)
    assert.equal(summary.total, 3)
    assert.equal(summary.published, 2)
    assert.equal(summary.hidden, 1)
  })

  it('counts stock problems per SIZE, with the product counts beside them', () => {
    // Two sizes are in trouble across two products: EU 41 at zero, EU 39 at 2.
    const summary = catalogSummary(products)
    assert.equal(summary.outSizes, 1)
    assert.equal(summary.lowSizes, 2)
    assert.equal(summary.outProducts, 1)
    assert.equal(summary.lowProducts, 2)
  })

  it('counts every size of one product separately, which is the fix', () => {
    // Three low sizes of ONE shoe is one restock, not three products to look
    // for — the figures have to be able to say both.
    const summary = catalogSummary([
      {
        id: 'p',
        name: 'One shoe',
        is_published: true,
        inventory: [
          { size: 'EU 40', stock: 1 },
          { size: 'EU 41', stock: 2 },
          { size: 'EU 42', stock: 3 },
        ],
      },
    ])
    assert.equal(summary.lowSizes, 3)
    assert.equal(summary.lowProducts, 1)
  })

  it('adds up the pairs on the shelf', () => {
    assert.equal(catalogSummary(products).pairs, 14)
  })

  it('is a rearrangement of nothing when there are no products', () => {
    assert.deepEqual(catalogSummary(null), {
      total: 0,
      published: 0,
      hidden: 0,
      lowSizes: 0,
      lowProducts: 0,
      outSizes: 0,
      outProducts: 0,
      pairs: 0,
    })
  })
})

describe('normalizeProductView', () => {
  it('keeps either real view', () => {
    assert.equal(normalizeProductView('grid'), 'grid')
    assert.equal(normalizeProductView('list'), 'list')
  })

  it('is case- and whitespace-tolerant, because localStorage writes it', () => {
    assert.equal(normalizeProductView(' LIST '), 'list')
  })

  it('falls back to the grid rather than to a page with nothing on it', () => {
    // The value comes out of storage, which a previous release, another tab or
    // devtools can have written. `tiles` must not mean an empty catalogue.
    for (const value of [undefined, null, '', 'tiles', 'table', 7, {}]) {
      assert.equal(normalizeProductView(value), 'grid')
    }
    assert.deepEqual(PRODUCT_VIEWS, ['grid', 'list'])
  })
})

describe('storeCompleteness', () => {
  it('names what is missing, one line each', () => {
    const result = storeCompleteness({
      tagline: 'Handmade since 1998',
      location: 'Carcar City, Cebu',
    })
    assert.equal(result.hasStore, true)
    assert.equal(result.complete, false)
    assert.deepEqual(result.missing, [
      'Write your workshop description',
      'Upload a logo',
      'Add a storefront photo',
    ])
  })

  it('treats whitespace as missing rather than as content', () => {
    const result = storeCompleteness({
      tagline: '   ',
      description: 'Real words',
      location: 'Carcar City, Cebu',
      logo_url: 'a.png',
      banner_url: 'b.jpg',
    })
    assert.deepEqual(result.missing, ['Add a tagline'])
  })

  it('is complete when nothing is missing', () => {
    const result = storeCompleteness({
      tagline: 't',
      description: 'd',
      location: 'Carcar City, Cebu',
      logo_url: 'a.png',
      banner_url: 'b.jpg',
    })
    assert.equal(result.complete, true)
    assert.deepEqual(result.missing, [])
  })

  it('asks for a store when there is none', () => {
    assert.equal(storeCompleteness(null).hasStore, false)
    assert.equal(storeCompleteness(null).complete, false)
  })
})

describe('sellerOrderFee', () => {
  it('derives the fee as total minus the lines', () => {
    const order = {
      total_amount: 1300,
      order_items: [{ unit_price: 600, quantity: 2 }],
    }
    assert.equal(sellerOrderFee(order), 100)
  })

  it('clamps a negative fee at zero rather than printing a negative', () => {
    // A voucher, or a sale that started between the snapshot and the charge.
    const order = {
      total_amount: 1000,
      order_items: [{ unit_price: 600, quantity: 2 }],
    }
    assert.equal(sellerOrderFee(order), 0)
  })

  it('treats an order with no line rows as all fee-free', () => {
    assert.equal(sellerOrderFee({ total_amount: 900 }), 900)
    assert.equal(sellerOrderFee(null), 0)
  })
})

describe('statusWriteError', () => {
  it('explains an empty result as a refusal, not a missing order', () => {
    // RLS does not raise on an UPDATE: PostgREST answers 200 with []. Asking
    // for the row back is what turns that into something we can see.
    const result = statusWriteError({ message: 'JSON object requested, multiple (or no) rows returned' })
    assert.equal(result.code, 'no-rows')
    assert.match(result.message, /refused/)
  })

  it('passes a real server message through', () => {
    const result = statusWriteError({
      message: 'new row for relation "orders" violates check constraint',
      code: '23514',
    })
    assert.equal(result.code, '23514')
    assert.match(result.message, /check constraint/)
  })
})
