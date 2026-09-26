import { cashOrderInsert, functionError, orderItemInserts, snapshotLines, stockUnavailableMessage } from './checkoutRules.js'
import { supabase } from './supabase.js'

// The rules live next door — including the error mapping, which encodes a
// non-obvious server quirk (see `checkoutRules.js`). Re-exported so screens have
// one import site for "checkout".
export * from './checkoutRules.js'

/**
 * Checkout's database operations.
 *
 * ## Which server route, and why it matters
 *
 * Online GCash here is **PayMongo Checkout Sessions** — the live path since
 * 2026-08-09 (`20260809000000_revive_paymongo_online_gcash.sql`). The
 * gateway-free attempt-#5 route (`create_gcash_checkout` +
 * `submit_gcash_proof`) was deprecated and CLOSED on 2026-09-05
 * (`20260905000000_fix_t5_manual_gcash_dedupe_audit.sql` §5), and its
 * order-creation RPC now answers `42501 permission denied` to a signed-in
 * caller. Verified against the deployed project, not inferred.
 *
 * So this module talks to two edge functions and three RPCs, and never writes
 * an order's money by hand:
 *
 *   invoke('create-gcash-payment-intent')  step 1 — creates the order in
 *                                          `awaiting_payment` and a hosted
 *                                          PayMongo session; returns the URL
 *   invoke('get-payment-status')           the authoritative poll; the client
 *                                          NEVER infers success from a redirect
 *   rpc('get_gcash_fee')                   the Model B surcharge, for the quote
 *   rpc('cancel_my_pending_payment_intent')  customer self-service cancel
 *
 * Stock is deliberately NOT reserved at step 1 (`defer-until-paid`): the
 * webhook inserts the order items and decrements inventory only once PayMongo
 * says the money moved. That is also why the cart keeps its lines until the
 * poll reports paid.
 */

/**
 * Place a **Cash on Pickup** order, immediately and by hand.
 *
 * The odd one out in this file, and it is odd on purpose: GCash goes through an
 * edge function so the server can revalidate stock, recompute the total from
 * current prices and own the charge. Cash has no charge to own, and this schema
 * has no `create_cash_order` RPC — the app places these with plain inserts and
 * so does the portal, rather than inventing a server path the app's own seller
 * screens have never seen an order arrive from.
 *
 * Three steps, and the middle one is where it can fail:
 *
 *  1. `orders` — `pending`, `payment_status: 'unpaid'`, `fulfillment: 'pickup'`.
 *     The customer INSERT policy is `auth.uid() = customer_id AND NOT
 *     is_suspended()`, so an expired session or a suspended account is refused
 *     here rather than half-written.
 *  2. `order_items`, one at a time. `decrement_inventory_on_order`
 *     (`SECURITY DEFINER`) decrements inventory inside each insert and raises
 *     `Insufficient stock` when it cannot — so **this** is the step that
 *     actually reserves the pair.
 *  3. Rollback: if any line fails, the rows already written are removed and the
 *     real error is re-thrown. Customers may delete their own `pending` orders
 *     (`20260704_add_orders_delete_policy.sql`) and the items cascade with the
 *     order, which is what makes the cleanup honest rather than best-effort —
 *     leaving a half-populated order would have the maker making pairs nobody
 *     paid for.
 */
