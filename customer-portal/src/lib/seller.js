import { supabase } from './supabase.js'
import {
  customizationRowsForInsert,
  customizationsFromProduct,
} from './productCustomizations.js'
import { productColumnsFromDraft } from './productDraft.js'
import { colourImagePath, colourImagesFor } from './productColourImages.js'
import { inventoryRowsFromVariants, variantRowsForInsert } from './productVariants.js'

// The rules live next door — including `sellerOrderActions`, which is what
// decides which status a button is allowed to write. Re-exported so screens
// have one import site for "seller".
export * from './sellerRules.js'

/**
 * Seller data access, mirroring `store_service.dart`, `product_service.dart`
 * and `supabase_service.dart#updateOrderStatus`.
 *
 * ## The three schema facts this file exists to respect
 *
 * 1. **A seller owns at most one store**, found by `stores.owner_id` — not by a
 *    `store_id` on the profile. `store_service.dart` enforces the one-store
 *    rule at creation; this reads the same relationship.
 * 2. **`inventory` is DERIVED from `product_variants`** and there is no
 *    database trigger that maintains it — the schema comment that says
 *    `_syncInventoryFromVariants()` syncs it names a *Dart* function. The
 *    aggregation is therefore done here, by the same rule: sum each size's
 *    stock across its colours. Writing `product_variants` without re-syncing
 *    would leave the customer's size selector and the checkout decrement
 *    reading a stale table.
 * 3. **An order-status write is not one write.** The app updates `orders` and
 *    then inserts an `order_status_history` row; skipping the history leaves
 *    the customer's timeline missing the step and breaks the two-hour
 *    cancellation window, which is measured from the `preparing` history row.
 */

/**
 * The seller's order select.
 *
 * `profiles!orders_customer_id_fkey` is the exact embed the app's push
 * deep-link handler uses, so a seller sees the same customer name on both
 * surfaces. `order_items` carries the live lines and `items_snapshot` stands in
 * for the ones the payment flow has not written yet — an order still awaiting
 * payment has none.
 */
export const SELLER_ORDER_SELECT = [
  '*',
  'profiles!orders_customer_id_fkey(full_name, email)',
  'order_items(id, product_id, size, quantity, unit_price, products(name, product_images(image_url, display_order, is_primary)))',
  'order_status_history(id, status, changed_at)',
].join(', ')

/**
 * A row → the shape the seller rules and screens expect.
 *
 * `customer_name` is lifted out of the embedded profile because every screen
 * wants the name and none of them want the embed.
 */
export function mapSellerOrder(row) {
  if (!row) return null

  const customer = row.profiles ?? {}

  return {
    ...row,
    id: String(row.id),
    store_id: row.store_id ? String(row.store_id) : null,
    customer_name: customer.full_name || customer.email || 'Customer',
    customer_email: customer.email ?? null,
    total_amount: Number(row.total_amount) || 0,
    order_items: Array.isArray(row.order_items) ? row.order_items : [],
    order_status_history: Array.isArray(row.order_status_history)
      ? row.order_status_history
      : [],
  }
}

/**
 * The store this seller owns, or null.
 *
 * `maybeSingle` rather than `single`: a freshly approved seller who has not
 * finished Create Store has no row yet, and that is a page state, not an
 * exception.
 */
export async function fetchMyStore(userId) {
  const { data, error } = await supabase
    .from('stores')
    .select('*')
    .eq('owner_id', userId)
    .maybeSingle()

  if (error) throw error
  return data ?? null
}

/**
 * Every order placed against this store, newest first.
 *
 * Filtered on `store_id` explicitly as well as relying on RLS: the policy
 * ("Sellers can view orders for their store") already scopes rows, and the
 * explicit predicate is also what this query is *about*. `store_id` is NOT NULL
 * on the orders the checkout creates, so nothing is lost by requiring it — and
 * it is required, rather than optional, precisely so a seller session can never
 * fall through to reading every order in the marketplace.
 */
export async function fetchSellerOrders(storeId) {
  if (!storeId) return []

  const { data, error } = await supabase
    .from('orders')
    .select(SELLER_ORDER_SELECT)
    .eq('store_id', storeId)
    .order('created_at', { ascending: false })

  if (error) throw error
  return (data ?? []).map(mapSellerOrder).filter(Boolean)
}

