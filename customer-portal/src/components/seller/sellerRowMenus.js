/**
 * What a right-click offers on a seller row.
 *
 * ## Why the items are built in one module
 *
 * An order is drawn on three surfaces in this portal — the dashboard's queue, the
 * dashboard's recent list, and the orders page — and a product on four. The
 * right-click menu has to say the same thing about each of them, or the same
 * order behaves differently depending on which list it was noticed in, which is
 * the sort of difference nobody reports and everybody distrusts. So the *items*
 * live here and the surfaces only supply the row they were opened on.
 *
 * The rules behind the contents:
 *
 *   - **Nothing here is new work.** Every item is something the surface (or the
 *     page one click away) already does, named where the row is. A menu is a
 *     shortcut, and a shortcut to something that does not exist is a bug with a
 *     nicer font.
 *   - **Copying is offered because a row's own fields are text a seller has to
 *     retype elsewhere** — an order reference into a chat with the customer, a
 *     SKU into a restock list. That is exactly what a pointer's menu is good at.
 *   - **No destructive items.** Cancelling runs through `ConfirmDialog` on the
 *     order page, and a product cannot be deleted from this build at all.
 *   - **`Copy link` and `Open in a new tab` are not listed here** — the menu adds
 *     them for every row that passes a `link`, so a surface cannot forget the two
 *     things it took away from the browser.
 *
 * The icons are component *references*, not elements, so this file stays a plain
 * module of data and every surface gets the same glyph for the same action.
 */
import { Copy, Eye, Package, Pencil, Store } from 'lucide-react'

import { shortOrderRef } from '../../lib/orderRules.js'

/** The seller's own page for an order — what the row itself links to. */
export function orderRowPath(order) {
  return `/seller/orders/${order.id}`
}

/** The seller's editor for a product. */
export function productRowPath(product) {
  return `/seller/products/${product.id}`
}

/**
 * The customer's page for the same product, on the storefront.
 *
 * The storefront is the same SPA, so this is a route rather than a URL to
 * assemble — and because it is a *different* application to the seller (no
 * header, no edit controls, a cart), the item that uses it opens a tab instead of
 * navigating, leaving the seller's page where they left it.
 */
export function storefrontProductPath(product) {
  return `/product/${product.id}`
}

/** What an order row offers — the same three on every list that draws orders. */
export function orderRowMenuItems(order) {
  return [
    { id: 'open', label: 'Open order', Icon: Eye, to: orderRowPath(order) },
    {
      id: 'copy-ref',
      label: 'Copy order reference',
      Icon: Copy,
      copy: shortOrderRef(order?.id),
    },
    ...(order?.customer_name
      ? [
          {
            id: 'copy-customer',
            label: 'Copy customer name',
            Icon: Copy,
            copy: order.customer_name,
          },
        ]
      : []),
  ]
}

/** What a product row offers, in both views of the catalogue. */
export function productRowMenuItems(product) {
  return [
    { id: 'open', label: 'Edit this product', Icon: Pencil, to: productRowPath(product) },
    {
      id: 'storefront',
      label: 'View on your storefront',
      Icon: Store,
      to: storefrontProductPath(product),
      newTab: true,
    },
    { id: 'copy-name', label: 'Copy product name', Icon: Copy, copy: product?.name ?? '' },
    ...(product?.sku
      ? [{ id: 'copy-sku', label: 'Copy SKU', Icon: Copy, copy: product.sku }]
      : []),
  ]
}

/**
 * What a "running out" row offers — the dashboard's own short list, which carries
 * a name, a size and a product id rather than a whole product row.
 */
export function lowStockRowMenuItems(row) {
  return [
    {
      id: 'open',
      label: 'Open product',
      Icon: Package,
      to: `/seller/products/${row.productId}`,
    },
    { id: 'copy-name', label: 'Copy product name', Icon: Copy, copy: row?.name ?? '' },
  ]
}