export async function placeCashOrder({
  userId,
  storeId,
  lines,
  deliveryAddress,
  shippingAddress,
}) {
  const orderInsert = cashOrderInsert({
    userId,
    storeId,
    lines,
    deliveryAddress,
    shippingAddress,
  })
  if (!orderInsert) throw new Error('There is nothing to order.')

  let orderId = null
  const insertedItemIds = []

  try {
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .insert(orderInsert)
      .select('id, total_amount')
      .single()

    if (orderError) throw orderError
    orderId = order.id

    for (const payload of orderItemInserts(orderId, lines)) {
      const { data: item, error: itemError } = await supabase
        .from('order_items')
        .insert(payload)
        .select('id')
        .single()

      if (itemError) throw itemError
      insertedItemIds.push(item.id)
    }

    return {
      id: String(orderId),
      totalAmount: Number(order.total_amount) || 0,
    }
  } catch (error) {
    /*
      Roll back in the order the app does: the items first (so nothing is left
      pointing at a row that is about to disappear), then the order. Both are
      attempted even if the first fails, because a half-cleaned failure is worse
      than a slow one — and a rollback that cannot complete is still reported as
      the original error, never as its own.
    */
    if (insertedItemIds.length > 0) {
      try {
        await supabase.from('order_items').delete().in('id', insertedItemIds)
      } catch {
        /* best effort */
      }
    }
    if (orderId) {
      try {
        await supabase.from('orders').delete().eq('id', orderId)
      } catch {
        /* best effort */
      }
    }

    const soldOut = stockUnavailableMessage(error, lines)
    if (soldOut) {
      const mapped = new Error(soldOut)
      mapped.code = error?.code
      mapped.soldOut = true
      throw mapped
    }

    throw error
  }
}

/** The functions this flow uses. Named here so no caller holds a string. */
export const CREATE_INTENT_FUNCTION = 'create-gcash-payment-intent'
export const PAYMENT_STATUS_FUNCTION = 'get-payment-status'

/**
 * The customer's saved addresses, default first.
 *
 * The same order the app asks for (`is_default` desc, then `created_at` desc),
 * so both clients offer the same list in the same order and the convenience of
 * "the one I use most" is not a web-only behaviour.
 */
export async function fetchAddresses(userId) {
  const { data, error } = await supabase
    .from('customer_addresses')
    .select('*')
    .eq('user_id', userId)
    .order('is_default', { ascending: false })
    .order('created_at', { ascending: false })

  if (error) throw error
  return data ?? []
}

/**
 * Save an address to the customer's book.
 *
 * Returns the inserted row, which is the only reason checkout calls this before
 * placing an order rather than after: the stored `id` is what lets the next
 * checkout skip the form.
 *
 * The single-default rule is a database trigger, so passing `is_default: true`
 * is enough — the trigger clears the others, and no second write is needed.
 */
export async function createAddress(userId, payload) {
  const { data, error } = await supabase
    .from('customer_addresses')
    .insert({ ...payload, user_id: userId })
    .select()
    .single()

  if (error) throw error
  return data
}

/**
 * Edit a saved address.
 *
 * RLS scopes the write to the customer's own rows, so an id from anywhere else
 * is a zero-row update rather than somebody else's address being changed.
 * `updated_at` is set by the table's trigger, not by the caller.
 */
export async function updateAddress(id, payload) {
  const { data, error } = await supabase
    .from('customer_addresses')
    .update(payload)
    .eq('id', id)
    .select()
    .single()

  if (error) throw error
  return data
}

/** Remove a saved address. */
export async function deleteAddress(id) {
  const { error } = await supabase
    .from('customer_addresses')
    .delete()
    .eq('id', id)

  if (error) throw error
}

/**
 * Make one address the default.
 *
 * A single-column write on purpose: `enforce_single_default_address` un-sets
 * every other default for this customer when `is_default` goes true, so the
 * rule lives in one place and a second write here could only race it.
 */
export async function setDefaultAddress(id) {
  return updateAddress(id, { is_default: true })
}

/**
 * The Model B GCash surcharge for an order total.
 *
 * The rate is data (`payment_fee_config`) and the arithmetic is the server's
 * (`ceil_to_cent(order_total / (1 - r))`, where `r = rate × (1 + VAT)`), so this
 * asks rather than computes — a rate change must not require a web deploy, and
 * a client that re-derived the fee would eventually disagree with the charge.
 *
 * Returns `{ base, rateBps, vatBps, feeAmount, totalCharged }`, or null when the
 * call fails. A missing fee is not worth blocking a checkout over: the page
 * falls back to quoting the order total and saying the fee is added at payment,
 * and `reconcileServerTotal` still catches a surprise before any money moves.
 */
