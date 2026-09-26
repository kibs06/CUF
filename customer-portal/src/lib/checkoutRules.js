import { lineTotal } from './cartRules.js'

/**
 * Digits only: `"EU 40"` → `"40"`.
 *
 * Deliberately NOT `cartRules.normalizeSize`, which strips letters and leaves
 * the space, because this has to agree with the server's own size resolution —
 * `regexp_replace(size, '\D', '', 'g')` in the order function and in
 * `create-gcash-payment-intent`'s inventory check. "EU 40" and "40" are one
 * size as far as the database is concerned, and a pairing that disagreed would
 * leave a paid-for pair sitting in the cart forever.
 */
function sizeDigits(size) {
  return String(size ?? '').replace(/\D/g, '')
}

/**
 * Checkout rules — the pure half of web checkout.
 *
 * Split out from `checkout.js` for the same reason the cart is split: that file
 * imports the Supabase client at module level and cannot be loaded in plain
 * Node, and everything here is money, an address, or a payment state — the
 * parts that must be provable without a network.
 *
 * Every rule below is copied from the server piece it has to agree with, NOT
 * invented here:
 *
 *   DELIVERY_FEE           the fixed ₱100 `create-gcash-payment-intent` adds
 *   shippingSnapshot       `Address.toSnapshot()` in lib/models/address_model.dart
 *   formatDeliveryAddress  `Address.formattedAddress`, same field order
 *   shortOrderId           the notifications' own `left(p_order_id::text, 8)`
 *   paymentState           the fields `get-payment-status` returns
 *   chargedTotal           the Model B fee is `order_total + fee`, and the fee
 *                          itself comes from `get_gcash_fee`, never from here
 *
 * If any of those change server-side, this file changes with them. A checkout
 * that disagrees with the server about a number is the one bug a customer
 * cannot forgive.
 */

/**
 * The fixed fee the order-creation function adds to every order.
 *
 * It is not computed here and sent, it is *expected* here and checked: the
 * server decides the total and `reconcileServerTotal` compares what it decided
 * with what the customer was shown. This constant exists so the storefront can
 * quote the same number before the order exists.
 */
export const DELIVERY_FEE = 100

/**
 * The server's default payment window, in minutes.
 *
 * Documentation, not authority: the real deadline comes back as `expires_at`
 * on the intent and is enforced server-side. Nothing here counts against this
 * constant — `deadlineState` reads the server's timestamp.
 */
export const DEFAULT_INTENT_EXPIRY_MINUTES = 15

/** Phone: 10–13 digits once punctuation is stripped. */
const PHONE_DIGITS = [10, 13]

/** The center the app's address map opens on — Cebu City, Carcar's neighbour. */
export const DEFAULT_PIN = { latitude: 10.3157, longitude: 123.8854 }

/** The address fields, in the order a Philippine address is written. */
export const ADDRESS_FIELDS = [
  'recipientName',
  'recipientPhone',
  'region',
  'province',
  'cityMunicipality',
  'barangay',
  'streetAddress',
  'landmark',
]

/**
 * An empty address draft.
 *
 * Region, province and city are deliberately BLANK even though most customers
 * are in Carcar — the form hints at them in placeholders instead. A pre-filled
 * province is a value nobody chose, and the failure it produces is silent and
 * expensive: a customer in Manila who does not notice ships their order to
 * Cebu. Required-and-empty is a visible nudge; pre-filled-and-wrong is not.
 */
export function emptyAddressDraft(overrides = {}) {
  return {
    label: 'Home',
    recipientName: '',
    recipientPhone: '',
    region: '',
    province: '',
    cityMunicipality: '',
    barangay: '',
    streetAddress: '',
    landmark: '',
    ...overrides,
  }
}

/**
 * A PostgREST or edge-function error as something a screen can act on.
 *
 * It lives here rather than in `checkout.js` because it is a rule about the
 * server's contract, and rules are the part that gets tested.
 *
 * Two mappings are worth knowing about:
 *
 *  1. `P0001` is the code for every hand-written rejection in this schema, so
 *     the MESSAGE is the only signal there is. One of them — "you already have
 *     a checkout awaiting confirmation" — reaches us as `P0001` because the
 *     server catches the unique violation and re-raises it without an ERRCODE,
 *     so it is sniffed and normalized back to `23505`. That is what lets the
 *     caller send the customer to the order they already have instead of
 *     showing them a dead end.
 *  2. A permission failure on a FUNCTION is never a customer's problem. It
 *     means the route is closed server-side — which is exactly the state
 *     `create_gcash_checkout` is in (revoked on 2026-09-05) — and printing
 *     "permission denied for function …" at a customer tells them nothing.
 */
