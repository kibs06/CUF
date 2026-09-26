import { shortOrderId, snapshotLines } from './checkoutRules.js'

/**
 * Order rules — the pure half of "my orders".
 *
 * Kept free of the Supabase client for the same reason `cartRules` and
 * `checkoutRules` are: `orders.js` imports the client at module level and
 * cannot be loaded in plain Node, and everything here is a status, a date or a
 * permission — the parts that must be provable without a network.
 *
 * Nothing below is invented. Each rule is copied from the piece it has to agree
 * with:
 *
 *   STATUS_META / progress     `MyOrdersScreen._getStatusData` and
 *                              `_getProgressIndex` — the same labels, in the
 *                              same words, for the same database values
 *   CANCELLATION_REASONS       `AppConstants.cancellationReasons`
 *   CANCEL_WINDOW_HOURS        `AppConstants.processingCancelWindowHours`
 *   cancelPlan                 `TrackingScreen._canCancel` plus its
 *                              \"preparing\" countdown, and the server's own
 *                              copy of both in `cancel_my_order`
 *   shortOrderRef              `notify_on_order_status_change`'s
 *                              `substring(id, length - 7)`
 *   orderLines                 the `defer-until-paid` split: line rows exist
 *                              only once money has moved, so the snapshot has
 *                              to be able to stand in for them
 */

/**
 * Why a customer can cancel, in the app's words.
 *
 * Ported verbatim rather than re-typed: the same list is shown in the app's
 * cancellation sheet, and a reason that exists in one place and not the other
 * turns one report field into two vocabularies.
 */
export const CANCELLATION_REASONS = [
  'Changed my mind',
  'Found a better price or deal elsewhere',
  'Ordered by mistake (wrong item, size, color, or quantity)',
  'Need to change delivery address',
  'Want to modify the order (variant, quantity, voucher, etc.)',
  'Shipping/processing is taking too long',
  'Seller is not responding to my inquiries',
  'Payment issue or want to change payment method',
  'Other',
]

/** Free text is required for this reason — the server enforces it too. */
export const OTHER_REASON = 'Other'

/** `AppConstants.processingCancelWindowHours` — hours after 'preparing'. */
export const CANCEL_WINDOW_HOURS = 2

/** The four steps the app's progress line shows, in its own words. */
export const ORDER_PROGRESS_STEPS = ['Pending', 'Processing', 'Shipped', 'Delivered']

/**
 * Every status the `orders.status` CHECK has ever allowed, and what a customer
 * should be told about it.
 *
 * `placed` and `received` are legacy aliases the app still maps
 * (`placed → Pending`, `received → Delivered`) because they exist on old rows.
 * `awaiting_payment` and `payment_conflict` arrived with PayMongo; the
 * gateway-free `awaiting_payment_confirmation` is kept for orders created
 * before 2026-09-05, which can still be read even though nothing writes it.
 *
 * `tone` names a Tailwind palette role, not a colour value, so the pill cannot
 * drift from the rest of the site.
 */
const STATUS_META = {
  pending: { label: 'Pending', tone: 'amber', step: 0, open: true },
  placed: { label: 'Pending', tone: 'amber', step: 0, open: true },
  preparing: { label: 'Processing', tone: 'clay', step: 1, open: true },
  ready: { label: 'Ready', tone: 'olive', step: 2, open: true },
  delivered: { label: 'Delivered', tone: 'muted', step: 3, open: false },
  received: { label: 'Delivered', tone: 'muted', step: 3, open: false },
  cancelled: { label: 'Cancelled', tone: 'crimson', step: -1, open: false },
  cancellation_requested: {
    label: 'Cancellation requested',
    tone: 'amber',
    step: -1,
    open: true,
  },
  awaiting_payment: {
    label: 'Awaiting payment',
    tone: 'amber',
    step: -1,
    open: true,
  },
  awaiting_payment_confirmation: {
    label: 'Awaiting confirmation',
    tone: 'amber',
    step: -1,
    open: true,
  },
  payment_conflict: {
    label: 'Needs review',
    tone: 'crimson',
    step: -1,
    open: true,
  },
}