/** One order, scoped to the store so a foreign id reads as "not found". */
export async function fetchSellerOrder(orderId, storeId) {
  let query = supabase
    .from('orders')
    .select(SELLER_ORDER_SELECT)
    .eq('id', orderId)

  if (storeId) query = query.eq('store_id', storeId)

  const { data, error } = await query.maybeSingle()
  if (error) throw error
  return mapSellerOrder(data)
}

/**
 * Move an order to a new status, and record that it moved.
 *
 * Two things are deliberate:
 *
 *  1. **The status is written as given.** The app sends a UI label and lets
 *     `_mapUiStatusToDb` translate it (`confirmed` → `preparing`); the caller
 *     here passes the `orders.status` value directly, because
 *     `sellerOrderActions` already returns those. One translation is one fewer
 *     thing to disagree about.
 *  2. **`.select().single()` is not decoration.** RLS refusing an UPDATE does
 *     not raise — PostgREST answers `200` with an empty array, which is exactly
 *     how the app's own `cancelOrder` reports success on a row it never
 *     touched. Asking for the row back turns a silent no-op into an error this
 *     screen can show.
 *
 * The history row is inserted AFTER the update and its failure is swallowed:
 * the status change has already happened, and rolling the caller back into a
 * "failed" state for a missing timeline entry would be a lie about the order.
 * `order_status_history.order_id` is BIGINT, so a UUID order id simply has no
 * history row — the same hole the app has.
 */
export async function updateSellerOrderStatus({ orderId, status }) {
  const { data, error } = await supabase
    .from('orders')
    .update({ status })
    .eq('id', orderId)
    .select()
    .single()

  if (error) throw error

  try {
    await supabase.from('order_status_history').insert({
      order_id: Number(orderId),
      status,
      changed_at: new Date().toISOString(),
    })
  } catch {
    // Deliberately swallowed — see above.
  }

  return mapSellerOrder(data)
}

/**
 * The store's products, with the rows every seller screen needs.
 *
 * `inventory` is joined because that is the table the size selector and the
 * checkout both read, and a seller's "3 left in EU 40" has to be the same 3 the
 * customer sees. `product_variants` is joined because that is the table stock is
 * actually WRITTEN to; the two are shown side by side so the relationship is
 * visible rather than magic. `product_customizations` is joined because the form
 * edits them as part of the product and the write replaces the set — reading them
 * in a second query would be a second chance to show the seller a stale option.
 */
export const SELLER_PRODUCT_SELECT = [
  '*',
  'inventory(size, stock)',
  'product_variants(id, size, color, stock, additional_price, sku)',
  'product_images(id, image_url, display_order, is_primary)',
  'product_color_images(id, color_name, url, display_order)',
  'product_customizations(id, option_name, option_type, options, is_required, additional_price)',
].join(', ')

export function mapSellerProduct(row) {
  if (!row) return null

  const inventory = Array.isArray(row.inventory) ? row.inventory : []
  const variants = Array.isArray(row.product_variants) ? row.product_variants : []
  const images = Array.isArray(row.product_images)
    ? [...row.product_images].sort(
        (a, b) => (a?.display_order ?? 0) - (b?.display_order ?? 0),
      )
    : []

  const totalStock = inventory.reduce(
    (sum, item) => sum + (Number(item?.stock) || 0),
    0,
  )

  return {
    ...row,
    id: String(row.id),
    price: Number(row.price) || 0,
    sale_price:
      row.sale_price === null || row.sale_price === undefined
        ? null
        : Number(row.sale_price),
    inventory: inventory.map((item) => ({
      size: String(item?.size ?? ''),
      stock: Number(item?.stock) || 0,
    })),
    variants: variants.map((variant) => ({
      id: variant?.id ?? null,
      size: String(variant?.size ?? ''),
      color: variant?.color ?? null,
      stock: Number(variant?.stock) || 0,
      additional_price: Number(variant?.additional_price) || 0,
      sku: variant?.sku ?? null,
    })),
    /*
      The options, in the order the table gives them back — `product_customizations`
      has no `display_order` column, so the id sequence is the order a seller
      added them in and the order the shop reads them out in.
    */
    customizations: customizationsFromProduct(row.product_customizations),
    images: images
      .map((image) => image?.image_url)
      .filter((url) => typeof url === 'string' && url.length > 0),
    /*
      The rows, with their ids, alongside the URL list. Both are needed and
      neither can be derived from the other: the gallery renders from `images`,
      and removing one has to DELETE `product_images.id` — a removal by URL
      would silently match zero rows if two products ever point at the same
      object, and the file would be gone while the row stayed.
    */
    imageRows: images.map((image) => ({
      id: image?.id ?? null,
      url: image?.image_url ?? null,
    })),
    /*
      The per-colour galleries, keyed by the colour's NAME — because that is the
      join key the table uses (`product_color_images.color_name`), and it is what
      lets a rename carry a gallery with it rather than orphaning it.

      Every row is kept, including one whose `color_name` is blank: this map is
      written back whole on save (the product's rows are deleted and re-inserted),
      so a row this function dropped would be a photo the next save deletes for no
      reason a seller could see.
    */
    colourImages: colourImagesFromProduct(row.product_color_images),
    totalStock,
  }
}