export function checkoutError(error, fallback = 'Something went wrong. Please try again.') {
  const code = error?.code ?? null
  const body = error?.body ?? null
  const raw = String(
    body?.error ?? body?.message ?? error?.message ?? '',
  ).trim()
  let message = fallback

  if (code === 'P0001' && raw) {
    message = raw
    if (raw.toLowerCase().includes('awaiting confirmation')) {
      return { message, code: '23505', openOrder: true }
    }
  } else if (code === '23505') {
    return {
      message:
        'You already have a GCash checkout awaiting confirmation. Complete or cancel it first.',
      code,
      openOrder: true,
    }
  } else if (code === '42501') {
    if (/permission denied/i.test(raw)) {
      message =
        'Ordering is not available on the web right now. Your cart is saved — you can complete this order in the CUFMAI app.'
    } else {
      // The server's own message is clearer here than a generic refusal — a
      // session that expired mid-checkout says "Not authenticated", and being
      // told to sign in again is the only useful thing to hear.
      message = raw || 'You are not allowed to do that.'
    }
  } else if (raw) {
    // An edge function's `{ error }` body, or a thrown JS error (network,
    // JSON). Either is more useful to the customer than the fallback.
    message = raw
  }

  return { message, code, openOrder: false }
}

/**
 * An edge-function error as something a screen can act on.
 *
 * `functions.invoke` throws a `FunctionsHttpError` whose `context` is the raw
 * `Response`, so the useful sentence — the `{ error }` body our functions
 * return — has to be read out of it. Without this step every failure surfaces
 * as supabase-js's "Edge Function returned a non-2xx status code", which is a
 * message for a developer, not a customer.
 *
 * A 409 is mapped to `openOrder: true` for the same reason the Postgres
 * mapping sniffs a message: the intent function refuses a second checkout while
 * one is pending, and the caller's job then is to send the customer to the
 * payment they already have rather than to show them a wall.
 */
export async function functionError(error, fallback) {
  let body = null
  let status = null

  try {
    if (error?.context?.json) {
      status = error.context.status ?? null
      body = await error.context.json()
    }
  } catch {
    // A non-JSON body (a platform 502, a timeout) — fall through to the generic
    // message rather than masking the failure with a parse error.
  }

  // First non-blank wins: an `Error` with no message has `message === ''`, and
  // returning that would hand the customer an empty error box.
  const message = [body?.error, body?.message, error?.message].find(
    (candidate) => typeof candidate === 'string' && candidate.trim(),
  )

  return {
    message: message ?? fallback,
    code: body?.code ?? (status ? String(status) : (error?.code ?? null)),
    status,
    body,
    openOrder: status === 409,
  }
}

/** Why a delivery phone number is unacceptable, or null. */
export function phoneError(value) {
  const digits = String(value ?? '').replace(/\D/g, '')
  if (!digits) return 'Enter a mobile number the rider can reach'
  if (digits.length < PHONE_DIGITS[0] || digits.length > PHONE_DIGITS[1]) {
    return 'Enter a complete mobile number, e.g. 0917 123 4567'
  }
  return null
}

/**
 * Every problem with an address draft, keyed by field.
 *
 * Only three fields are genuinely load-bearing — a name, a reachable number and
 * a street — but all of `region`/`province`/`city`/`barangay` are NOT NULL in
 * `customer_addresses`, so they are required here rather than failing at the
 * database. `landmark` and `label` are optional, as the schema says.
 */
export function addressErrors(draft) {
  const errors = {}
  if (!draft?.recipientName?.trim()) {
    errors.recipientName = 'Who is receiving this order?'
  }
  const phone = phoneError(draft?.recipientPhone)
  if (phone) errors.recipientPhone = phone
  for (const field of ['region', 'province', 'cityMunicipality', 'barangay']) {
    if (!draft?.[field]?.trim()) errors[field] = 'Required'
  }
  if (!draft?.streetAddress?.trim()) {
    errors.streetAddress = 'House or building number, street, purok'
  }
  return errors
}