const UNKNOWN_STATUS = { label: 'Unknown', tone: 'muted', step: 0, open: true }

/**
 * An unrecognised status is shown, not hidden.
 *
 * The status CHECK has grown four times; a value this file has not heard of
 * means a release added one, and an order that vanishes from the list is worse
 * than an order labelled `preparing_custom`. The raw value is title-cased so it
 * is at least readable.
 */
export function statusMeta(status) {
  const key = String(status ?? '').trim()
  const known = STATUS_META[key]
  if (known) return { status: key, ...known }

  const readable = key
    ? key.replace(/[_-]+/g, ' ').replace(/^./, (c) => c.toUpperCase())
    : 'Unknown'
  return { status: key, ...UNKNOWN_STATUS, label: readable }
}

export function statusLabel(status) {
  return statusMeta(status).label
}

export function statusTone(status) {
  return statusMeta(status).tone
}

/** 0–3 on the progress line, or -1 when the line does not apply. */
export function progressIndex(status) {
  return statusMeta(status).step
}

/** Still moving through the maker's bench (not delivered, not cancelled). */
export function isOpenOrder(status) {
  return statusMeta(status).open
}

/** Money not yet confirmed — the order exists but has not been paid for. */
export function isUnpaidOrder(status) {
  return (
    status === 'awaiting_payment' || status === 'awaiting_payment_confirmation'
  )
}

/**
 * `#a1b2c3d4` — an order's short reference.
 *
 * Delegates to `checkoutRules.shortOrderId` rather than re-deriving it, and the
 * first eight characters are the RIGHT choice for the storefront even though
 * the two conventions exist server-side (`cancel_awaiting_gcash_order` uses
 * `left(id, 8)`, while `notify_on_order_status_change` uses the last eight):
 * the checkout and payment pages already print the first eight, and a customer
 * reading `#a1b2c3d4` on the payment screen and `#ef123456` on the receipt for
 * the same order would reasonably conclude they are two orders.
 */
export function shortOrderRef(orderId) {
  const short = shortOrderId(orderId)
  return short ? `#${short}` : '—'
}

/**
 * Whether the customer may cancel, and which cancellation they would be
 * asking for.
 *
 * Two shapes, matching the server exactly:
 *
 *   pending / placed   → `cancel`,   an outright cancellation
 *   preparing          → `request`,  which the maker approves or rejects,
 *                        and only inside `CANCEL_WINDOW_HOURS` of entering
 *                        'preparing'
 *
 * `preparingAt` is read from `order_status_history`, not from `created_at`: a
 * maker can sit on an order for days, so \"when did work start\" and \"when was
 * this ordered\" are different questions and only the first one decides whether
 * cancelling is still fair. An order with no history row predates the history
 * trigger — unknown age is treated as still cancellable, because the
 * transition is a request, not a unilateral cancel.
 *
 * `reason` carries the explanation for a refusal, ready to render. It is the
 * same sentence the server raises, so the button and the API cannot tell the
 * customer two different stories.
 */
export function cancelPlan(order, { now = new Date() } = {}) {
  const status = order?.status
  const kindFor = (raw) =>
    raw === 'pending' || raw === 'placed'
      ? 'cancel'
      : raw === 'preparing'
        ? 'request'
        : null

  const kind = kindFor(status)

  if (!kind) {
    return {
      allowed: false,
      kind: null,
      closesAt: null,
      reason: cancelRefusal(status),
    }
  }

  if (kind === 'cancel') {
    return { allowed: true, kind, closesAt: null, reason: null }
  }

  const since = preparingAt(order)
  if (!since) {
    return { allowed: true, kind, closesAt: null, reason: null }
  }

  const closesAt = new Date(
    since.getTime() + CANCEL_WINDOW_HOURS * 60 * 60 * 1000,
  )
  // Strictly AFTER the deadline closes the window, matching the app's
  // `if (now.isAfter(deadline))` — at exactly the two-hour mark the request is
  // still accepted, the same inclusive-boundary convention `sale_price.dart`
  // uses. The server enforces it with `v_since < now() - interval '2 hours'`,
  // which is the same comparison.
  if (closesAt.getTime() < now.getTime()) {
    return {
      allowed: false,
      kind: null,
      closesAt,
      reason:
        'The maker has already started this order and the 2-hour cancellation window has closed. Message the store to arrange a return.',
    }
  }

  return { allowed: true, kind, closesAt, reason: null }
}

