/**
 * Seller rules — the pure half of the seller portal.
 *
 * Kept free of the Supabase client for the same reason `orderRules.js` and
 * `cartRules.js` are: everything here is a status, a count or a permission, and
 * those are the parts that must be provable without a network.
 *
 * Nothing below is invented. Each rule is copied from the piece it has to agree
 * with, because the seller portal and the seller's phone write to the SAME rows
 * and a dashboard that disagrees with the app about what "today's sales" means
 * is worse than no dashboard:
 *
 *   sellerAccess              `auth_gate.dart` — role + seller_status, in the
 *                             app's own order of checks
 *   sellerOrderActions        `order_detail_screen.dart`'s `_nextStatus` and
 *                             `_actionLabel`, plus the seller side of
 *                             `cancellation_requested` from
 *                             `MY_ORDERS_ARCHITECTURE.md`
 *   LOW_STOCK_THRESHOLD       `SellerInventoryRow.lowStockThreshold`
 *   lowStockRows              `SellerDashboardScreen._getLowStockItems`, whose
 *                             boundary is deliberate and is kept (see below)
 *   dashboardTotals           `SalesService`'s notion of what counts
 *   dailyBuckets / salesTrend `SalesTrendResult` — the app's trend shape, and
 *                             its comparison against the window before it
 *   statusBreakdown           the status tallies `dashboardTotals` already
 *                             computed and nothing displayed
 */

/**
 * Where an account sits in the seller lifecycle.
 *
 * `auth_gate.dart` checks these in exactly this order and the order matters:
 * a `rejected` seller falls through to the customer shell there, and a
 * `pending` one gets the waiting screen. Approved-ness is what gates the seller
 * UI, not the role alone — a `seller` row with `seller_status = 'pending'` has
 * applied but is not allowed to sell yet, and showing them an empty dashboard
 * would read as a broken account rather than an unfinished application.
 */
export const SELLER_ACCESS = {
  APPROVED: 'approved',
  PENDING: 'pending',
  REJECTED: 'rejected',
  NONE: 'none',
}

/**
 * What this profile may do on `/seller`.
 *
 * `admin` is deliberately NOT an approved seller here even though every RLS
 * policy on these tables admits one (`is_seller_or_admin()`). Admin has its own
 * portal, with its own gate and its own sign-in, and letting an admin session
 * browse into the seller shell would make the two portals two doors into the
 * same room — including through the seller screens that assume a single
 * `owner_id` and would show an admin an empty store.
 */
export function sellerAccess(profile) {
  if (!profile) return SELLER_ACCESS.NONE

  const status = String(profile.seller_status ?? 'none').toLowerCase()

  // The application lifecycle is reported even to a customer row: a customer
  // who applied through the app's seller flow and was approved has
  // `seller_status = 'approved'` before their `role` catches up, and hiding
  // that would strand them.
  if (status === SELLER_ACCESS.PENDING) return SELLER_ACCESS.PENDING
  if (status === SELLER_ACCESS.REJECTED) return SELLER_ACCESS.REJECTED

  if (profile.role === 'seller' && status === SELLER_ACCESS.APPROVED) {
    return SELLER_ACCESS.APPROVED
  }

  return SELLER_ACCESS.NONE
}

export function isApprovedSeller(profile) {
  return sellerAccess(profile) === SELLER_ACCESS.APPROVED
}

/**
 * The one thing a seller can do to an order at each status.
 *
 * Ported from `order_detail_screen.dart`, including the parts that look like
 * dead ends and are not:
 *
 *  - **`pending` and `placed` are the same step.** Both are "we have not
 *    started", and the app sends `confirmed`, which `SupabaseService.
 *    _mapUiStatusToDb` translates to `preparing`. The translation is folded in
 *    here so the portal stores the DB value directly — one hop fewer to be
 *    wrong about.
 *  - **`ready → delivered`, not `ready → received`.** Part D made receipt the
 *    CUSTOMER's act: the seller hands the pair over and the order sits at
 *    `delivered` until the buyer confirms. `seller_orders_screen.dart` still
 *    sends `received` here and is the older of the two.
 *  - **`cancellation_requested` is a decision, not a step.** The customer's
 *    cancel of a `preparing` order does not cancel it — it asks. Approving is
 *    `cancelled`; declining puts the order back on the bench at `preparing`.
 *  - **`cancelled` can be restored**, because a mis-tap on a phone is the way
 *    orders get cancelled by accident. Restoring lands on `placed` (the app's
 *    own target), which is "not started" without rewriting history to say the
 *    order was never placed.
 *  - **`delivered` and `received` have no action — waiting is the state.** The
 *    order is out of the maker's hands, and a button that does nothing would be
 *    worse than the honest absence of one.
 */