/** True when `addressErrors` found nothing. */
export function isAddressComplete(draft) {
  return Object.keys(addressErrors(draft)).length === 0
}

/**
 * `street, barangay, city, province, region`.
 *
 * The same order as `Address.formattedAddress` in the app, because this string
 * is written onto the order and then read by a human at the other end — a
 * different order would produce two dialects of the same address.
 */
export function formatDeliveryAddress(draft) {
  return [
    draft?.streetAddress,
    draft?.barangay,
    draft?.cityMunicipality,
    draft?.province,
    draft?.region,
  ]
    .map((part) => String(part ?? '').trim())
    .filter(Boolean)
    .join(', ')
}

/**
 * The address as the `orders.shipping_address` JSONB snapshot.
 *
 * Snake_case because that is the shape `Address.toSnapshot()` has always
 * written and `Address.fromSnapshot` has always read — the app renders order
 * history from this object, so the keys are a contract, not a preference.
 *
 * Coordinates are included only when we actually have a pin. Writing the Carcar
 * default onto an order the customer never located would put a false pin on
 * somebody's delivery record; an absent key is honest, and the app's own reader
 * already tolerates it.
 */
export function shippingSnapshot(draft) {
  const snapshot = {
    label: draft?.label?.trim() || 'Home',
    recipient_name: draft?.recipientName?.trim() ?? '',
    recipient_phone: draft?.recipientPhone?.trim() ?? '',
    region: draft?.region?.trim() ?? '',
    province: draft?.province?.trim() ?? '',
    city_municipality: draft?.cityMunicipality?.trim() ?? '',
    barangay: draft?.barangay?.trim() ?? '',
    street_address: draft?.streetAddress?.trim() ?? '',
    landmark: draft?.landmark?.trim() || null,
  }

  if (Number.isFinite(Number(draft?.latitude)) && Number(draft?.latitude) !== 0) {
    snapshot.latitude = Number(draft.latitude)
    snapshot.longitude = Number(draft.longitude)
  }

  return snapshot
}

/** The `customer_addresses` insert payload for a draft. */
export function addressInsert(userId, draft) {
  return {
    user_id: userId,
    label: draft?.label?.trim() || 'Home',
    recipient_name: draft?.recipientName?.trim() ?? '',
    recipient_phone: draft?.recipientPhone?.trim() ?? '',
    region: draft?.region?.trim() ?? '',
    province: draft?.province?.trim() ?? '',
    city_municipality: draft?.cityMunicipality?.trim() ?? '',
    barangay: draft?.barangay?.trim() ?? '',
    street_address: draft?.streetAddress?.trim() ?? '',
    landmark: draft?.landmark?.trim() || null,
    // NOT NULL in the schema, so a draft without a pin falls back to the same
    // default center the app's address map opens on.
    latitude: Number(draft?.latitude) || DEFAULT_PIN.latitude,
    longitude: Number(draft?.longitude) || DEFAULT_PIN.longitude,
    is_default: Boolean(draft?.isDefault),
  }
}

/**
 * The `customer_addresses` UPDATE payload for a draft.
 *
 * The same columns as the insert, minus `user_id` — an address never changes
 * owner, and sending it would invite a mistake in a field nobody should be
 * able to edit. `is_default` IS included, because that is a decision the
 * customer is making with this save.
 */
export function addressUpdatePayload(draft) {
  const { user_id: _ignored, ...payload } = addressInsert(null, draft)
  return payload
}

/** A saved `customer_addresses` row as a draft (snake_case → camelCase). */
export function addressFromRow(row) {
  if (!row) return null
  return {
    id: String(row.id),
    label: row.label ?? 'Home',
    recipientName: row.recipient_name ?? '',
    recipientPhone: row.recipient_phone ?? '',
    region: row.region ?? '',
    province: row.province ?? '',
    cityMunicipality: row.city_municipality ?? '',
    barangay: row.barangay ?? '',
    streetAddress: row.street_address ?? '',
    landmark: row.landmark ?? '',
    latitude: Number(row.latitude) || 0,
    longitude: Number(row.longitude) || 0,
    isDefault: Boolean(row.is_default),
  }
}

/** Whole pesos-and-centavos, as the API and the rest of the site do it. */
function money(value) {
  return Math.round((Number(value) || 0) * 100) / 100
}