/** Why this status cannot be cancelled, in the server's own words. */
function cancelRefusal(status) {
  switch (status) {
    case 'cancelled':
      return 'This order is already cancelled.'
    case 'cancellation_requested':
      return 'You have already asked to cancel this order — the maker will respond shortly.'
    case 'awaiting_payment':
    case 'awaiting_payment_confirmation':
      return 'This order is still waiting for payment. Cancel it from the payment screen instead.'
    case 'payment_conflict':
      return 'This order needs a person to check it against the payment — please contact the store.'
    case 'ready':
      return 'This order is already bagged and waiting for you, so it can no longer be cancelled here. Contact the store for a return.'
    case 'delivered':
    case 'received':
      return 'This order has been delivered, so it can no longer be cancelled here. Contact the store for a return.'
    default:
      return 'This order can no longer be cancelled here.'
  }
}

/**
 * When the order entered 'preparing', or null when that is not known.
 *
 * `history` is the `order_status_history` rows for the order. The LAST
 * 'preparing' row wins: a seller can send an order back through preparing
 * after a correction, and the window should restart with the work.
 */
export function preparingAt(order) {
  const rows = order?.order_status_history
  if (!Array.isArray(rows)) return null

  let latest = null
  for (const row of rows) {
    if (row?.status !== 'preparing') continue
    const at = new Date(row.changed_at)
    if (Number.isNaN(at.getTime())) continue
    if (!latest || at.getTime() > latest.getTime()) latest = at
  }
  return latest
}

/**
 * The order's lines, from whichever source actually has them.
 *
 * `order_items` is the real table, but it is written by the payment webhook
 * *after* money moves (`defer-until-paid`), so an order that is pending
 * payment — or one that was cancelled before payment — has no line rows at
 * all. `items_snapshot` is captured when the order is created and is therefore
 * the only complete record for those, which is why it is the fallback rather
 * than a nice-to-have.
 *
 * Both paths return the shape `OrderSummaryCard` renders, so a screen does not
 * need to know which one it got.
 */
export function orderLines(order) {
  const items = Array.isArray(order?.order_items) ? order.order_items : []

  if (items.length > 0) {
    return items.map((item, index) => {
      const quantity = Number(item?.quantity) || 1
      const unitPrice = money(item?.unit_price)

      return {
        id: String(item?.id ?? `${item?.product_id ?? index}|${index}`),
        name: item?.products?.name ?? item?.product_name ?? 'Product',
        imageUrl: primaryImage(item?.products),
        size: item?.size ?? '',
        quantity,
        unitPrice,
        lineTotal: money(unitPrice * quantity),
      }
    })
  }

  return snapshotLines(order?.items_snapshot)
}

/** The image the app would show for a product: `is_primary`, then order. */
function primaryImage(product) {
  const images = Array.isArray(product?.product_images)
    ? [...product.product_images]
    : []
  if (images.length === 0) return null

  images.sort((a, b) => {
    const primary = Number(Boolean(b?.is_primary)) - Number(Boolean(a?.is_primary))
    if (primary !== 0) return primary
    return (a?.display_order ?? 0) - (b?.display_order ?? 0)
  })

  const url = images[0]?.image_url
  return typeof url === 'string' && url.length > 0 ? url : null
}

function money(value) {
  return Math.round((Number(value) || 0) * 100) / 100
}

/** Total pieces across every line — \"3 pairs\" on the order card. */
export function orderPieces(order) {
  return orderLines(order).reduce(
    (sum, line) => sum + (Number(line.quantity) || 0),
    0,
  )
}