const SELLER_ORDER_ACTIONS = {
  pending: [{ id: 'prepare', label: 'Start preparing', status: 'preparing', tone: 'primary' }],
  placed: [{ id: 'prepare', label: 'Start preparing', status: 'preparing', tone: 'primary' }],
  preparing: [{ id: 'ready', label: 'Mark ready', status: 'ready', tone: 'primary' }],
  ready: [{ id: 'deliver', label: 'Mark delivered', status: 'delivered', tone: 'primary' }],
  cancellation_requested: [
    { id: 'approve-cancel', label: 'Approve cancellation', status: 'cancelled', tone: 'danger' },
    { id: 'decline-cancel', label: 'Keep the order', status: 'preparing', tone: 'outline' },
  ],
  cancelled: [{ id: 'restore', label: 'Restore order', status: 'placed', tone: 'outline' }],
  delivered: [],
  received: [],
  awaiting_payment: [],
  awaiting_payment_confirmation: [],
  payment_conflict: [],
}

/**
 * The actions available at a status, in the order they should be drawn.
 *
 * An unrecognised status gets no actions rather than a guess: this table has
 * grown with the `orders.status` CHECK four times, and the safe failure for a
 * value the portal has not heard of is to show the order and refuse to move it,
 * not to invent a transition.
 */
export function sellerOrderActions(status) {
  const key = String(status ?? '').trim().toLowerCase()
  return SELLER_ORDER_ACTIONS[key] ?? []
}

/** The seller's primary action at this status, or null. */
export function primarySellerAction(status) {
  return sellerOrderActions(status)[0] ?? null
}

/**
 * Whether an order is genuinely waiting on the maker.
 *
 * "Has an action" is *not* the same question, and `cancelled` is why: restoring
 * a cancelled order is an affordance worth offering, but nobody is blocked on
 * it. Counting every cancellation as "waiting on you" would turn the
 * dashboard's one alarm into a list of everything that has ever gone wrong, and
 * an alarm that is always lit is not read.
 */
export function needsSellerAction(status) {
  const key = String(status ?? '').trim().toLowerCase()
  if (key === 'cancelled') return false
  return sellerOrderActions(key).length > 0
}

/**
 * The tabs across the top of the seller's order list.
 *
 * The app's seller list has a status chip row rather than tabs; these are the
 * same groupings, named for what a maker is looking at when they open the page
 * at 8am. Each filter states its predicate so the count on a tab and the rows
 * under it come from one function and cannot disagree.
 */
export const SELLER_ORDER_TABS = [
  { id: 'all', label: 'All', match: () => true },
  {
    id: 'new',
    label: 'New',
    // Not started, including the ones the customer's cancel has parked.
    match: (order) =>
      ['pending', 'placed', 'awaiting_payment', 'awaiting_payment_confirmation'].includes(
        order?.status,
      ),
  },
  {
    id: 'progress',
    label: 'On the bench',
    match: (order) => order?.status === 'preparing',
  },
  {
    id: 'ready',
    label: 'Ready',
    match: (order) => order?.status === 'ready',
  },
  {
    id: 'attention',
    label: 'Needs you',
    // The two statuses where the order is genuinely blocked on the maker:
    // a cancellation to approve and a payment a person has to check.
    match: (order) =>
      ['cancellation_requested', 'payment_conflict'].includes(order?.status),
  },
  {
    id: 'done',
    label: 'Done',
    match: (order) =>
      ['delivered', 'received', 'cancelled'].includes(order?.status),
  },
]

export function filterSellerOrders(orders, tabId = 'all') {
  const tab =
    SELLER_ORDER_TABS.find((candidate) => candidate.id === tabId) ??
    SELLER_ORDER_TABS[0]
  return (orders ?? []).filter(tab.match)
}

/**
 * A tab with nothing behind it is a dead end, so empty ones are dropped —
 * except 'all' and 'attention'. 'All' is the list's own name. 'Needs you' is
 * kept even when empty because its emptiness is the good news the seller opened
 * the page to check.
 */
