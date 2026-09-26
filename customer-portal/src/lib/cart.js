import { mapCartItem } from './cartRules.js'
import { supabase } from './supabase.js'

// The pure rules live next door (see `cartRules.js` for why), and are
// re-exported here so the UI has one import site for "the cart".
export * from './cartRules.js'

/**
 * The cart's database operations — a port of `lib/services/cart_service.dart`.
 *
 * **This is the app's own `cart_items` table**, not a browser-local cart. That
 * is the entire point: a pair added on a phone must be waiting in this cart on
 * a laptop. A local-storage cart would be a second, invisible cart that the app
 * knows nothing about.
 */

/** The relations the cart reads — the app's own select, unchanged. */
export const CART_SELECT = `
  *,
  products!inner(
    name, is_active, price, sale_price, sale_starts_at,
    sale_ends_at, store_id,
    product_images(image_url, display_order)
  ),
  product_variants(
    id, size, color, stock, additional_price
  )
`

/**
 * The customer's cart, fully resolved.
 *
 * Three round trips, and they are batched rather than per-line: the lines, the
 * store names behind them, and — only for lines whose variant did not already
 * answer the stock question — the inventory rows.
 */
export async function fetchCart(userId) {
  const { data, error } = await supabase
    .from('cart_items')
    .select(CART_SELECT)
    .eq('user_id', userId)
    .order('created_at', { ascending: true })

  if (error) throw error
  const rows = data ?? []

  // ── Store names, one query for all of them ──
  const storeIds = [
    ...new Set(rows.map((row) => row.products?.store_id).filter(Boolean)),
  ]
  const storeNames = {}
  if (storeIds.length > 0) {
    const { data: stores, error: storeError } = await supabase
      .from('stores')
      .select('id, name')
      .in('id', storeIds)
    if (storeError) throw storeError
    for (const store of stores ?? []) {
      storeNames[store.id] = store.name ?? 'Unknown Store'
    }
  }

  // ── Inventory fallback, only for lines with no variant row ──
  const fallbackProductIds = [
    ...new Set(
      rows.filter((row) => !row.product_variants).map((row) => row.product_id),
    ),
  ]
  const inventoryStock = {}
  const inventorySizes = {}
  if (fallbackProductIds.length > 0) {
    const { data: inventoryRows, error: inventoryError } = await supabase
      .from('inventory')
      .select('product_id, size, stock')
      .in('product_id', fallbackProductIds)
      .gt('stock', 0)
    if (inventoryError) throw inventoryError

    for (const inventory of inventoryRows ?? []) {
      const productId = String(inventory.product_id)
      const size = inventory.size?.toString() ?? ''
      const key = `${productId}-${size}`
      inventoryStock[key] =
        (inventoryStock[key] ?? 0) + (Number(inventory.stock) || 0)
      if (!(productId in inventorySizes) && size) {
        inventorySizes[productId] = size
      }
    }
  }

  return rows.map((row) =>
    mapCartItem(row, { storeNames, inventoryStock, inventorySizes }),
  )
}

/**
 * Add to the cart, or increment an existing line.
 *
 * Deliberately a manual find-then-write rather than an upsert, exactly as the
 * app does it: the sameness a customer means by "the same item" is
 * `(user_id, product_id, variant_id)`, and **PostgreSQL treats NULL as distinct
 * in a unique index** — so an upsert would not dedupe two rows with a null
 * `variant_id` (which is most of them), and the customer would silently end up
 * with two lines of the same product.
 *
 * Returns the row id.
 */
export async function addOrUpdateItem({
  userId,
  productId,
  variantId = null,
  quantity,
  customizations = null,
  size = null,
}) {
  let query = supabase
    .from('cart_items')
    .select('id, quantity')
    .eq('user_id', userId)
    .eq('product_id', productId)

  query = variantId
    ? query.eq('variant_id', variantId)
    : query.is('variant_id', null)

  const { data: existing, error: findError } = await query.maybeSingle()
  if (findError) throw findError

  if (existing) {
    const update = { quantity: Number(existing.quantity) + quantity }
    if (size !== null) update.size = size

    const { error } = await supabase
      .from('cart_items')
      .update(update)
      .eq('id', existing.id)
    if (error) throw error

    return String(existing.id)
  }

  const { data, error } = await supabase
    .from('cart_items')
    .insert({
      user_id: userId,
      product_id: productId,
      variant_id: variantId,
      quantity,
      customizations,
      size,
    })
    .select('id')
    .single()

  if (error) throw error
  return String(data.id)
}

/** Set an absolute quantity. Zero or less deletes the line rather than storing a 0. */
export async function updateQuantity({ cartItemId, newQuantity }) {
  if (newQuantity <= 0) {
    const { error } = await supabase
      .from('cart_items')
      .delete()
      .eq('id', cartItemId)
    if (error) throw error
    return
  }

  const { error } = await supabase
    .from('cart_items')
    .update({ quantity: newQuantity })
    .eq('id', cartItemId)
  if (error) throw error
}

export async function removeItem(cartItemId) {
  const { error } = await supabase
    .from('cart_items')
    .delete()
    .eq('id', cartItemId)
  if (error) throw error
}

/** Remove specific lines. Used after an order to clear only what was ordered. */
export async function removeItems(userId, cartItemIds) {
  if (!cartItemIds?.length) return
  const { error } = await supabase
    .from('cart_items')
    .delete()
    .eq('user_id', userId)
    .in('id', cartItemIds)
  if (error) throw error
}

export async function clearCart(userId) {
  const { error } = await supabase
    .from('cart_items')
    .delete()
    .eq('user_id', userId)
  if (error) throw error
}
