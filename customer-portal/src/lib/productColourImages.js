/**
 * A colour's photos — `product_color_images`, and the rules the app's colour
 * sheet follows.
 *
 * ## The table, and why the colour's NAME is the key
 *
 * `product_color_images(id, product_id, color_name, url, display_order)` holds one
 * row per photo per colour, and the join key is the colour's **name** rather than
 * an id. That is the app's own decision and it is written into the migration: the
 * name on `product_variants.color` stays the single source of truth for what a
 * colour *is*, so grouping stock by size and querying variants flat both keep
 * working. It has one consequence this module lives with: renaming a colour has to
 * rename its photos too, or the gallery is orphaned — see `renameColourImages`.
 *
 * ## What the app requires, and where it requires it
 *
 *  1. **At least one photo per colour, and a name.** The colour sheet's own save
 *     button is disabled until both are true (`colorName.trim().isEmpty ||
 *     colorImages.isEmpty`), so a colour cannot be *created* without one. The
 *     product-level save does **not** enforce it — the migration says as much:
 *     existing coloured products have no photos and are "left as-is — sellers will
 *     be prompted to add photos the next time they edit that product". That is the
 *     split here too: an error in `colourSheetProblems`, a note in
 *     `colourPhotoNotes`.
 *  2. **Six photos per colour.** `maxColorImages = 6`, and the picker takes only
 *     as many as are left (`picked.take(remaining)`), so a seventh is dropped
 *     rather than refused. `MAX_COLOUR_IMAGES` is that number and the picker here
 *     enforces it the same way.
 *  3. **The first photo is the cover.** The sheet marks index 0 "Main", the card
 *     draws the first one that has a URL as its thumbnail, and a customer's colour
 *     swatch uses it. So order is not decorative: it decides what the storefront
 *     shows, and removing the first photo promotes the second.
 *
 * ## Two small liberties, both about the same failure
 *
 *  * **Uploads happen before the delete.** The app deletes the product's existing
 *    rows and *then* uploads (`_syncColorImages` inserts as it goes). Doing it the
 *    other way round here means a failed upload leaves the stored photos exactly
 *    where they were instead of leaving none — the same reasoning as uploading an
 *    avatar before writing its column, and the same reasoning
 *    `removeProductImage` uses to delete the row before the object.
 *  * **`display_order` is renumbered on save** to `0..n-1` in the order the seller
 *    sees. The app keeps whatever `displayOrder` each image was created with, which
 *    leaves gaps after a removal. Gaps are harmless but the *meaning* is "this
 *    order", and an order that is not a sequence is an order with two ways to be
 *    wrong in.
 *
 * ## Pending files
 *
 * An image entry is either **stored** (`{ id, url, displayOrder }`) or **pending**
 * (`{ file, displayOrder }`) — a file the seller picked and nothing has uploaded
 * yet. Only `saveProductColourImages` in `seller.js` turns the second into the
 * first; everything in here treats a pending file as a photo that exists, because
 * to the seller it does.
 */

/** The app's own cap on a colour's gallery (`maxColorImages`). */
export const MAX_COLOUR_IMAGES = 6

/**
 * A colour name as a storage path segment — the app's own rule, character for
 * character: everything outside `[a-zA-Z0-9_-]` becomes `_`.
 *
 * Not cosmetic. `Burnished Clay` has a space in it and the object path is part of
 * a URL; and the app and this portal must build the *same* path for the same
 * colour, or the two clients fill one bucket with two sets of directories and a
 * removal from one side misses the other's file.
 */
export function colourSlug(name) {
  return String(name ?? '').trim().replace(/[^a-zA-Z0-9_-]/g, '_') || 'colour'
}

/**
 * Where a colour's photo lives in the `product-images` bucket.
 *
 * `{sellerId}/{productId}/colors/{slug}/{timestamp}_{index}.{ext}` — the app's
 * `_syncColorImages`, exactly. The first segment is the seller's id because the
 * bucket's own policy checks it, and `colors/` keeps a colour's gallery out of the
 * product gallery's own flat layout.
 */
export function colourImagePath({
  sellerId,
  productId,
  colourName,
  index = 0,
  ext = 'jpg',
  at = Date.now(),
}) {
  return `${sellerId}/${productId}/colors/${colourSlug(colourName)}/${at}_${index}.${ext}`
}

/** A colour's photos, in the order the seller sees them. */
export function colourImagesFor(colourImages, name) {
  const list = Array.isArray(colourImages?.[name]) ? colourImages[name] : []
  return [...list].sort(
    (a, b) => (Number(a?.displayOrder) || 0) - (Number(b?.displayOrder) || 0),
  )
}

/**
 * The photo a colour's card draws: the first one that is **stored**.
 *
 * Stored, not merely first, because a card is read on a list of colours and a
 * pending file has no URL to put in an `<img>` — the sheet, which is where the
 * seller is looking at *their* photos, previews pending files instead.
 */