/**
 * What the storefront quotes for a set of cart lines.
 *
 * `lineTotal` is the cart's own function, so this is guaranteed to equal the
 * number the cart page showed: sale prices included, variant surcharges
 * included, recomputed from the product rows rather than stored.
 *
 * This is the ORDER total — goods plus delivery — and deliberately excludes the
 * GCash fee. That fee is rate-based and lives in `payment_fee_config`; it is
 * read from `get_gcash_fee`, and `chargedTotal` puts the two together.
 */
export function quotedTotal(lines, { deliveryFee = DELIVERY_FEE } = {}) {
  const subtotal = money(
    (lines ?? []).reduce((sum, item) => sum + lineTotal(item), 0),
  )
  const fee = subtotal > 0 ? money(deliveryFee) : 0
  return { subtotal, deliveryFee: fee, total: money(subtotal + fee) }
}

/**
 * Cart lines → the shape `OrderSummaryCard` renders.
 *
 * The two shapes exist for good reasons and should stay different: a cart line
 * carries the *cart's* names (`productName`, `cartSize`, a resolved `unitPrice`
 * including any variant surcharge), while an order line carries the ORDER's
 * names and the price the server pinned when it created the order. Neither
 * should be bent to look like the other, so the translation lives here, once,
 * instead of in every screen that wants to show a basket.
 */
export function summaryLines(cartLines) {
  return (cartLines ?? []).map((line) => {
    const quantity = Number(line.quantity) || 1
    const unitPrice = Number(line.unitPrice) || 0

    return {
      id: line.id,
      name: line.productName ?? line.name ?? 'Product',
      imageUrl: line.imageUrl ?? null,
      size: line.cartSize ?? line.size ?? '',
      quantity,
      unitPrice,
      lineTotal: money(unitPrice * quantity),
    }
  })
}

/**
 * An order's own `items_snapshot` → the shape `OrderSummaryCard` renders.
 *
 * This is what makes the payment page work on a resumed visit. `order_items`
 * are deliberately not written until the webhook confirms the money moved
 * (`defer-until-paid`), so while a payment is pending the order has no line
 * rows — but `create-gcash-payment-intent` snapshots the lines onto the order
 * when it creates it, and that snapshot is what the customer should see when
 * they come back to a bookmark three days later with no navigation state at
 * all.
 *
 * `id` is synthesized from the line's own identity rather than taken from a
 * row that does not exist yet.
 */
export function snapshotLines(snapshot) {
  return (snapshot ?? []).map((item, index) => {
    const quantity = Number(item?.quantity) || 1
    const unitPrice = Number(item?.unit_price) || 0

    return {
      id: `${item?.product_id ?? index}|${item?.size ?? ''}|${index}`,
      name: item?.product_name ?? item?.name ?? 'Product',
      // The snapshot carries no image, so the card shows its placeholder rather
      // than a picture fetched from a product that may have been delisted.
      imageUrl: null,
      size: item?.size ?? '',
      quantity,
      unitPrice,
      lineTotal: money(unitPrice * quantity),
    }
  })
}

/** What the customer's GCash is actually charged: the order total + the fee. */
export function chargedTotal({ orderTotal, feeAmount }) {
  return money(money(orderTotal) + money(feeAmount))
}

/**
 * The fee as a label: `2.23% + 12% VAT`.
 *
 * Built from the basis points the server reports rather than from a number
 * written here, so a rate change in `payment_fee_config` changes the sentence
 * the customer reads. `rate_bps` 223 → 2.23%, `vat_bps` 1200 → 12%.
 */
export function feeLabel(fee) {
  const rateBps = Number(fee?.rate_bps ?? fee?.rateBps)
  const vatBps = Number(fee?.vat_bps ?? fee?.vatBps)

  if (!Number.isFinite(rateBps)) return 'GCash fee'
  const rate = (rateBps / 100).toFixed(2)
  if (!Number.isFinite(vatBps) || vatBps <= 0) return `GCash fee (${rate}%)`
  return `GCash fee (${rate}% + ${(vatBps / 100).toFixed(0)}% VAT)`
}

/**
 * The order lines the intent function takes: `[{product_id, size, quantity}]`.
 *
 * Deliberately no prices. The server pins them, and sending ours would imply we
 * had a say in the amount — which is exactly what `reconcileServerTotal` exists
 * to check rather than assume.
 */
