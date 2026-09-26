import { supabase } from './supabase.js'

// The rules live next door — including the error mapping, which encodes a
// non-obvious server state (see `cancelError` in `orderRules.js`). Re-exported
// so screens have one import site for "orders".
export * from './orderRules.js'

/**
 * The customer's order history.
 *
 * ## Two things this file has to know about the schema
 *
 * 1. **`order_items` is written late.** The PayMongo flow is
 *    `defer-until-paid`: the webhook materializes the line rows only after the
 *    money moves, so while a payment is pending — and on any order cancelled
 *    before payment — the table is legitimately empty for that order.
 *    `items_snapshot` is the record in those cases, which is why it is selected
 *    here and why `orderLines` falls back to it.
 * 2. **Cancelling is not an UPDATE.** `orders` has no customer UPDATE policy,
 *    so the app's `cancelOrder` (a bare client UPDATE) matches zero rows and
 *    reports success anyway. Verified against the deployed project. The write
 *    therefore goes through `cancel_my_order` — see
 *    `20260925140000_add_cancel_my_order_rpc.sql`.
 *
 * ## Relationship to `checkout.js#fetchOrder`
 *
 * Both read an order and both are deliberate. That one is the PAYMENT page's
 * view — it carries the stored fee rate/VAT so its breakdown adds up to the
 * amount charged — and is used while a payment is in flight. This one is the
 * HISTORY view: every order, with its status timeline. They select different
 * columns because they answer different questions; neither should be bent to
 * serve the other.
 */

/**
 * The read-only select.
 *
 * `order_status_history` is embedded so the timeline and the 'preparing'
 * cancellation window come from the same round trip as the order itself —
 * `order_status_history` is readable for a customer's own orders by policy, and
 * fetching it separately would mean a silent gap whenever the second call
 * failed.
 */
export const ORDER_SELECT = [
  '*',
  'stores(name)',
  'order_items(id, product_id, size, quantity, unit_price, products(name, product_images(image_url, display_order, is_primary)))',
  'order_status_history(id, status, changed_at)',
].join(', ')

/**
 * A row → the shape the rules and screens expect.
 *
 * The raw row is spread first so an untouched column stays reachable, exactly
 * as `mapProduct` does in `catalog.js`.
 */
export function mapOrder(row) {
  if (!row) return null

  return {
    ...row,
    id: String(row.id),
    store_id: row.store_id ? String(row.store_id) : null,
    store_name: row.stores?.name ?? null,
    total_amount: Number(row.total_amount) || 0,
    order_items: Array.isArray(row.order_items) ? row.order_items : [],
    order_status_history: Array.isArray(row.order_status_history)
      ? row.order_status_history
      : [],
  }
}

/**
 * Every order this customer has placed, newest first.
 *
 * Filtered on `customer_id` as well as relying on RLS: the policy already
 * scopes rows, and the explicit predicate is what lets Postgres use
 * `orders_customer_id_idx` instead of filtering after the fact. An order with a
 * NULL `customer_id` — the shape an anon-created order used to have before
 * 2026-09-25 — is therefore not in anybody's history, which is correct: nobody
 * placed it.
 */
export async function fetchMyOrders(userId) {
  const { data, error } = await supabase
    .from('orders')
    .select(ORDER_SELECT)
    .eq('customer_id', userId)
    .order('created_at', { ascending: false })

  if (error) throw error
  return (data ?? []).map(mapOrder).filter(Boolean)
}

/**
 * One order, with its lines and timeline.
 *
 * `maybeSingle` rather than `single`: a foreign or deleted order id is a
 * legitimate `null` here, and the page renders "we could not find that order"
 * instead of an exception. RLS makes somebody else's order indistinguishable
 * from a missing one, which is the intended answer.
 */
export async function fetchMyOrder(orderId) {
  const { data, error } = await supabase
    .from('orders')
    .select(ORDER_SELECT)
    .eq('id', orderId)
    .maybeSingle()

  if (error) throw error
  return mapOrder(data)
}

/**
 * Cancel an order, or ask the maker to.
 *
 * The server decides which of the two it is (`pending`/`placed` → cancelled,
 * `preparing` inside its two-hour window → a request) and enforces the same
 * rules `cancelPlan` shows in the UI. Nothing about the transition is decided
 * here, including the reason strings — the list comes from
 * `CANCELLATION_REASONS`, which is the app's own list.
 *
 * Resolves to `{ orderId, status, requested }`.
 */
export async function cancelOrder({ orderId, reason, details }) {
  const { data, error } = await supabase.rpc('cancel_my_order', {
    p_order_id: orderId,
    p_reason: reason,
    p_details: details ?? null,
  })

  if (error) throw error

  const result = asObject(data)
  return {
    orderId: result.order_id ? String(result.order_id) : String(orderId),
    status: result.status ?? null,
    requested: result.requested === true,
  }
}

/** A jsonb/RPC response, whether PostgREST hands back an object or a string. */
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