/**
 * The order's own numbers, read back off the row.
 *
 * `orders.total_amount` is what the server decided and is therefore the
 * authority; the subtotal is the sum of the lines. Delivery is the difference
 * between them rather than the ₱100 constant, because a legacy order, a
 * voucher or a future fee table would all make the constant wrong — and a
 * breakdown that does not add up to the total is worse than no breakdown.
 */
export function orderTotals(order) {
  const total = money(order?.total_amount)
  const subtotal = money(
    orderLines(order).reduce((sum, line) => sum + line.lineTotal, 0),
  )

  /*
    Clamped at zero. A negative "delivery fee" is nonsense to print, and the
    only way to reach one is an order priced BELOW the sum of its own lines — a
    voucher, or a sale that started between the snapshot and the charge. That
    needs a discount row of its own, which this portal does not model yet (the
    checkout sends `voucher_code: null`); until it does, showing ₱0.00 delivery
    is the least wrong of the available answers rather than a number with the
    wrong sign. `total` stays the server's, because that is what was charged.
  */
  return { subtotal, deliveryFee: Math.max(0, money(total - subtotal)), total }
}

/**
 * The delivery address as display lines.
 *
 * Reads the snake_case `orders.shipping_address` snapshot — the same object
 * `Address.fromSnapshot` renders in the app, written once at checkout and never
 * updated, so a delivered order still shows where it actually went even after
 * the customer edits their address book.
 */
export function shippingAddressLines(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return []

  const parts = [
    snapshot.recipient_name,
    snapshot.recipient_phone,
    snapshot.street_address,
    snapshot.landmark ? `Landmark: ${snapshot.landmark}` : null,
    snapshot.barangay,
    snapshot.city_municipality,
    snapshot.province,
    snapshot.region,
  ]

  return parts
    .map((part) => String(part ?? '').trim())
    .filter(Boolean)
}

/** Whether the customer chose to collect, or to have it brought. */
export function fulfilmentLabel(order) {
  return order?.fulfillment === 'delivery' ? 'Delivery' : 'Pickup'
}

/**
 * The order's timeline: real transitions where we have them.
 *
 * `order_status_history` only starts when the history trigger shipped
 * (2026-07-18), so an older order has a single backfilled row — or, if it was
 * created before that too, none at all. `orders.created_at` is therefore added
 * as the first entry when the history does not already begin there, which is
 * the one transition we can always state truthfully.
 *
 * Sorted oldest first: an order's story reads downwards.
 */
export function orderTimeline(order) {
  const rows = Array.isArray(order?.order_status_history)
    ? order.order_status_history
    : []

  const entries = rows
    .map((row) => ({
      key: `h|${row?.id ?? row?.status}|${row?.changed_at}`,
      status: row?.status ?? 'pending',
      label: statusLabel(row?.status),
      tone: statusTone(row?.status),
      at: parseDate(row?.changed_at),
      source: 'history',
    }))
    .filter((entry) => entry.at)
    .sort((a, b) => a.at.getTime() - b.at.getTime())

  const created = parseDate(order?.created_at)
  if (!created) return entries

  /*
    Suppress the synthetic 'Order placed' only when the first history row IS
    the creation: the same status a brand-new order has (`pending`/`placed`),
    within a minute of `created_at`. Both halves matter. Matching on the
    timestamp alone swallowed a real transition — measured on a live order
    created at 11:13:05 and cancelled at 11:13:11: the first history row was six
    seconds from creation, so 'Order placed' was dropped and the whole timeline
    was a single entry, "Cancelled", with no sign the order had ever been
    placed.
  */
  const startsAtCreated =
    entries.length > 0 &&
    (entries[0].status === 'pending' || entries[0].status === 'placed') &&
    Math.abs(entries[0].at.getTime() - created.getTime()) < 60_000

  if (entries.length === 0) {
    return [
      {
        key: 'created',
        status: 'placed',
        label: 'Order placed',
        tone: 'amber',
        at: created,
        source: 'created',
      },
    ]
  }

  if (startsAtCreated) return entries

  return [
    {
      key: 'created',
      status: 'placed',
      label: 'Order placed',
      tone: 'amber',
      at: created,
      source: 'created',
    },
    ...entries,
  ]
}

