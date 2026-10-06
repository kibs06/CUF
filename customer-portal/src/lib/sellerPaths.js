/**
 * The seller portal's own routes for a product.
 *
 * In `lib/` rather than beside the components that use it, because the same path
 * is built in two places that must agree: the product row's context menu, and
 * the "More from this workshop" grid *inside* the preview — which has to link to
 * another product's preview rather than to the customer's `/product/:id`, or the
 * first tile a seller clicks bounces them out of the preview and back to their
 * dashboard. One function, so the two cannot drift.
 *
 * ## Why the preview is a seller route, and not `/product/:id`
 *
 * Because the shop is closed to sellers. `AppLayout` sends an approved seller
 * back to the portal from every customer route, which is what made the old
 * "View on your storefront" menu item a control that flashed the product page
 * for a moment and then replaced it with the dashboard. A preview link has to be
 * able to reach the thing it previews, and by construction a seller's session
 * cannot reach the shop — so the preview lives under `/seller`, inside the
 * portal's own guard, and the page it draws is read-only. See `ProductDetail`'s
 * `preview` prop: the purchase controls are disabled there, which is what keeps
 * this an exception in the *routing* rather than a hole in the marketplace rule
 * (a seller still cannot put their own stock in a cart).
 */
export function sellerProductPreviewPath(product) {
  return `/seller/products/${product?.id}/preview`
}