export async function fetchSellerProducts(storeId) {
  if (!storeId) return []

  const { data, error } = await supabase
    .from('products')
    .select(SELLER_PRODUCT_SELECT)
    .eq('store_id', storeId)
    .order('created_at', { ascending: false })

  if (error) throw error
  return (data ?? []).map(mapSellerProduct).filter(Boolean)
}

export async function fetchSellerProduct(productId) {
  const { data, error } = await supabase
    .from('products')
    .select(SELLER_PRODUCT_SELECT)
    .eq('id', productId)
    .maybeSingle()

  if (error) throw error
  return mapSellerProduct(data)
}

/**
 * Create a product for this store.
 *
 * `seller_id` is written explicitly and is load-bearing: the RLS policies on
 * `inventory`, `product_variants` and `product_images` all resolve ownership
 * through `products.seller_id = auth.uid()`, NOT through the store. The
 * products table's own INSERT policy checks `store_id` ownership, so omitting
 * this would create a product the seller can see and cannot stock.
 *
 * The columns come from `productColumnsFromDraft`, so the create and the update
 * write the same fields in the same shapes — the pair the app's `createProduct`
 * and `updateProduct` also share.
 *
 * `is_active: true` is provisional and honest: it is what the app writes on
 * create too, and it is re-derived from stock the moment the sizes are saved
 * (`saveProductVariants`). A product with no sizes yet is not purchasable either
 * way — `isOutOfStock` is what the storefront reads.
 */
export async function createSellerProduct({ storeId, sellerId, draft }) {
  const { data, error } = await supabase
    .from('products')
    .insert({
      store_id: storeId,
      seller_id: sellerId,
      is_active: true,
      ...productColumnsFromDraft(draft),
    })
    .select()
    .single()

  if (error) throw error
  return data
}

/** A partial update — only the keys given are written. */
export async function updateSellerProduct(productId, patch) {
  const { data, error } = await supabase
    .from('products')
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq('id', productId)
    .select()
    .single()

  if (error) throw error
  return data
}

/**
 * Delete a product.
 *
 * The cascade does the rest: `product_variants`, `inventory`, `product_images`
 * and `product_customizations` all reference `products.id` `ON DELETE CASCADE`.
 */
export async function deleteSellerProduct(productId) {
  const { error } = await supabase.from('products').delete().eq('id', productId)
  if (error) throw error
}