function parseDate(value) {
  if (!value) return null
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? null : date
}

/**
 * The tabs across the top of the list.
 *
 * The app's tabs are All / Unpaid / Processing / Shipped / Review / Returns;
 * these are the same groupings with the two that need other features removed —
 * 'Review' belongs to a review flow this portal does not have yet, and
 * 'Returns' was the app's home for swipe-deleted orders. Each filter states its
 * predicate, so the count on a tab and the rows it shows come from one function
 * and cannot disagree.
 */
export const ORDER_FILTERS = [
  { id: 'all', label: 'All orders', match: () => true },
  {
    id: 'unpaid',
    label: 'To pay',
    match: (order) => isUnpaidOrder(order?.status),
  },
  {
    id: 'processing',
    label: 'In progress',
    match: (order) =>
      ['pending', 'placed', 'preparing', 'cancellation_requested'].includes(
        order?.status,
      ),
  },
  {
    id: 'ready',
    label: 'Ready',
    match: (order) => order?.status === 'ready',
  },
  {
    id: 'completed',
    label: 'Completed',
    match: (order) =>
      order?.status === 'delivered' ||
      order?.status === 'received' ||
      order?.status === 'cancelled',
  },
]

export function filterOrders(orders, filterId = 'all') {
  const filter =
    ORDER_FILTERS.find((candidate) => candidate.id === filterId) ??
    ORDER_FILTERS[0]
  return (orders ?? []).filter(filter.match)
}

/**
 * A tab with nothing behind it is a dead end, so empty ones are dropped —
 * except 'all', which is the list's own name and must always exist.
 */
export function availableOrderFilters(orders) {
  const list = orders ?? []
  return ORDER_FILTERS.filter(
    (filter) => filter.id === 'all' || list.some(filter.match),
  )
}

/**
 * A failed `cancel_my_order` as something a screen can act on.
 *
 * Two mappings are worth spelling out:
 *
 *  1. `P0001` is the code for every hand-written rejection in this schema, so
 *     the MESSAGE is the only signal there is — and for cancellation it is the
 *     right thing to show. "The maker has already started this order…" is
 *     written for a customer; replacing it with a generic apology would throw
 *     away the only useful sentence in the response.
 *  2. `PGRST202` (HTTP 404) is PostgREST reporting that
 *     `public.cancel_my_order` does not exist — i.e. the migration has not been
 *     applied to this project yet. That is a deployment fact, not a customer
 *     error, and it needs its own message: telling somebody "we could not cancel
 *     your order, try again" when trying again can never work is the worst of
 *     the available answers. `notAvailable` lets the screen say so plainly and
 *     point at the app instead.
 *
 * A `42501` that is NOT our own 'Order not found' is a permission failure on
 * the function, which means the route is closed to this session — the same
 * message the checkout uses for that state.
 */
export function cancelError(
  error,
  fallback = 'We could not cancel this order. Please try again.',
) {
  const code = error?.code ?? null
  const raw = String(error?.message ?? '').trim()

  if (code === 'PGRST202' || /could not find the function/i.test(raw)) {
    return {
      message:
        'Cancelling from the website is not switched on yet. You can cancel this order in the CUFMAI app.',
      code: 'not-applied',
      notAvailable: true,
    }
  }

  if (code === '42501') {
    if (!raw || /permission denied/i.test(raw)) {
      return {
        message:
          'You are not allowed to cancel this order. Sign in again, or cancel it in the CUFMAI app.',
        code,
        notAvailable: false,
      }
    }
    return { message: raw, code, notAvailable: false }
  }

  if (raw) return { message: raw, code, notAvailable: false }
  return { message: fallback, code, notAvailable: false }
}

/** Newest first — the order a customer cares about is the one they just paid. */
export function sortOrders(orders) {
  return [...(orders ?? [])].sort((a, b) => {
    const left = parseDate(a?.created_at)?.getTime() ?? 0
    const right = parseDate(b?.created_at)?.getTime() ?? 0
    return right - left
  })
}