export function colourThumbnail(colourImages, name) {
  const stored = colourImagesFor(colourImages, name).find((image) => image?.url)
  return stored?.url ?? null
}

/**
 * Every colour's own row count for the card's summary line: `photos · sizes · in
 * stock`, the app's `'$photoCount photo${…} · $sizeCount size${…} · $totalStock in
 * stock'`.
 *
 * The three numbers come from three different places on purpose — the photos from
 * this table, the sizes from `product_variants` (the rows that name the colour),
 * and the stock from those same rows summed. A colour with photos but no sizes is
 * a real state (the sheet saves the two independently) and the line is how a
 * seller sees it.
 */
export function colourSummaries({ colours, variants = [], colourImages = {} }) {
  return (colours ?? []).map((name) => {
    const images = colourImagesFor(colourImages, name)
    const rows = (variants ?? []).filter(
      (variant) => String(variant?.color ?? '').trim() === String(name ?? '').trim(),
    )
    const sizes = new Set(
      rows.map((row) => String(row?.size ?? '').trim()).filter(Boolean),
    )
    return {
      name,
      photos: images.length,
      pending: images.filter((image) => image?.file).length,
      sizes: sizes.size,
      stock: rows.reduce((sum, row) => sum + (Number(row?.stock) || 0), 0),
      label: `${images.length} photo${images.length === 1 ? '' : 's'} · ${
        sizes.size
      } size${sizes.size === 1 ? '' : 's'} · ${
        rows.reduce((sum, row) => sum + (Number(row?.stock) || 0), 0)
      } in stock`,
    }
  })
}

/**
 * What the colour sheet refuses, and what it can only warn about.
 *
 * The errors are the sheet's own two conditions (`_showColorSheet` disables its
 * save on exactly these): a colour with no name, and a colour with no photo. Both
 * are about the **colour being saved**, so they are asked here rather than of the
 * whole draft.
 */
export function colourSheetProblems({ name, images }) {
  const errors = []
  if (!String(name ?? '').trim()) errors.push('Give the colour a name.')
  if ((images ?? []).length === 0) {
    errors.push('Add at least one photo — a customer picks a colour by its photo.')
  }
  if ((images ?? []).length > MAX_COLOUR_IMAGES) {
    errors.push(`A colour can have at most ${MAX_COLOUR_IMAGES} photos.`)
  }
  return { errors }
}

/**
 * The product-level prompt: colours the storefront cannot show a picture for.
 *
 * A **note** and never an error. Every coloured product in the catalog predates
 * per-colour galleries, and the migration's own words are that they are left as-is
 * and "sellers will be prompted to add photos the next time they edit that
 * product". Blocking the save would mean the portal refuses to save a product the
 * app saves, over a photo — which is the one thing this form is not allowed to do.
 */
export function colourPhotoNotes({ colours, colourImages }) {
  const notes = []
  for (const name of colours ?? []) {
    if (colourImagesFor(colourImages, name).length > 0) continue
    notes.push(`${name} has no photos yet — customers see the product’s own photos for it.`)
  }
  return notes
}

/** A colour's photos with another one appended, in the app's display order. */
export function addColourImage(images, entry) {
  const list = [...(images ?? [])]
  return [...list, { ...entry, displayOrder: list.length }]
}

/** A colour's photos without the one at `index`, renumbered. */
export function removeColourImageAt(images, index) {
  return (images ?? [])
    .filter((_, at) => at !== index)
    .map((image, at) => ({ ...image, displayOrder: at }))
}

/**
 * A colour's photos, moved under its new name.
 *
 * What makes the name-as-key schema safe to edit. `product_variants.color` is
 * renamed by `renameColour`, and a gallery keyed by the old name would be a colour
 * with photos that nothing can find and a colour with no photos that the sheet
 * insists on having. Merging rather than replacing: a rename onto a name that
 * already has photos keeps both, in order, because two sets of photos for one
 * colour is a thing a seller can see and undo while a silently discarded one is
 * not.
 */
export function renameColourImages(colourImages, from, to) {
  const next = { ...(colourImages ?? {}) }
  const name = String(to ?? '').trim()
  if (!name || from === to) return next

  // In display order, not storage order: the merged gallery has to keep the
  // order the seller put the photos in, whichever colour they came from.
  const moving = colourImagesFor(colourImages, from)
  if (moving.length > 0) {
    delete next[from]
    next[name] = [...colourImagesFor(colourImages, name), ...moving]
  }

  return Object.fromEntries(
    Object.entries(next).map(([colour, images]) => [
      colour,
      (images ?? []).map((image, at) => ({ ...image, displayOrder: at })),
    ]),
  )
}

/** A colour's photos, dropped with the colour itself. */
export function removeColourImages(colourImages, name) {
  const next = { ...(colourImages ?? {}) }
  delete next[name]
  return next
}