/**
 * Replace a product's variants, and re-derive `inventory` and `is_active`.
 *
 * One row per (size, colour) into `product_variants`, then one row per size into
 * `inventory`, then a derived `is_active`. This is the portal's port of
 * `ProductService._syncInventoryFromVariants`, and the ORDER of the writes is the
 * whole point:
 *
 *   1. delete every `product_variants` row for the product and write the new
 *      set;
 *   2. delete every `inventory` row for the product and write one row per
 *      unique size, summing that size's stock across its colours;
 *   3. re-derive `is_active` from the stock just written.
 *
 * Step 2 deletes even when there is nothing to insert, which is the app's own
 * fix: without it, removing a product's last size leaves the old inventory row
 * behind and the size selector keeps offering a size the seller deleted.
 *
 * The direct write to `inventory` is not a shortcut around a trigger — there is
 * no trigger maintaining this table, and its only other writers are the checkout
 * functions that decrement it. A portal that wrote only `product_variants`
 * would leave the customer's size grid reading stale stock.
 *
 * The whole set is replaced rather than diffed, because the rows have no stable
 * identity a form can hold: a variant is (size, colour), both editable, and
 * "which row was that" has no answer once either changes. Replace-all is what the
 * app does, and it is the only shape in which renaming a colour cannot leave an
 * orphan row behind.
 */
export async function saveProductVariants({ productId, variants }) {
  const rows = variantRowsForInsert(variants).map((row) => ({
    product_id: productId,
    ...row,
  }))

  const { error: clearError } = await supabase
    .from('product_variants')
    .delete()
    .eq('product_id', productId)
  if (clearError) throw clearError

  if (rows.length > 0) {
    const { error: variantError } = await supabase
      .from('product_variants')
      .insert(rows)
    if (variantError) throw variantError
  }

  const { error: inventoryClearError } = await supabase
    .from('inventory')
    .delete()
    .eq('product_id', productId)
  if (inventoryClearError) throw inventoryClearError

  // Summed per size. One row per size, not per colour — that is the shape the
  // checkout decrements and the customer's size grid reads.
  const inventoryRows = inventoryRowsFromVariants(variants).map((row) => ({
    product_id: productId,
    size: row.size,
    stock: row.stock,
    updated_at: new Date().toISOString(),
  }))

  if (inventoryRows.length > 0) {
    const { error: inventoryError } = await supabase
      .from('inventory')
      .insert(inventoryRows)
    if (inventoryError) throw inventoryError
  }

  /*
    Re-derive `is_active`, which is the app's own step and the reason a manual
    toggle for it does not exist on either surface: `syncProductActiveStatus`
    recomputes it as "any stock at all" after EVERY variant write, so a switch a
    seller could flip would be overwritten by the next save anyway. Doing it here
    keeps the column honest whichever client last touched the stock.

    The failure is swallowed, exactly as the app swallows it: the stock has been
    written, and reporting that save as failed for a stale status flag would be
    wrong about the thing the seller asked for. It self-corrects on the next
    write.
  */
  try {
    await supabase
      .from('products')
      .update({ is_active: inventoryRows.some((row) => row.stock > 0) })
      .eq('id', productId)
  } catch {
    // Deliberately swallowed — see above.
  }

  return inventoryRows
}

/**
 * Replace a product's customisation options.
 *
 * Delete-then-insert, the app's own strategy, and for the same reason the
 * variants are replaced: the rows have no `display_order` and no natural key, so
 * the set is the unit. A partial failure leaves the product with fewer options
 * than it had rather than a mix of old and new — which the form's single Save
 * makes a narrow window: the options are written immediately after the row that
 * describes them.
 */
export async function saveProductCustomizations({ productId, customizations }) {
  const rows = customizationRowsForInsert(customizations).map((row) => ({
    product_id: productId,
    ...row,
  }))

  const { error: clearError } = await supabase
    .from('product_customizations')
    .delete()
    .eq('product_id', productId)
  if (clearError) throw clearError

  if (rows.length === 0) return []

  const { error: insertError } = await supabase
    .from('product_customizations')
    .insert(rows)
  if (insertError) throw insertError

  return rows
}

/**
 * Save the seller's own storefront.
 *
 * Only the columns the portal edits are written. `owner_id`, `id` and `rating`
 * are never sent: the first two are the identity the row is found by, and
 * `rating` is computed from reviews — a form that round-trips the whole row
 * would push a stale rating back over a review that landed mid-edit.
 */
export async function updateSellerStore(storeId, patch) {
  const payload = {}
  for (const key of [
    'name',
    'tagline',
    'description',
    'location',
    'brand_color',
    'is_open',
  ]) {
    if (key in patch) payload[key] = patch[key]
  }

  const { data, error } = await supabase
    .from('stores')
    .update(payload)
    .eq('id', storeId)
    .select()
    .single()

  if (error) throw error
  return data
}

