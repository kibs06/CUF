import { effectivePrice } from './pricing.js'

/**
 * Cart rules — the pure half of the cart, ported from
 * `lib/utils/cart_helpers.dart` and the row mapping in
 * `lib/services/cart_service.dart`.
 *
 * Split out from `cart.js` for one practical reason and one real one. The
 * practical one: `cart.js` imports the Supabase client at module level, so it
 * cannot be loaded in plain Node, and these functions are exactly the ones
 * worth testing. The real one: everything here is money and availability —
 * what the customer pays, and whether the thing they are paying for exists —
 * and that is the part that should be provable without a network.
 */

/** Strip an alpha prefix: "EU40" → "40". Letters only, matching the app. */
export function normalizeSize(size) {
  return String(size ?? '').replace(/[A-Za-z]+/g, '')
}

/**
 * Stock for a cart line's size, or **-1 when no inventory row matches**.
 *
 * There is deliberately NO fallback to "first available size". The Dart helper
 * documents the same choice: an unmatched size is a data problem, and quietly
 * resolving it to a different size's stock is how a customer reaches checkout
 * with something unbuyable. `-1` keeps that visible, and `0` stays reserved for
 * a size that exists and is genuinely empty.
 */
export function resolveInventoryStock({ inventoryRows, cartSize }) {
  if (!Array.isArray(inventoryRows) || inventoryRows.length === 0) return -1
  if (!cartSize) return -1

  const wanted = String(cartSize)

  for (const row of inventoryRows) {
    if (String(row?.size ?? '') === wanted) return Number(row?.stock) || 0
  }

  const normalizedWanted = normalizeSize(wanted)
  if (!normalizedWanted) return -1

  for (const row of inventoryRows) {
    if (normalizeSize(row?.size) === normalizedWanted) {
      return Number(row?.stock) || 0
    }
  }

  return -1
}

/**
 * The variant for a chosen size and colour.
 *
 * Mirrors the app's `resolveVariant`, including its tie-break: prefer an exact
 * colour match, but accept any variant for that size rather than returning
 * nothing — so a product whose variants carry no colour still resolves.
 */
export function resolveVariant({ variants, size, color }) {
  let variantId = null
  let additionalPrice = 0

  for (const variant of variants ?? []) {
    if (String(variant?.size ?? '') !== String(size ?? '')) continue

    const sameColor = String(variant?.color ?? '') === String(color ?? '')
    if (sameColor || variantId === null) {
      variantId = variant?.id ? String(variant.id) : null
      additionalPrice = Number(variant?.additional_price) || 0
      if (sameColor) break
    }
  }

  return { variantId, additionalPrice }
}

/**
 * One `cart_items` row → the shape the cart UI renders.
 *
 * Two rules are copied from the Dart side rather than improved:
 *
 *  1. **`cart_items` stores no price snapshot.** The line price is recomputed
 *     from the product row on every read, so a product that went on sale after
 *     it was added restores at the sale price.
 *  2. **Size authority is cart → variant → inventory**, and stock prefers the
 *     variant before falling back to the inventory row for that size.
 */
export function mapCartItem(
  row,
  { storeNames = {}, inventoryStock = {}, inventorySizes = {} } = {},
) {
  const product = row?.products ?? {}
  const variant = row?.product_variants ?? null

  const images = [...(product.product_images ?? [])].sort(
    (a, b) => (a?.display_order ?? 0) - (b?.display_order ?? 0),
  )
  const imageUrl = images[0]?.image_url ?? null

  const productId = String(row.product_id)
  const storeId = product.store_id ? String(product.store_id) : null

  const rawCartSize = row?.size ? String(row.size) : null
  let size = rawCartSize ?? ''
  if (!size && variant?.size) size = String(variant.size)
  if (!size && inventorySizes[productId]) size = inventorySizes[productId]

  let stock = Number(variant?.stock) || 0
  if (stock <= 0 && size) {
    stock = inventoryStock[`${productId}-${size}`] ?? 0
  }

  const basePrice = effectivePrice({
    price: product.price,
    sale_price: product.sale_price,
    sale_starts_at: product.sale_starts_at,
    sale_ends_at: product.sale_ends_at,
  })
  const additionalPrice = Number(variant?.additional_price) || 0
  const quantity = Number(row.quantity) || 1

  return {
    id: String(row.id),
    userId: String(row.user_id),
    productId,
    variantId: row.variant_id ? String(row.variant_id) : null,
    quantity,
    customizations: row.customizations ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,

    productName: product.name ?? 'Unknown Product',
    imageUrl,
    isActive: product.is_active ?? true,

    storeId,
    storeName: storeNames[storeId] ?? 'Unknown Store',

    // Mirrors `CartItemWithDetails.unitPrice`: price + additionalPrice.
    basePrice,
    additionalPrice,
    unitPrice: basePrice + additionalPrice,

    size,
    cartSize: rawCartSize,
    color: variant?.color ?? null,
    stock,
  }
}