export async function fetchGcashFee(orderTotal) {
  const { data, error } = await supabase.rpc('get_gcash_fee', {
    p_subtotal: orderTotal,
  })
  if (error) throw error
  if (!data) return null

  return {
    base: Number(data.base) || 0,
    rateBps: Number(data.rate_bps) || 0,
    vatBps: Number(data.vat_bps) || 0,
    feeAmount: Number(data.fee_amount) || 0,
    totalCharged: Number(data.total_charged) || 0,
    raw: data,
  }
}

/**
 * A jsonb/RPC response, whether PostgREST hands back an object or a string.
 */
function asObject(data) {
  if (!data) return {}
  if (typeof data === 'string') {
    try {
      return JSON.parse(data)
    } catch {
      return {}
    }
  }
  return data
}

/**
 * Step 1 — create the order and the hosted PayMongo session.
 *
 * The server never trusts a client total: it revalidates stock, recomputes the
 * total from current product prices plus the fixed ₱100 delivery fee, and
 * derives what PayMongo charges from the stored totals. `idempotencyKey` is a
 * client uuid that makes a double-tap or a retry return the SAME session
 * instead of creating a second charge — which is why the caller caches one per
 * checkout attempt rather than generating a fresh one per click.
 */
export async function createPaymentIntent({
  idempotencyKey,
  items,
  deliveryAddress,
  shippingAddress,
  voucherCode,
}) {
  const { data, error } = await supabase.functions.invoke(
    CREATE_INTENT_FUNCTION,
    {
      body: {
        idempotency_key: idempotencyKey,
        items,
        delivery_address: deliveryAddress,
        shipping_address: shippingAddress,
        voucher_code: voucherCode ?? null,
      },
    },
  )

  if (error) throw await functionError(error, 'We could not start the GCash payment. Please try again.')
  const result = asObject(data)

  return {
    orderId: result.order_id ? String(result.order_id) : '',
    checkoutUrl: result.checkout_url ?? null,
    clientKey: result.client_key ?? null,
    // What PayMongo will charge: the order total PLUS the Model B fee.
    amount: Number(result.amount) || 0,
    feeAmount: Number(result.fee_amount) || 0,
    expiresAt: result.expires_at ?? null,
  }
}

/**
 * Step 2 — the authoritative payment status.
 *
 * The app's rule, kept: *never* infer success from landing on a redirect. The
 * customer may return from GCash on a different device, or not at all, so the
 * only thing that decides is this call (which the webhook has already settled
 * server-side).
 *
 * `get-payment-status` enforces ownership itself — it reads with the service
 * role and compares `customer_id` to the JWT — so a foreign order id is a 403
 * rather than somebody else's order.
 */
export async function fetchPaymentStatus(orderId) {
  const { data, error } = await supabase.functions.invoke(
    PAYMENT_STATUS_FUNCTION,
    { body: { order_id: orderId } },
  )

  if (error) throw await functionError(error, 'We could not check that payment.')
  const result = asObject(data)
  const payment = asObject(result.payment)

  return {
    orderId: String(result.order_id ?? orderId),
    status: result.status ?? null,
    paymentStatus: result.payment_status ?? null,
    totalAmount: Number(result.total_amount) || 0,
    paid: result.paid === true,
    cancellationReason: result.cancellation_reason ?? null,
    intentStatus: payment.status ?? null,
    amount: payment.amount === undefined ? null : Number(payment.amount),
    // The fee is reported here too, which is what lets a resumed visit show the
    // same breakdown as a fresh one — nothing has to be carried in navigation
    // state for the numbers to add up.
    feeAmount:
      payment.fee_amount === undefined ? null : Number(payment.fee_amount),
    expiresAt: payment.expires_at ?? null,
    checkoutUrl: payment.checkout_url ?? null,
  }
}

/**
 * Cancel an unpaid intent and release the order.
 *
 * Server-guarded: the caller must own the order, and the transition only
 * applies while it is still awaiting payment. Returns `false` when the order
 * had already resolved — a normal outcome to report, not an error.
 */