/**
 * Upload a store logo or banner, and point the store at it.
 *
 * The path is the app's own (`store_service.dart#uploadStoreAsset`):
 * `{sellerId}/{storeId}-{type}-{timestamp}.{ext}` in the PUBLIC `store-assets`
 * bucket. It is reproduced rather than improved on because the storage
 * policies are keyed to the leading `{sellerId}/`, and a portal-invented layout
 * would be a second convention to keep in sync with the first.
 */
export async function uploadStoreAsset({ storeId, sellerId, file, type }) {
  const ext = extensionOf(file.name)
  const path = `${sellerId}/${storeId}-${type}-${Date.now()}.${ext}`

  const { error: uploadError } = await supabase.storage
    .from('store-assets')
    .upload(path, file, { upsert: true, contentType: file.type })
  if (uploadError) throw uploadError

  const url = supabase.storage.from('store-assets').getPublicUrl(path).data
    .publicUrl

  const column = type === 'logo' ? 'logo_url' : 'banner_url'
  const { data, error } = await supabase
    .from('stores')
    .update({ [column]: url })
    .eq('id', storeId)
    .select()
    .single()
  if (error) throw error

  return { url, store: data }
}

/**
 * Attach images to a product.
 *
 * Path mirrored from `product_service.dart#uploadProductImages`:
 * `{sellerId}/{productId}/{timestamp}_{index}.{ext}` in `product-images`. The
 * rows are appended rather than replacing the set, so uploading a second photo
 * does not delete the first.
 */
export async function uploadProductImages({
  productId,
  sellerId,
  files,
  startOrder = 0,
}) {
  const urls = []

  for (let index = 0; index < files.length; index += 1) {
    const file = files[index]
    const ext = extensionOf(file.name)
    const path = `${sellerId}/${productId}/${Date.now()}_${index}.${ext}`

    const { error: uploadError } = await supabase.storage
      .from('product-images')
      .upload(path, file, { upsert: true, contentType: file.type })
    if (uploadError) throw uploadError

    const url = supabase.storage.from('product-images').getPublicUrl(path).data
      .publicUrl
    urls.push(url)
  }

  if (urls.length === 0) return []

  const { error } = await supabase.from('product_images').insert(
    urls.map((url, index) => ({
      product_id: productId,
      image_url: url,
      display_order: startOrder + index,
      is_primary: startOrder === 0 && index === 0,
    })),
  )
  if (error) throw error

  return urls
}

/**
 * Remove a stored image and its row, so the two cannot drift apart.
 *
 * The ROW is deleted first. The other order looks tidier and is worse: if the
 * row delete then fails, the file is gone and the storefront is serving a
 * broken image with no way to notice it. Failing after the row is gone leaves an
 * orphaned object in the bucket, which costs a few kilobytes and breaks nothing.
 *
 * The object path is only removed when the URL genuinely belongs to this
 * bucket — a seeded product whose photo is an external URL has no object here,
 * and guessing a path is how the wrong file gets deleted.
 */
export async function removeProductImage({ imageId, url }) {
  const { error } = await supabase
    .from('product_images')
    .delete()
    .eq('id', imageId)
  if (error) throw error

  const path = storagePathFromUrl(url, 'product-images')
  if (path) {
    await supabase.storage.from('product-images').remove([path])
  }
}

/**
 * `product_color_images` rows → the form's per-colour map.
 *
 * Grouped rather than left flat, because every read of it is per colour: a card's
 * cover, the sheet's strip, a rename, a removal. Ordered here as well, so the map
 * is already in the shape `colourImagesFor` would have produced.
 */
function colourImagesFromProduct(rows) {
  const map = {}
  for (const row of Array.isArray(rows) ? rows : []) {
    const url = row?.url
    if (typeof url !== 'string' || url.length === 0) continue
    const name = String(row?.color_name ?? '')
    map[name] = [
      ...(map[name] ?? []),
      {
        id: row?.id ?? null,
        url,
        displayOrder: Number(row?.display_order) || 0,
        file: null,
      },
    ]
  }
  return map
}