/** Line total = unitPrice × quantity. */
export function lineTotal(item) {
  return (Number(item?.unitPrice) || 0) * (Number(item?.quantity) || 1)
}

export function cartSubtotal(items) {
  return (items ?? []).reduce((sum, item) => sum + lineTotal(item), 0)
}

/** Total UNITS, not lines — what the header badge counts. */
export function cartCount(items) {
  return (items ?? []).reduce(
    (sum, item) => sum + (Number(item?.quantity) || 1),
    0,
  )
}

/**
 * Why a line cannot be bought as configured, or null when it can.
 *
 * The third case is the one a plain "in stock" badge misses: three left is in
 * stock, but not for a quantity of five.
 */
export function unavailableReason(item) {
  if (!item?.isActive) return 'No longer available'
  if (item.stock <= 0) return 'Out of stock'
  if (item.quantity > item.stock) return `Only ${item.stock} left`
  return null
}

/**
 * ── Selection ────────────────────────────────────────────────────────────
 *
 * A port of `CartProvider`'s `_selectedKeys` and everything computed from it.
 * The app's cart is a *checklist*: opening it selects nothing, each line has a
 * checkbox, each store has a tri-state checkbox, and the summary reads only the
 * selected lines — so "which of these am I buying" is answered **before**
 * checkout rather than on the checkout screen.
 *
 * The portal had the opposite order: its cart totalled everything and its
 * checkout asked the customer to pick a maker. That is a different question
 * asked at the wrong moment — and it hid the app's real rule, that the summary
 * belongs to the selection. These functions are that rule, separated from React
 * so the arithmetic can be tested without a browser.
 *
 * The key is the app's own: `productId-size-color`
 * (`'$productId-$size-${color ?? 'none'}'` in `CartProvider.addToCart`). It is
 * deliberately NOT the cart row's id — a line that has not reached the server
 * yet has no id, and a line whose quantity changes keeps the same identity, so
 * a selection made a second ago must survive both.
 */

export function cartItemKey(item) {
  const productId = String(item?.productId ?? '')
  const size = String(item?.size ?? '')
  const color = item?.color ? String(item.color) : 'none'
  return `${productId}-${size}-${color}`
}

/** Every selectable key in the cart, in list order. */
export function cartItemKeys(items) {
  return (items ?? []).map(cartItemKey)
}

const selectable = (items, selectedKeys) =>
  (items ?? []).filter((item) => selectedKeys?.has?.(cartItemKey(item)))

/** The selected LINES — the app's `selectedItems`. */
export function selectedItems(items, selectedKeys) {
  return selectable(items, selectedKeys)
}

/**
 * The selected UNITS — the app's `selectedCount`.
 *
 * Units, not lines: a customer with two pairs of the same sandal has selected
 * two things, and the button that says "Checkout" has to agree with the header
 * badge that says 2 as well.
 */
export function selectedUnitCount(items, selectedKeys) {
  return selectable(items, selectedKeys).reduce(
    (sum, item) => sum + (Number(item?.quantity) || 1),
    0,
  )
}

/** The selected subtotal — the app's `selectedSubtotal`. */
export function selectedSubtotal(items, selectedKeys) {
  return selectable(items, selectedKeys).reduce(
    (sum, item) => sum + lineTotal(item),
    0,
  )
}