export async function cancelPendingPaymentIntent(orderId) {
  const { data, error } = await supabase.rpc(
    'cancel_my_pending_payment_intent',
    { p_order_id: orderId },
  )
  if (error) throw error
  return data === true
}

/**
 * The customer's currently-open checkout, if any.
 *
 * A port of the app's `fetchPendingIntent`, including its second step: the
 * intent row is not enough, because the webhook can win a race and settle the
 * order while the row still says `pending`. So the order's status is checked
 * too, and a settled order returns null here rather than being offered as
 * something to resume.
 *
 * `null` means "genuinely nothing pending" — a failed read throws instead, so
 * the caller can tell "nothing pending" apart from "could not check". Showing a
 * reassuring "no pending order" on a network blip is how a customer pays twice.
 */
export async function fetchPendingIntent(userId) {
  const { data, error } = await supabase
    .from('payment_intents')
    .select(
      'order_id, checkout_url, client_key, amount, fee_amount, expires_at, status',
    )
    .eq('customer_id', userId)
    .eq('status', 'pending')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error) throw error
  if (!data) return null

  const { data: order, error: orderError } = await supabase
    .from('orders')
    .select('status')
    .eq('id', data.order_id)
    .maybeSingle()

  if (orderError) throw orderError
  if (!order || order.status !== 'awaiting_payment') return null

  return {
    orderId: String(data.order_id),
    checkoutUrl: data.checkout_url ?? null,
    amount: Number(data.amount) || 0,
    feeAmount: Number(data.fee_amount) || 0,
    expiresAt: data.expires_at ?? null,
    intentStatus: data.status,
  }
}

/**
 * An order with its lines, for the states after payment.
 *
 * RLS scopes this to the customer's own orders, so an id from somewhere else
 * returns nothing rather than somebody's order. Note what is NOT here while the
 * payment is pending: the order items. They are inserted by the webhook, so
 * before it fires the order legitimately has no lines and the pending screen
 * shows the cart's instead.
 */
export async function fetchOrder(orderId) {
  const { data, error } = await supabase
    .from('orders')
    .select(
      `*,
       stores(name),
       order_items(
         id, product_id, size, quantity, unit_price,
         products(name, product_images(image_url, display_order))
       )`,
    )
    .eq('id', orderId)
    .maybeSingle()

  if (error) throw error
  if (!data) return null

  const orderItems = (data.order_items ?? []).map((row) => {
    const images = [...(row.products?.product_images ?? [])].sort(
      (a, b) => (a?.display_order ?? 0) - (b?.display_order ?? 0),
    )
    const quantity = Number(row.quantity) || 1
    const unitPrice = Number(row.unit_price) || 0
    return {
      id: String(row.id),
      productId: String(row.product_id),
      name: row.products?.name ?? 'Product',
      imageUrl: images[0]?.image_url ?? null,
      size: row.size ?? '',
      quantity,
      unitPrice,
      lineTotal: Math.round(unitPrice * quantity * 100) / 100,
    }
  })

  /*
    Before the webhook confirms, `order_items` is empty on purpose — the lines
    exist only as the snapshot the intent function wrote. Preferring the real
    rows and falling back to the snapshot means one code path serves both the
    pending and the paid state, and a resumed visit shows the same basket a
    fresh one does.
  */
  const items =
    orderItems.length > 0 ? orderItems : snapshotLines(data.items_snapshot)

  return {
    id: String(data.id),
    status: data.status,
    paymentStatus: data.payment_status,
    totalAmount: Number(data.total_amount) || 0,
    createdAt: data.created_at ?? null,
    cancellationReason: data.cancellation_reason ?? null,
    shippingAddress: data.shipping_address ?? null,
    deliveryAddress: data.notes ?? '',
    storeName: data.stores?.name ?? 'the maker',
    // The fee as the payment was created with it, so the breakdown on screen
    // always adds up to the amount that was charged.
    feeAmount: Number(data.gcash_fee_amount) || 0,
    feeRateBps: Number(data.gcash_fee_rate_bps) || 0,
    feeVatBps: Number(data.gcash_fee_vat_bps) || 0,
    items,
  }
}