/**
 * Upload one photo for one colour.
 *
 * The path is the app's own (`{sellerId}/{productId}/colors/{slug}/{timestamp}_{i}.{ext}`,
 * see `colourImagePath`) so the two clients fill one bucket the same way rather
 * than filing the same photo in two places.
 */
export async function uploadColourImage({
  sellerId,
  productId,
  colourName,
  file,
  index = 0,
}) {
  const path = colourImagePath({
    sellerId,
    productId,
    colourName,
    index,
    ext: extensionOf(file?.name),
  })

  const { error } = await supabase.storage
    .from('product-images')
    .upload(path, file, { upsert: true, contentType: file?.type })
  if (error) throw error

  const url = supabase.storage.from('product-images').getPublicUrl(path).data
    ?.publicUrl
  if (!url) {
    throw new Error(`Uploading the photo for ${colourName} returned no URL.`)
  }
  return url
}

/**
 * Replace a product's per-colour galleries with what the form holds.
 *
 * **The app's write, in one order that is deliberately not the app's.** It deletes
 * every `product_color_images` row for the product and re-inserts the set
 * (`_syncColorImages` plus the caller's delete), which is what makes a removal, a
 * rename and a reorder all one operation. What is different here is *when* the new
 * files are uploaded: the app deletes first, so a failed upload leaves the product
 * with no colour photos at all, while uploading first leaves the stored set exactly
 * as it was. Same reasoning as the avatar upload, which writes the file before the
 * column so a failure cannot leave the account pointing at a photo that never
 * arrived.
 *
 * Pending files are uploaded in the order the seller sees them, and
 * `display_order` is renumbered `0..n-1` per colour on the way — the order *is* the
 * meaning (index 0 is the cover), and an order with gaps has two ways to be wrong
 * in.
 */
export async function saveProductColourImages({ productId, sellerId, colourImages }) {
  const rows = []

  for (const name of Object.keys(colourImages ?? {})) {
    for (const [index, image] of colourImagesFor(colourImages, name).entries()) {
      if (image?.file) {
        const url = await uploadColourImage({
          sellerId,
          productId,
          colourName: name,
          file: image.file,
          index,
        })
        rows.push({ product_id: productId, color_name: name, url, display_order: index })
      } else if (image?.url) {
        rows.push({
          product_id: productId,
          color_name: name,
          url: image.url,
          display_order: index,
        })
      }
    }
  }

  const { error: deleteError } = await supabase
    .from('product_color_images')
    .delete()
    .eq('product_id', productId)
  if (deleteError) throw deleteError

  if (rows.length > 0) {
    const { error } = await supabase.from('product_color_images').insert(rows)
    if (error) throw error
  }

  return rows
}

/**
 * Remove one stored colour photo, and its object.
 *
 * The app's `removeColorImage` plus its `_removeStorageFile`: the X on an existing
 * photo takes it out of the database **and** out of the bucket, because an
 * orphaned object is paid for forever and nothing will ever come back for it. The
 * row goes first — see `removeProductImage` for why that order.
 */
export async function removeColourImage({ imageId, url }) {
  const { error } = await supabase
    .from('product_color_images')
    .delete()
    .eq('id', imageId)
  if (error) throw error

  const path = storagePathFromUrl(url, 'product-images')
  if (path) {
    await supabase.storage.from('product-images').remove([path])
  }
}

/**
 * The object path behind a public storage URL.
 *
 * Returns null when the URL does not belong to that bucket, which is the case
 * that matters: a seeded product whose image is an external URL has no object to
 * remove, and calling `remove()` with a guessed path is how the wrong file gets
 * deleted.
 */
export function storagePathFromUrl(url, bucket) {
  if (typeof url !== 'string' || !url) return null
  try {
    const segments = new URL(url).pathname.split('/').filter(Boolean)
    const at = segments.indexOf(bucket)
    if (at < 0 || at + 1 >= segments.length) return null
    return segments.slice(at + 1).join('/')
  } catch {
    return null
  }
}

function extensionOf(name) {
  const ext = String(name ?? '').split('.').pop()?.toLowerCase() ?? ''
  return ext && ext.length <= 5 ? ext : 'jpg'
}

