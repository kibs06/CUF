/**
 * The product gallery's own photos, as a list the seller orders.
 *
 * ## Why order is not decoration here
 *
 * The lowest `display_order` is the photo a customer sees first — the storefront
 * sorts `product_images` by it and draws the first one, and the app sorts the same
 * way (`add_edit_product_screen.dart` hydrates its `_imageItems` in
 * `display_order`). So the order a seller arranges here is the order the shop
 * shows, and `is_primary` is kept in step with position 0 rather than left to mean
 * something else.
 *
 * ## The two rules, and why they are functions
 *
 *  * `dropIndexForPoint` is the drag itself: which tile a photo lands on, given the
 *    tiles' rectangles and where the pointer is. It is pure because the arithmetic
 *    is the part of a drag that cannot be checked by looking at the screen — a
 *    three-column grid is where an off-by-one shows up, and every one of those
 *    cases is a test rather than a mouse.
 *  * `moveImage` is the list edit, which is a *move* and not a swap: dragging the
 *    sixth photo into the first slot has to push the other five along, not trade
 *    places with one of them.
 */

/** The middle of a rect — the point a drop is measured against. */
function centreOf(rect) {
  return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 }
}

/** Is the point inside this rect? */
function contains(rect, point) {
  return (
    point.x >= rect.left &&
    point.x <= rect.left + rect.width &&
    point.y >= rect.top &&
    point.y <= rect.top + rect.height
  )
}

/**
 * The index a dragged photo lands at.
 *
 * **Inside a tile wins outright**, because the pointer being over a photograph is
 * the least ambiguous statement a seller can make; otherwise the nearest tile
 * centre takes it, which is what makes a drop between two tiles still land
 * somewhere sensible instead of doing nothing.
 *
 * The list of rects includes the tile being dragged — deliberately. Hovering back
 * over your own slot then resolves to your own index, so putting a photo down
 * where it already was is a no-op rather than a one-place shuffle, and the caller
 * does not have to special-case it.
 *
 * Returns `null` when nothing could be measured (a detached or zero-sized grid),
 * which the caller treats as "no move" rather than as index 0.
 *
 * @param {Array<{left:number,top:number,width:number,height:number}|null>} rects
 * @param {{x:number,y:number}} point
 */
export function dropIndexForPoint(rects, point) {
  let best = null

  ;(rects ?? []).forEach((rect, index) => {
    if (!rect || !point) return
    const inside = contains(rect, point)
    const centre = centreOf(rect)
    const distance =
      (point.x - centre.x) * (point.x - centre.x) +
      (point.y - centre.y) * (point.y - centre.y)

    if (
      best === null ||
      (inside && !best.inside) ||
      inside === best.inside && distance < best.distance
    ) {
      best = { index, inside, distance }
    }
  })

  return best ? best.index : null
}

/**
 * The list with the item at `from` moved to `to`, as a new array.
 *
 * Out-of-range moves resolve to the nearest real position rather than throwing or
 * producing a hole: the indices come from a pointer, and the only thing worse than
 * a photo that lands next to where it was dropped is one that disappears.
 */
export function moveImage(list, from, to) {
  const items = [...(list ?? [])]
  if (from < 0 || from >= items.length) return items

  const target = Math.min(Math.max(Number.isFinite(to) ? to : from, 0), items.length - 1)
  const [moved] = items.splice(from, 1)
  items.splice(target, 0, moved)
  return items
}

/**
 * The `product_images` rows this order means: `display_order` renumbered from
 * zero, and `is_primary` on the first one.
 *
 * Rows without an id are dropped rather than written, and that is the one place
 * this could do damage: `upsert` conflicts on the primary key, so a row that
 * arrives without one would be *inserted* — a second row for the same photo, at
 * the same URL. Every row here came out of the table and has an id; the filter is
 * what keeps a defensive caller from duplicating a gallery.
 *
 * @param {object} input
 * @param {string} input.productId
 * @param {Array<{id:string,url:string}>} input.images in the order the seller arranged
 */
export function imageOrderRows({ productId, images = [] }) {
  return images
    .map((image, index) => ({
      id: image?.id ?? null,
      product_id: productId,
      image_url: image?.url ?? null,
      display_order: index,
      is_primary: index === 0,
    }))
    // `!= null` rather than a truthy test: the column is an identity BIGINT, and a
    // filter that treated `0` as "no id" would quietly drop a real row.
    .filter((row) => row.id != null && row.image_url)
}