export function availableSellerOrderTabs(orders) {
  const list = orders ?? []
  return SELLER_ORDER_TABS.filter(
    (tab) =>
      tab.id === 'all' || tab.id === 'attention' || list.some(tab.match),
  )
}

/** Newest first — the order a maker cares about is the one that just landed. */
export function sortSellerOrders(orders) {
  return [...(orders ?? [])].sort((a, b) => {
    const left = new Date(a?.created_at ?? 0).getTime() || 0
    const right = new Date(b?.created_at ?? 0).getTime() || 0
    return right - left
  })
}

/**
 * Stock at or below this is "running out" — `SellerInventoryRow.
 * lowStockThreshold`.
 */
export const LOW_STOCK_THRESHOLD = 5

/**
 * The (product, size) rows that are running out, worst first.
 *
 * The boundary is copied exactly and both ends of it matter:
 *
 *   stock > 0 AND stock <= 5
 *
 * **Zero is excluded on purpose.** It is a different problem with a different
 * fix — a size that is gone cannot be sold and needs restocking before anyone
 * asks for it, while a size at 3 is about to cost a sale this week. Folding
 * them together (the common `stock <= 5` mistake) buries the four rows that
 * need attention behind the twenty that are already broken.
 *
 * `inventory` is one row per (product_id, size) with the colours already summed
 * into it, so this reads the same table checkout decrements.
 */
export function lowStockRows(products, { threshold = LOW_STOCK_THRESHOLD } = {}) {
  const rows = []

  for (const product of products ?? []) {
    const inventory = Array.isArray(product?.inventory) ? product.inventory : []
    for (const row of inventory) {
      const stock = Number(row?.stock) || 0
      if (stock <= 0 || stock > threshold) continue
      rows.push({
        productId: String(product?.id ?? ''),
        name: product?.name ?? 'Product',
        size: row?.size ?? '',
        stock,
      })
    }
  }

  return rows.sort((a, b) => a.stock - b.stock)
}

/** Stock at exactly zero — listed separately from `lowStockRows` above. */
export function outOfStockRows(products) {
  const rows = []
  for (const product of products ?? []) {
    const inventory = Array.isArray(product?.inventory) ? product.inventory : []
    for (const row of inventory) {
      if ((Number(row?.stock) || 0) > 0) continue
      rows.push({
        productId: String(product?.id ?? ''),
        name: product?.name ?? 'Product',
        size: row?.size ?? '',
        stock: 0,
      })
    }
  }
  return rows
}

/**
 * The catalogue in five numbers — what the product list says before the list.
 *
 * Every figure here is already computed somewhere else on the page (published
 * from `is_published`, the two stock counts from the functions above, pairs from
 * `inventory`), and that is the point: a summary is only allowed to be a
 * rearrangement of what the rows already say. A summary with its own query is a
 * second answer to the same question, and the day it disagrees with the list
 * underneath it is the day a seller stops reading either.
 *
 * The two stock counts are counted **per size, not per product**, because that
 * is what the fix is: a product running low in one size out of eight is one
 * restock, and saying "3 products running low" when it is three sizes of one
 * shoe would send the seller looking for three shoes. The product counts come
 * along (`lowProducts`, `outProducts`) for the hint beside the figure, which is
 * where "across 2 products" belongs.
 */
export function catalogSummary(products) {
  const rows = Array.isArray(products) ? products : []
  const low = lowStockRows(rows)
  const out = outOfStockRows(rows)

  let pairs = 0
  for (const product of rows) {
    const inventory = Array.isArray(product?.inventory) ? product.inventory : []
    for (const row of inventory) pairs += Number(row?.stock) || 0
  }

  const published = rows.filter((product) => Boolean(product?.is_published)).length

  return {
    total: rows.length,
    published,
    hidden: rows.length - published,
    lowSizes: low.length,
    lowProducts: new Set(low.map((row) => row.productId)).size,
    outSizes: out.length,
    outProducts: new Set(out.map((row) => row.productId)).size,
    pairs,
  }
}

/**
 * How the seller's product list is drawn: photographs, or a table of numbers.
 *
 * Both are honest answers to different questions — *is this the pair I meant?*
 * is a question about the picture, and *which of these is missing a size 42?* is
 * a question about columns — so the page offers both and remembers the choice.
 * The order matters only in that `grid` is the default, which is what the page
 * has always been and what the storefront itself does.
 */
export const PRODUCT_VIEWS = ['grid', 'list']

