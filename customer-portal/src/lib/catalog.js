import { PRODUCT_CATEGORIES } from './constants'
import { supabase } from './supabase'

/**
 * The customer-facing product select.
 *
 * Character-for-character the same relation list the app uses in
 * `SupabaseService.fetchProducts` — including `is_primary` on product_images,
 * which exists so both the app and the admin portal pick the same primary
 * image. If a column is added for the app, it is added here; the two must read
 * the same shape or the mapping below starts guessing.
 */
export const PRODUCT_SELECT = [
  '*',
  'stores(name)',
  'product_images(image_url, display_order, is_primary)',
  'inventory(size, stock)',
  'product_variants(size, stock, color)',
  'product_color_images(url, color_name, display_order)',
].join(', ')

/**
 * A row → the shape every component below expects. A port of the app's
 * `_mapProduct`, so the same field names mean the same things on both sides.
 *
 * Note what is deliberately kept as well as added: the raw row is spread first,
 * so an untouched column (description, category, audience, collection, sku) is
 * available to components without this function having to know about it.
 */
export function mapProduct(row) {
  if (!row) return null

  const productImages = Array.isArray(row.product_images)
    ? [...row.product_images]
    : []
  productImages.sort(
    (a, b) => (a?.display_order ?? 0) - (b?.display_order ?? 0),
  )

  const inventory = Array.isArray(row.inventory) ? row.inventory : []
  const sizes = {}
  for (const item of inventory) {
    sizes[String(item?.size)] = Number(item?.stock) || 0
  }

  const images = productImages
    .map((image) => image?.image_url)
    .filter((url) => typeof url === 'string' && url.length > 0)

  return {
    ...row,
    id: String(row.id),
    price: Number(row.price) || 0,
    sale_price:
      row.sale_price === null || row.sale_price === undefined
        ? null
        : Number(row.sale_price),
    images,
    sizes,
    store_name: row.stores?.name ?? null,
  }
}

/**
 * The catalog. Out-of-stock products are NOT filtered here — the caller
 * decides, because a store page may want to show "sold out" while the browse
 * feed hides them (see `purchasableProducts`).
 *
 * **Unpublished products ARE filtered, and that is a fix rather than a
 * preference.** The seller form's "Show on the storefront" checkbox writes
 * `is_published`, and until this `eq` existed nothing on any customer surface
 * read the column — so a seller could uncheck it, watch the badge appear in their
 * own product list, and leave the pair on sale to every customer. The column
 * defaults to `true` and the app never writes it, so the only products this can
 * hide are ones a seller deliberately hid.
 *
 * Hidden in both reads: the list and the single product. A hidden product's URL
 * would otherwise still render, which is exactly what unchecking the box was
 * meant to stop.
 */
export async function fetchProducts({ storeId } = {}) {
  let query = supabase
    .from('products')
    .select(PRODUCT_SELECT)
    .eq('is_published', true)

  if (storeId) query = query.eq('store_id', storeId)

  const { data, error } = await query.order('created_at', {
    ascending: false,
  })
  if (error) throw error

  return (data ?? []).map(mapProduct).filter(Boolean)
}

export async function fetchProductById(productId) {
  const { data, error } = await supabase
    .from('products')
    .select(PRODUCT_SELECT)
    .eq('id', productId)
    .eq('is_published', true)
    .maybeSingle()

  if (error) throw error
  return mapProduct(data)
}

/**
 * Every open store, newest first — `StoreService.fetchAllStores`'s query.
 * `is_active` is the same predicate the app filters on, so a deactivated store
 * disappears from the portal at the same moment it disappears from the app.
 */
export async function fetchStores() {
  const { data, error } = await supabase
    .from('stores')
    .select('*')
    .eq('is_active', true)
    .order('created_at', { ascending: false })

  if (error) throw error
  return data ?? []
}

export async function fetchStoreById(storeId) {
  const { data, error } = await supabase
    .from('stores')
    .select('*')
    .eq('id', storeId)
    .maybeSingle()

  if (error) throw error
  return data
}

/**
 * The categories worth offering as filter chips.
 *
 * The app's rule, unchanged: the canonical list first, then any category that
 * actually exists on a product but is not in it. Sellers can still save a free
 * text category, and a filter that cannot reach the products it is describing
 * is worse than no filter — so real data always wins over the preset list.
 *
 * Categories with nothing in them are omitted rather than shown disabled: a
 * chip that exists to be un-clickable is a dead end dressed as a control.
 */
export function catalogCategories(products) {
  const present = new Set()
  for (const product of products ?? []) {
    const value = product?.category
    if (typeof value === 'string' && value.trim()) present.add(value.trim())
  }

  const canonical = PRODUCT_CATEGORIES.filter((category) =>
    present.has(category),
  )
  const extra = [...present]
    .filter((category) => !PRODUCT_CATEGORIES.includes(category))
    .sort((a, b) => a.localeCompare(b))

  return [...canonical, ...extra]
}