export function checkoutItems(lines) {
  return (lines ?? []).map((item) => ({
    product_id: item.productId,
    size: item.cartSize ?? item.size ?? '',
    quantity: Number(item.quantity) || 1,
  }))
}

/**
 * Compare the amount the server is about to charge with the amount we showed.
 *
 * This is a fail-safe, not a nicety. The client quotes from its own sale-aware
 * rules, and the server recomputes from the product rows; a disagreement means
 * one of the two is wrong, and the customer must never discover which by
 * looking at their GCash receipt. `tolerance` is one centavo: the server builds
 * its total in NUMERIC and we build ours in binary floating point, and a
 * rounding difference is not a discrepancy.
 */
export function reconcileServerTotal({ quoted, server, tolerance = 0.01 }) {
  const quotedValue = money(quoted)
  const serverValue = money(server)
  const delta = money(serverValue - quotedValue)

  return {
    matches: Math.abs(delta) <= tolerance,
    quoted: quotedValue,
    server: serverValue,
    delta,
    // Which way the surprise points, so the message can be specific rather than
    // "the totals differ".
    direction: delta > 0 ? 'higher' : 'lower',
  }
}

/** `left(order_id::text, 8)` — the short form the server's notifications use. */
export function shortOrderId(orderId) {
  return String(orderId ?? '').slice(0, 8)
}

/**
 * Where the payment window stands.
 *
 * The server sets 15 minutes at creation and returns the deadline as
 * `expires_at`, so this is a read of the server's timestamp and never a client
 * clock doing the deciding — the sweep can cancel an order the browser still
 * believes is live, and the UI has to be able to say so.
 */
export function deadlineState(deadline, now = new Date()) {
  if (!deadline) return { known: false, expired: false, msLeft: null }
  const end = new Date(deadline)
  if (Number.isNaN(end.getTime())) {
    return { known: false, expired: false, msLeft: null }
  }

  const msLeft = end.getTime() - now.getTime()
  return { known: true, expired: msLeft <= 0, msLeft, endsAt: end }
}

/** `14m 05s` — the countdown format the app's payment screen uses. */
export function formatCountdown(msLeft) {
  const total = Math.max(0, Math.floor((Number(msLeft) || 0) / 1000))
  const minutes = Math.floor(total / 60)
  const seconds = total % 60
  return `${minutes}m ${String(seconds).padStart(2, '0')}s`
}

/**
 * One word for what a poll of `get-payment-status` means, so no screen has to
 * re-derive it from four fields.
 *
 * The server's `paid` flag is authoritative and comes first. After that the
 * order's own status is the next authority: once the webhook confirms, the
 * order leaves `awaiting_payment` for the seller's pipeline, and a cancelled
 * order means the money was released. Only when the order is still awaiting
 * payment does the intent's own expiry matter — and even then this is a hint to
 * STOP showing a countdown, not a decision: the sweep is the decision.
 */
export function paymentState(
  { paid, orderStatus, paymentStatus, intentStatus, expiresAt } = {},
  now = new Date(),
) {
  if (paid || paymentStatus === 'paid') return 'paid'

  if (
    orderStatus === 'cancelled' ||
    paymentStatus === 'failed' ||
    intentStatus === 'expired' ||
    intentStatus === 'cancelled'
  ) {
    return 'cancelled'
  }

  // Anything that is no longer `awaiting_payment` has left the payment step,
  // so there is nothing left to poll for: whatever the webhook decided is
  // already in the order's own status.
  if (orderStatus && orderStatus !== 'awaiting_payment') return 'processing'

  if (deadlineState(expiresAt, now).expired) return 'expired'

  return 'awaiting'
}

/**
 * Which cart lines a paid order accounts for.
 *
 * The app is explicit about the timing here, and it is the right call: items
 * stay in the cart while payment is pending, so the customer can see what they
 * are paying for and retry or cancel freely — and are removed only once the
 * server confirms the order is paid. This decides *which* lines that means, by
 * matching the order's lines back to the cart on `(product_id, size)`.
 *
 * Size is compared digits-only, the same normalization the server uses to
 * resolve a size against `inventory`: "EU 40" and "40" are one size.
 */
export function cartLinesToClear(cartLines, orderItems) {
  const paid = new Set(
    (orderItems ?? []).map((item) => `${item.productId}|${sizeDigits(item.size)}`),
  )

  return (cartLines ?? [])
    .filter((line) =>
      paid.has(`${line.productId}|${sizeDigits(line.cartSize ?? line.size)}`),
    )
    .map((line) => line.id)
}