/**
 * The delivery fee for a selection — the app's `selectedDeliveryFee`.
 *
 * **Flat, and charged once**: `selectedSubtotal > 0 ? 100.0 : 0.0`. The fee is a
 * parameter rather than an import because `checkoutRules.js` already imports
 * this file, and reaching back the other way would be a cycle — the caller that
 * owns the number (`DELIVERY_FEE`, the same one the payment intent adds) passes
 * it in.
 *
 * This is also a bug fix. The cart used to show a fee *per maker* while the
 * checkout charged one fee for the single order it creates, so a two-maker cart
 * quoted ₱651 and then charged ₱551. Quoting the app's rule fixes the
 * disagreement in the direction of what is actually taken from the customer.
 */
export function selectedDeliveryFee(items, selectedKeys, fee) {
  const amount = Number(fee) || 0
  return selectedSubtotal(items, selectedKeys) > 0 ? amount : 0
}

/** Subtotal + the one delivery fee. */
export function selectedTotal(items, selectedKeys, fee) {
  const subtotal = selectedSubtotal(items, selectedKeys)
  return subtotal + selectedDeliveryFee(items, selectedKeys, fee)
}

/** Whether every line is selected — the app's `allSelected`. */
export function allItemsSelected(items, selectedKeys) {
  const keys = cartItemKeys(items)
  return keys.length > 0 && keys.every((key) => selectedKeys?.has?.(key))
}

/**
 * A store's checkbox state: `'all'`, `'none'`, or `'some'` for the indeterminate
 * middle — the app's `isStoreFullySelected` / `isStorePartiallySelected`
 * collapsed into the three states a checkbox can actually be drawn in.
 */
export function storeSelection(items, selectedKeys, storeId) {
  const keys = (items ?? [])
    .filter((item) => (item?.storeId ?? null) === storeId)
    .map(cartItemKey)

  if (keys.length === 0) return 'none'
  const selected = keys.filter((key) => selectedKeys?.has?.(key)).length
  if (selected === 0) return 'none'
  return selected === keys.length ? 'all' : 'some'
}

/** Toggle one line — `CartProvider.toggleItem`. */
export function toggleItemSelection(selectedKeys, item) {
  const next = new Set(selectedKeys ?? [])
  const key = cartItemKey(item)
  if (next.has(key)) next.delete(key)
  else next.add(key)
  return next
}

/**
 * Toggle a whole store — `CartProvider.toggleStore`.
 *
 * Note the direction: a store that is *partly* selected becomes fully selected
 * (it is not cleared), which is what makes the indeterminate box behave like a
 * "select all of these" rather than a coin toss.
 */
export function toggleStoreSelection(selectedKeys, items, storeId) {
  const next = new Set(selectedKeys ?? [])
  const keys = (items ?? [])
    .filter((item) => (item?.storeId ?? null) === storeId)
    .map(cartItemKey)

  const fullySelected = keys.length > 0 && keys.every((key) => next.has(key))
  for (const key of keys) {
    if (fullySelected) next.delete(key)
    else next.add(key)
  }
  return next
}

/** Toggle everything — `CartProvider.toggleAll`. */
export function toggleAllSelection(selectedKeys, items) {
  if (allItemsSelected(items, selectedKeys)) return new Set()
  return new Set(cartItemKeys(items))
}

/**
 * Group lines by store, preserving first-appearance order.
 *
 * Order of appearance rather than alphabetical: the cart is built over time,
 * and re-sorting it on every add would move the line the customer is looking
 * at out from under the cursor.
 */
export function groupByStore(items) {
  const groups = []
  const index = new Map()

  for (const item of items ?? []) {
    const key = item.storeId ?? 'unknown'
    if (!index.has(key)) {
      index.set(key, groups.length)
      groups.push({
        storeId: item.storeId,
        storeName: item.storeName ?? 'Unknown Store',
        items: [],
      })
    }
    groups[index.get(key)].items.push(item)
  }

  return groups
}