/**
 * A stored or hand-typed view, or the default.
 *
 * Tolerant for the same reason `normalizeThemeMode` is: the value comes out of
 * `localStorage`, which a previous release, another tab, or the seller's own
 * devtools can have written, and a mismatched string must not be able to render
 * a page with no products on it.
 */
export function normalizeProductView(value) {
  const text = String(value ?? '').trim().toLowerCase()
  return PRODUCT_VIEWS.includes(text) ? text : 'grid'
}

/** Local midnight for a timestamp, so "today" means the seller's today. */
function startOfDay(date) {
  const copy = new Date(date)
  copy.setHours(0, 0, 0, 0)
  return copy
}

/**
 * The dashboard's own arithmetic, over orders already in hand.
 *
 * Three decisions worth stating, because each one is a way a dashboard lies:
 *
 *  1. **"Sales today" counts orders PLACED today, not money collected today.**
 *     `orders` has `created_at` and no `paid_at`, so there is no honest way to
 *     ask when the money actually arrived without a second table. So this is
 *     the value of what was ordered today — which is what a maker acts on —
 *     and `unpaid` is reported beside it rather than quietly folded in, so
 *     "₱4,200 today" with "3 unpaid" underneath is not read as ₱4,200 banked.
 *  2. **A cancelled order is not counted at all** — not in today's count, not
 *     in today's value, not in today's unpaid. It is not revenue, and counting
 *     it in the arrivals makes every cancellation read as a sale that later
 *     vanished. It is still in `byStatus` and still in the list, which is where
 *     a seller goes to find out what happened to it.
 *  3. **`awaiting_*` orders ARE counted**, because they are real orders that
 *     reserved real stock. Excluding them would hide the newest work from the
 *     person who has to do it; the `unpaid` figure is what keeps it honest.
 *
 * `openCount` and `needsActionCount` are deliberately different numbers. "Open"
 * is "not finished" — it includes an order sitting at `ready` waiting for the
 * buyer to collect. "Needs action" is "a customer is waiting on you right now",
 * which is what the dashboard's alarm is for.
 */
export function dashboardTotals(orders, { now = new Date() } = {}) {
  const today = startOfDay(now).getTime()
  const list = orders ?? []

  const counted = list.filter((order) => order?.status !== 'cancelled')

  const todays = counted.filter((order) => {
    const at = new Date(order?.created_at ?? 0).getTime()
    return Number.isFinite(at) && at >= today
  })

  const salesToday = todays.reduce(
    (sum, order) => sum + (Number(order?.total_amount) || 0),
    0,
  )

  const unpaidToday = todays.filter(
    (order) => order?.payment_status !== 'paid',
  ).length

  const byStatus = {}
  for (const order of list) {
    const status = String(order?.status ?? 'unknown')
    byStatus[status] = (byStatus[status] ?? 0) + 1
  }

  return {
    // Orders that arrived today, and what they are worth.
    orderCountToday: todays.length,
    salesToday,
    unpaidToday,
    // The whole book, not just today.
    openCount: list.filter(
      (order) => !['delivered', 'received', 'cancelled'].includes(order?.status),
    ).length,
    needsActionCount: list.filter((order) => needsSellerAction(order?.status))
      .length,
    byStatus,
  }
}

/**
 * The local calendar day a timestamp falls on, as a comparable key.
 *
 * LOCAL, not UTC, and this is the one thing about bucketing that has to be
 * right: a seller in Cebu closing at 11pm is still selling "today", and a UTC
 * bucket would move the last eight hours of their day onto tomorrow — so the
 * bar for today would be short at exactly the moment they are looking at it.
 */