/**
 * Split the cart into the units an order can actually be placed in.
 *
 * Every order that has ever existed here belongs to ONE store, and the payment
 * intent keeps that shape: a single `store_id`, one order, one PayMongo session
 * charged to one maker.
 *
 * Splitting into one checkout per maker is not a workaround; it is the shape
 * the whole flow has, twice over — the order rows and the payment intents are
 * both singular, and a cart mixing makers has to become more than one payment.
 * So the customer pays one maker at a time, and the rest of the cart stays put.
 */
/**
 * ── Payment methods ──────────────────────────────────────────────────────
 *
 * The app's checkout offers **two**, in its own order and with its own words
 * (`checkout_screen.dart`: a `RadioGroup` of `GCash` and `Cash on Pickup`). The
 * portal offered one, which read as though paying in cash were not possible.
 *
 * They are not interchangeable, and the difference is the whole reason the two
 * need separate code paths rather than a label:
 *
 *   * **GCash** goes through `create-gcash-payment-intent` → PayMongo. The order
 *     is created in `awaiting_payment`, stock is NOT reserved
 *     (`defer-until-paid`), the lines are written by the webhook once the money
 *     moves, and the customer is handed to a hosted page in another tab.
 *   * **Cash on Pickup** is placed **immediately**, by the client, exactly as the
 *     app does it: an `orders` row in `pending` with `payment_status`
 *     `unpaid`, then one `order_items` row per line — and that insert is what
 *     decrements inventory, through `decrement_inventory_on_order`, which raises
 *     `Insufficient stock` when it cannot. There is no server function to route
 *     through: no `create_cash_order` RPC exists in this schema.
 *
 * `payment_method` is `TEXT NOT NULL DEFAULT 'cash'` with **no CHECK
 * constraint**, but the app normalizes what it stores (`_normalizePaymentMethod`)
 * and other screens read those words, so the portal normalizes identically rather
 * than writing `'Cash on Pickup'` into the column and hoping.
 */
export const PAYMENT_METHODS = [
  { value: 'gcash', label: 'GCash', hint: 'Pay the store directly via GCash' },
  { value: 'cash', label: 'Cash on Pickup', hint: 'Pay in cash when you collect it' },
]

/** GCash, because that is the app's initial value (`String _paymentMethod = 'GCash'`). */
export const DEFAULT_PAYMENT_METHOD = 'gcash'

/**
 * The app's `_normalizePaymentMethod`, including its default: anything that is
 * not GCash or a card is **cash**. That default is why an unrecognised value
 * must never reach the column — it would be stored as cash and read as cash.
 */
export function normalizePaymentMethod(value) {
  const text = String(value ?? '').trim().toLowerCase()
  if (text.includes('gcash')) return 'gcash'
  if (text.includes('card')) return 'card'
  return 'cash'
}

/**
 * A stored `payment_method` as a customer-facing label.
 *
 * Reads the *column*, which holds `'gcash'`/`'cash'`/`'card'` — not the label
 * the app's picker showed — so an order placed on a phone and an order placed
 * here print the same words on the receipt.
 *
 * Deliberately **not** built on `normalizePaymentMethod`: that function's job is
 * to decide what gets *written*, and its fallback turns anything it does not
 * recognise into `'cash'`. Labelling a stored `'paymaya'` as "Cash on Pickup"
 * would be a lie about somebody's order, so an unrecognised value keeps the
 * database's own word for it.
 */
export function paymentMethodLabel(value) {
  const text = String(value ?? '').trim()
  const method = text.toLowerCase()

  if (method.includes('gcash')) return 'GCash'
  if (method.includes('cash')) return 'Cash on Pickup'
  if (method.includes('card')) return 'Card'
  return text || 'Not recorded'
}

/** Whether the order is paid online, so a payment page or a fee applies. */
export function isOnlinePayment(value) {
  return normalizePaymentMethod(value) === 'gcash'
}

