// ─── The 3D-products shelf ────────────────────────────────────────
//
// One entry per product with a LIVE model — the same file the app renders in
// its preview and the customer portal draws in `Product3DViewer`, so this
// list and those two surfaces can never disagree about what "has 3D" means.
//
// Drafts are excluded on purpose: a draft is not a model customers can render,
// and listing it here would promise a fitting the app cannot open. The queue's
// fulfil picker shows drafts for exactly the opposite reason (to explain why a
// request cannot close), and the two lists must not be confused.

/**
 * Collapse `active` model rows (with their `products` embed) to one entry per
 * product — the newest version wins. Rows without a product (removed) or
 * without a file (nothing to draw) are dropped, never rendered as ghosts.
 */
export function pickModelledProducts(rows) {
  const byProduct = new Map()

  for (const row of rows ?? []) {
    // The product embed is required, not the raw FK: without it there is no
    // name and no photo, and a nameless card is a ghost, not an entry.
    const productId = row?.products?.id ?? null
    if (productId == null || typeof row?.storage_path !== 'string' || row.storage_path === '') {
      continue
    }
    const prev = byProduct.get(productId)
    if (!prev || Number(row.version ?? 0) > Number(prev.model.version ?? 0)) {
      byProduct.set(productId, {
        productId,
        name: row.products?.name ?? 'Product removed',
        images: row.products?.product_images ?? [],
        model: row,
      })
    }
  }

  return [...byProduct.values()]
}