function localDayKey(date) {
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`
}

/**
 * Orders bucketed into one entry per local day, oldest first.
 *
 * One bucket per day **including the empty ones**, which is not padding: a list
 * of only the days that sold something draws a chart with no gaps, so a quiet
 * Tuesday disappears and the week reads as continuous trade. An explicit zero is
 * the truth.
 *
 * Cancelled orders are excluded, the same rule `dashboardTotals` follows and for
 * the same reason — a cancelled order is not revenue, and a chart that counts it
 * makes every cancellation look like a sale that later vanished.
 *
 * `isProjected` marks **today**, and it is the app's own flag (a
 * `SalesDataPoint` carries it for "today if the day is incomplete"). It exists
 * so a chart can say "this bar is still filling" rather than drawing a partly
 * finished day as though the seller had simply stopped selling at noon.
 */
export function dailyBuckets(orders, { now = new Date(), days = 7 } = {}) {
  const end = startOfDay(now)
  const buckets = []

  for (let offset = days - 1; offset >= 0; offset -= 1) {
    const date = new Date(end)
    date.setDate(end.getDate() - offset)
    buckets.push({
      date,
      key: localDayKey(date),
      revenue: 0,
      orderCount: 0,
    })
  }

  const at = new Map(buckets.map((bucket, index) => [bucket.key, index]))

  for (const order of orders ?? []) {
    if (order?.status === 'cancelled') continue
    const when = new Date(order?.created_at ?? 0)
    if (!Number.isFinite(when.getTime())) continue

    const index = at.get(localDayKey(when))
    if (index === undefined) continue

    buckets[index].revenue += Number(order.total_amount) || 0
    buckets[index].orderCount += 1
  }

  const todayKey = localDayKey(end)
  return buckets.map((bucket) => ({
    ...bucket,
    isProjected: bucket.key === todayKey,
  }))
}

/** The dashboard's chart window. A week is the shortest span that can show a
 *  rhythm — two points is a line, and a day is not a trend. */
export const TREND_WINDOW_DAYS = 7

/**
 * The last `days` of takings, against the `days` before them — a port of
 * `SalesTrendResult`.
 *
 * The comparison window is the **same length and immediately prior**, which is
 * the app's rule and the only one that makes the percentage mean anything: "up
 * 20%" against a three-day holiday weekend is not a fact about the business.
 *
 * `hasComparison` is separate from `percentChange` rather than being folded into
 * it, because `previousTotal === 0` has two completely different meanings and a
 * single number cannot carry both. It is either **the first week this store has
 * ever traded**, where "+∞%" is nonsense and "0% growth" is a lie, or a week off
 * — and the caller needs to be able to tell the seller which, so this returns
 * the ability to say nothing instead of a number that is always wrong.
 */
export function salesTrend(
  orders,
  { now = new Date(), days = TREND_WINDOW_DAYS } = {},
) {
  const list = orders ?? []

  const currentEnd = startOfDay(now)
  const previousEnd = new Date(currentEnd)
  previousEnd.setDate(currentEnd.getDate() - days)

  const points = dailyBuckets(list, { now: currentEnd, days })
  const previousPoints = dailyBuckets(list, { now: previousEnd, days })

  const total = points.reduce((sum, point) => sum + point.revenue, 0)
  const previousTotal = previousPoints.reduce(
    (sum, point) => sum + point.revenue,
    0,
  )
  const hasComparison = previousTotal > 0

  return {
    days,
    points,
    total,
    previousTotal,
    // Raw, not rounded — the display rounds to a whole percent, and rounding
    // here as well would compound two roundings into a different number.
    percentChange: hasComparison
      ? ((total - previousTotal) / previousTotal) * 100
      : 0,
    hasComparison,
    // Every day zero, so there is no chart to draw — only a flat line that looks
    // like a broken chart rather than like a quiet week.
    isEmpty: points.every((point) => point.revenue === 0),
  }
}

/**
 * The statuses in the order a maker works them, not alphabetically.
 *
 * This is the pipeline order the app's tabs and chips follow, and it is what
 * makes a breakdown readable at a glance: "placed, preparing, ready" left to
 * right is the day's work. Sorted alphabetically the same three read as
 * "placed, preparing, ready" by luck and as "cancelled, delivered, pending" on
 * the next store — a list with no story in it.
 *
 * Anything the order does not name sorts last, which is the honest place for a
 * status this file has not heard of (the CHECK has grown four times) and is the
 * same fail-visible rule `statusMeta` follows.
 */
export const SELLER_STATUS_ORDER = [
  'pending',
  'placed',
  'preparing',
  'ready',
  'delivered',
  'received',
  'cancellation_requested',
  'cancelled',
  'awaiting_payment',
  'awaiting_payment_confirmation',
  'payment_conflict',
]

/**
 * How the store's orders are distributed across statuses.
 *
 * `dashboardTotals.byStatus` already tallies these and nothing displayed them,
 * which was the gap: four numbers on the dashboard told a seller *how many*
 * orders were open and never *where* they were, so the only way to find the two
 * that had been sitting at `placed` since yesterday was to open the list and
 * read it.
 *
 * `tab` is the queue tab this status lives under, so a chip is a door rather
 * than a decoration — "3 cancelled" that opens the same unfiltered list as every
 * other chip teaches a seller the chips do nothing. The mapping is many-to-one
 * in both directions and that is fine: the tabs group by what a maker is about
 * to do, and `preparing` and `placed` are both "work in front of me".
 */
export function statusBreakdown(orders) {
  const counts = new Map()

  for (const order of orders ?? []) {
    const status = String(order?.status ?? 'unknown')
    counts.set(status, (counts.get(status) ?? 0) + 1)
  }

  const rankOf = (status) => {
    const index = SELLER_STATUS_ORDER.indexOf(status)
    return index < 0 ? SELLER_STATUS_ORDER.length : index
  }

  return [...counts.entries()]
    .map(([status, count]) => ({ status, count, tab: tabForStatus(status) }))
    .sort(
      (a, b) => rankOf(a.status) - rankOf(b.status) || a.status.localeCompare(b.status),
    )
}

/**
 * Which queue tab shows this status.
 *
 * Kept beside `SELLER_ORDER_TABS` in spirit even though it cannot share its
 * predicates: the tabs *bucket* orders by what to do next, and a status is one
 * value inside a bucket. Writing it as a status→tab map is the only way a chip
 * can be a link, and the fallback is `all` — a status this file has not heard of
 * opens the whole queue rather than a tab that would show nothing, because an
 * empty list reads as "none of these" and the order is right there.
 */
export function tabForStatus(status) {
  switch (String(status ?? '').trim().toLowerCase()) {
    case 'pending':
    case 'placed':
    case 'awaiting_payment':
    case 'awaiting_payment_confirmation':
      return 'new'
    case 'preparing':
      return 'progress'
    case 'ready':
      return 'ready'
    case 'cancellation_requested':
    case 'payment_conflict':
      return 'attention'
    case 'delivered':
    case 'received':
    case 'cancelled':
      return 'done'
    default:
      return 'all'
  }
}

/**
 * What a store still needs before it can sell.
 *
 * A seller whose store is missing a banner or a description has a shopfront
 * that looks broken to a customer, and the app spreads those fields across four
 * screens. This turns them into one checklist so the dashboard can say what is
 * missing rather than leaving the seller to notice.
 *
 * `location` is required in the schema (NOT NULL), so it is not listed.
 */
export function storeCompleteness(store) {
  if (!store) {
    return { complete: false, missing: ['Create your store'], hasStore: false }
  }

  const missing = []
  const blank = (value) => !String(value ?? '').trim()

  if (blank(store.tagline)) missing.push('Add a tagline')
  if (blank(store.description)) missing.push('Write your workshop description')
  if (blank(store.logo_url)) missing.push('Upload a logo')
  if (blank(store.banner_url)) missing.push('Add a storefront photo')
  if (blank(store.location)) missing.push('Set your location')

  return { complete: missing.length === 0, missing, hasStore: true }
}

/**
 * The delivery fee a seller is shown for an order, derived the same way the
 * customer's receipt derives it: `total − the sum of the lines`, clamped at
 * zero.
 *
 * Not the ₱100 constant. A voucher, a legacy order or a future fee table would
 * each make the constant wrong, and a seller reconciling a payout against a
 * breakdown that does not add up to the total is the one number they will
 * check.
 */
export function sellerOrderFee(order) {
  const total = Number(order?.total_amount) || 0
  const lines = (Array.isArray(order?.order_items) ? order.order_items : []).reduce(
    (sum, item) =>
      sum + (Number(item?.unit_price) || 0) * (Number(item?.quantity) || 1),
    0,
  )
  return Math.max(0, Math.round((total - lines) * 100) / 100)
}

/**
 * What a failed status write means, in words the seller can act on.
 *
 * RLS on `orders` is the thing that actually decides, and it fails *silently*
 * for a plain UPDATE — PostgREST answers `200` with an empty array, which is
 * how the app's own `cancelOrder` reports success on an order it never touched.
 * The portal therefore asks for the row back (`.select().single()`), and this
 * function exists for the case where that comes back empty: "no rows" here
 * means the write was refused, not that the order is gone.
 */
export function statusWriteError(error) {
  const raw = String(error?.message ?? '').trim()

  if (!raw || /no rows|0 rows|json object requested/i.test(raw)) {
    return {
      message:
        'That change was refused. You may not have access to this order — sign in again, or update it in the CUFMAI app.',
      code: 'no-rows',
    }
  }

  return { message: raw, code: error?.code ?? null }
}