/**
 * The `orders` row a pay-in-person order becomes — the app's own payload from
 * `SupabaseService.createOrder`, field for field:
 *
 *   status `pending`   the maker's normal pipeline starts here, and the
 *                      `pending → placed → preparing → ready → received`
 *                      notification trigger fires on every step of it
 *   payment_status `unpaid`   `method == 'cash' ? 'unpaid' : 'paid'`
 *   fulfillment `pickup`      what the app writes for **every** online order,
 *                      delivery included — so the portal writes it too rather
 *                      than inventing a delivery/cash combination the app has
 *                      never produced and the seller side has never seen
 *
 * `total_amount` is the storefront's own sale-aware total (`quotedTotal`),
 * which is the same number the cart showed. Without a voucher there is no
 * trigger to reprice it, which is precisely why the total is computed from
 * `cartRules.lineTotal` rather than accepted from a caller.
 */
export function cashOrderInsert({
  userId,
  storeId,
  lines,
  deliveryAddress,
  shippingAddress,
}) {
  if (!userId || !storeId || !(lines ?? []).length) return null

  const totals = quotedTotal(lines)
  const insert = {
    customer_id: userId,
    store_id: storeId,
    status: 'pending',
    fulfillment: 'pickup',
    total_amount: totals.total,
    payment_method: 'cash',
    payment_status: 'unpaid',
    notes: String(deliveryAddress ?? '').trim() || null,
    source: 'online',
  }

  if (shippingAddress) insert.shipping_address = shippingAddress
  return insert
}

/**
 * The `order_items` rows for a placed cash order.
 *
 * One insert per line — deliberately not a batch, because the app does it one
 * at a time and the ORDER matters: when the fourth line is the one whose size
 * sold out, the first three have already decremented their inventory, and the
 * caller has to be able to roll all of them back. A single multi-row insert
 * would be atomic on the server and leave the portal with a different failure
 * story than the app has.
 *
 * `size` is the cart's own string. The app resolves it against `inventory`
 * first; the trigger compares sizes by their **digits**
 * (`regexp_replace(size, '\D', '', 'g')`), so the row that gets decremented is
 * the same either way, and the string stored on the order line is the one the
 * customer saw in their cart.
 */
export function orderItemInserts(orderId, lines) {
  if (!orderId) return []

  return (lines ?? []).map((item) => ({
    order_id: orderId,
    product_id: item.productId,
    size: item.cartSize ?? item.size ?? '',
    quantity: Number(item.quantity) || 1,
    unit_price: money(item.unitPrice),
  }))
}

/**
 * The database's stock rejection, as a sentence about the customer's own line.
 *
 * `decrement_inventory_on_order` raises
 * `Insufficient stock for product <uuid> size <size>` — a developer's message
 * with a UUID in it. The app turns it into
 * `StockUnavailableException.friendlyMessage` by naming the item it was
 * inserting at the time; the portal does the same by looking the product id up
 * in the lines it is placing.
 *
 * Returns null for anything that is not that error, so a caller can tell "the
 * pair sold out" apart from "the insert failed" — which are different things to
 * say to a customer, and only the first one means "go back to your cart".
 */
export function stockUnavailableMessage(error, lines) {
  const code = error?.code ?? null
  const raw = String(error?.message ?? '').trim()
  if (code !== 'P0001' || !/insufficient stock/i.test(raw)) return null

  /*
    `(\S+)` and not a UUID pattern: the trigger prints whatever `product_id` is
    (`%` in `raise exception … %`, which renders a uuid), and a parser that only
    accepted uuids would silently stop naming items the day a row's id was not
    one. The lookup below is by equality, so a non-matching token just falls back
    to "That pair".
  */
  const match = /insufficient stock for product\s+(\S+)\s+size\s+(.+)$/i.exec(raw)
  const productId = match?.[1] ?? null
  const line = (lines ?? []).find((item) => String(item.productId) === productId)

  const name = line?.productName ?? 'That pair'
  const size = line?.cartSize ?? line?.size ?? match?.[2] ?? ''
  return `${name} (size ${size}) is no longer available in that quantity. Update your cart and try again.`
}

/**
 * ── One maker at a time ──────────────────────────────────────────────────
 */
export function checkoutGroups(lines) {
  const groups = new Map()

  for (const item of lines ?? []) {
    const key = item.storeId ?? 'unknown'
    if (!groups.has(key)) {
      groups.set(key, {
        storeId: item.storeId ?? null,
        storeName: item.storeName ?? 'Unknown maker',
        items: [],
        subtotal: 0,
      })
    }
    const group = groups.get(key)
    group.items.push(item)
    group.subtotal = money(group.subtotal + lineTotal(item))
  }

  return [...groups.values()]
}
