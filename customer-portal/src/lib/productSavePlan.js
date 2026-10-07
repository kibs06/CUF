/**
 * What one press of Save does: which row it writes, and which photos it sends.
 *
 * ## Why this is a module rather than three lines in the form
 *
 * Because the two decisions here are the two a reader of the form cannot check, and
 * both were got wrong once while the form was being written:
 *
 *  1. **A save with a row updates it; only a save without one creates one.** The
 *     route says `/seller/products/new` or a product id, and there is a *third*
 *     case — a create that failed after its row landed, whose id the form kept
 *     (`createdId`). That case has to **update**: pressing Save again finishes that
 *     product rather than making a second one. The obvious shape of this rule
 *     ("create while the route is new") is exactly the bug, and the bug is invisible
 *     until a seller has two copies of the same pair in their list.
 *  2. **A retry sends only the photos that have not landed.** Files are dropped from
 *     the draft as they are stored, so the batch below is what is genuinely still
 *     pending — and it is sent *behind* whatever already landed, which is what keeps
 *     the cover honest (see below).
 *
 * ## The numbers
 *
 * `photoStartOrder` is where this batch's `display_order` begins. The lowest order
 * is the cover: `uploadProductImages` writes `is_primary` only for `startOrder === 0`
 * and index 0, and the storefront draws the lowest `display_order` first. Counting
 * from what has already landed is therefore not bookkeeping — it is the rule that
 * stops a second batch from colliding with the first, or from taking the cover away
 * from a photo that was already there. `photoCount` is the product's total once this
 * save lands, which is what the confirmation card is told.
 */

/**
 * @param {object}   input
 * @param {string?}  [input.productId]    the id on the route, or null on `/new`
 * @param {string?}  [input.createdId]    the id a failed save created, kept by the form
 * @param {File[]}   [input.photos]       the files still waiting to be uploaded
 * @param {number}   [input.photosStored] how many photos earlier saves already stored
 */
export function productSavePlan({
  productId = null,
  createdId = null,
  photos = [],
  photosStored = 0,
} = {}) {
  const id = productId ?? createdId ?? null
  const batch = [...(photos ?? [])]
  const stored = Math.max(0, Number(photosStored) || 0)

  return {
    /** The row this save is about — null only when there genuinely is none yet. */
    id,
    /** `'create'` inserts a row; `'update'` writes the one that exists. */
    row: id === null ? 'create' : 'update',
    /** The files to upload, in the order the seller picked them. */
    photos: batch,
    /** Where this batch's `display_order` starts. */
    photoStartOrder: stored,
    /** The product's photo count once this save lands — the card's number. */
    photoCount: stored + batch.length,
  }
}
