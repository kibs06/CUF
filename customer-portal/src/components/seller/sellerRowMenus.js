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
 *   - **One item leaves for the app.** *Request a 3D model* is the same shape as
 *     the shell's *Store creation* pointer: the thing the seller wants does not
 *     happen in this portal, so the menu names the wish and hands them to the
 *     app that grants it (`modelRequestAppPrompt`). Which is also why it is an
 *     `onSelect` and not a link — the answer is a sentence before it is a
 *     download, and a bare releases page explains none of it.
 *   - **`Copy link` and `Open in a new tab` are not listed here** — the menu adds
 *     them for every row that passes a `link`, so a surface cannot forget the two
 *     things it took away from the browser.
 *
 * The icons are component *references*, not elements, so this file stays a plain
 * module of data and every surface gets the same glyph for the same action.
 */
import { Copy, Cuboid, Eye, Package, Pencil, Store } from 'lucide-react'

import { shortOrderRef } from '../../lib/orderRules.js'
import { sellerProductPreviewPath } from '../../lib/sellerPaths.js'

/** The seller's own page for an order — what the row itself links to. */
export function orderRowPath(order) {
  return `/seller/orders/${order.id}`
}

/** The seller's editor for a product. */
export function productRowPath(product) {
  return `/seller/products/${product.id}`
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
export function productRowMenuItems(product, { onRequestModel } = {}) {
  return [
    { id: 'open', label: 'Edit this product', Icon: Pencil, to: productRowPath(product) },
    /*
      The portal's own read-only copy of the product's storefront page, NOT the
      customer's `/product/:id`. That route is closed to sellers — `AppLayout`
      redirects an approved seller back to the portal — so this item used to
      flash the product for a moment and then replace it with the dashboard. See
      `sellerProductPreviewPath` for the path and `ProductDetail`'s `preview`
      prop for what the page does differently.

      Offered only for a product the shop is actually showing. The preview reads
      through the catalog's own `is_published` filter, so on a hidden row it
      could only ever answer "no longer available" — and there is nothing lost,
      because a product customers cannot see has no storefront view to check.

      It still opens a tab rather than navigating: the preview is a different
      application to this list — no edit controls, its own gallery — and a seller
      comparing the two wants both on screen.
    */
    ...(product?.is_published
      ? [
          {
            id: 'storefront',
            label: 'View on your storefront',
            Icon: Store,
            to: sellerProductPreviewPath(product),
            newTab: true,
          },
        ]
      : []),
    /*
      The model a *View in 3D* needs is the CUFMAI team's to build, and the
      request for it is filed in the app — the seller measures the pair with a
      tape there, and the app is where the request's status lives. See
      `modelRequestAppPrompt` for why this is a pointer and not a form.

      It is offered on every product, published or not, because the model is a
      thing a seller wants *before* the pair is on sale as often as after it.

      The handler is supplied by the surface rather than built here for the same
      reason `ContextMenu` takes state from its call site: opening a dialog is a
      render, and this file is data. It is omitted when a surface passes nothing,
      which is the one case where the row genuinely has no prompt to open — and
      `useProductRowMenu` is what passes it in both views.
    */
    ...(typeof onRequestModel === 'function'
      ? [
          {
            id: 'request-model',
            label: 'Request a 3D model',
            Icon: Cuboid,
            onSelect: onRequestModel,
          },
        ]
      : []),
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
