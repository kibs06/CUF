/**
 * The app's *Color sheet* — a colour's name, its photos and its sizes, as one
 * edit.
 *
 * ## Why this is its own module
 *
 * Because a colour is not a row in one table. It is a name in `product_variants`
 * (on every row that carries it), the same name in `product_color_images` (on every
 * photo of it), and a member of the product's colour *list*. Three pieces of state,
 * one thing the seller is editing, and the app keeps them together by handing the
 * sheet a `ProductColor` — `name`, `images`, `variants` — and putting that object
 * back into `_colors` on save. This module is that object, and the two merges its
 * two tables need.
 *
 * ## The one place the web is stricter than the phone
 *
 * The phone's sheet collects its rows **before** the save button is enabled, and it
 * stamps each one with the colour name it had when *Add Sizes* was opened
 * (`_showVariantSheetForColor(colorName: colorName, …)`). Rename the colour
 * afterwards and the rows keep the old name, which is a colour the card shows and
 * the database cannot find. Here the sheet holds rows that carry a working name and
 * `applyColourSheet` **re-stamps them with the name they are saved under** — so the
 * name on the card is the name on every row and every photo, whichever order the
 * seller did the two steps in. That is a divergence about a bug rather than about a
 * rule: the sheet the seller sees is the phone's sheet.
 *
 * ## What is required, and where
 *
 * `colourSheetProblems` holds the sheet's own two conditions — a name and at least
 * one photo — because the phone's save button is disabled on exactly those. A
 * colour that **already exists** without photos is a different thing: the
 * migration left those as-is, so they are a note on the product
 * (`colourPhotoNotes`) and never a block. The distinction matters at save: the
 * sheet refuses to *create* a photoless colour, and the product-level save does not.
 */

import {
  colourOf,
  renameColour,
  replaceColourRows,
  sizeOf,
} from './productVariants.js'
import { renameColourImages, removeColourImages } from './productColourImages.js'

/**
 * A colour's rows, in the set's own order.
 *
 * The unit the colour sheet adds sizes to: it opens with these, the size sheet
 * edits them, and applying swaps the whole set for what came back. Also what the
 * `<img>` case in `colourSummaries` counts, named here so both read the same way.
 */
export function rowsForColour(variants, colour) {
  const wanted = colourOf({ color: colour })
  return (variants ?? []).filter((variant) => colourOf(variant) === wanted)
}

/**
 * Whether a colour name is already taken, as the app's sheet says it.
 *
 * Compared case-insensitively, and excluding the colour being edited, which is the
 * one case where a name matches itself. The phone's own message is
 * `'That is already a color — tap it above instead.'`, and it is a *live* check
 * there (the name field is a chip selector with a duplicate error), which is why
 * this is a function the sheet calls while typing rather than a condition on save.
 */
export function colourClash(colours, name, previous = null) {
  const wanted = String(name ?? '').trim().toLowerCase()
  if (!wanted) return null
  const taken = (colours ?? []).some(
    (colour) =>
      colour !== previous && String(colour ?? '').trim().toLowerCase() === wanted,
  )
  return taken ? 'That is already a colour — edit that card instead.' : null
}

/**
 * A colour's row for one size, as the sheet's own list draws it.
 *
 * Not a form field: the list under *Sizes & stock* is a **summary** of what the size
 * sheet wrote, one line per row with a delete button. Here rather than in the
 * component because the count that is drawn is the raw stock rather than one of
 * `stockState`'s three states — a summary line is not a stock warning — and because
 * the extra price is drawn only when there is one.
 */
export function rowSummary(variant) {
  const stock = Math.max(0, Math.trunc(Number(variant?.stock) || 0))
  const extra = Number(variant?.additional_price) || 0
  return {
    size: sizeOf(variant),
    stock,
    extra,
    // `Stock: 3`, the phone's own words (`'Stock: ${v.stock}'`).
    label: `Stock: ${stock}`,
    // Only when there is one — the phone draws `+₱0` nowhere, and a row of them
    // would be nine claims that nothing is added.
    extraLabel: extra > 0 ? `+₱${extra.toFixed(2)}` : null,
  }
}

/**
 * The colour sheet, applied: its name, its photos and its rows, in one merge.
 *
 * `previous` is the name the colour had when the sheet opened (`null` for a new
 * one) and `name` is what the seller typed. Everything the merge does follows from
 * the difference between the two:
 *
 *  1. **A rename moves all three.** `renameColour` rewrites the rows, and
 *     `renameColourImages` moves the gallery, because the name is the key in both
 *     tables — see `renameColourImages`. A name that is taken is refused here
 *     *and* while typing (`colourClash`), since the sheet can also be saved by
 *     pressing Enter.
 *  2. **A new colour joins the list.** Not with `addColour`'s no-rows rule but with
 *     the rows the sheet collected — `replaceColourRows` below writes them.
 *  3. **The rows are this colour's, entire.** `replaceColourRows` drops the colour's
 *     existing rows and writes what the sheet returned, so a size the seller took
 *     out of the colour really is gone. That is the colour sheet's own scope (see
 *     `replaceColourRows`), and it is why the size sheet inside it is scoped to the
 *     same one colour: two nested edits, both of them per colour.
 *
 * The rows are **re-stamped** with `name` on the way in, which is the divergence
 * described at the top: renaming a colour whose sizes were already collected is the
 * case the phone gets wrong, and stamping here is what makes the order of the two
 * steps stop mattering.
 */
export function applyColourSheet({
  variants,
  colours,
  colourImages = {},
  previous = null,
  name,
  images,
  rows,
}) {
  const finalName = String(name ?? '').trim()
  if (!finalName) {
    return { variants, colours, colourImages, error: 'Give the colour a name.' }
  }

  const clash = colourClash(colours, finalName, previous)
  if (clash) return { variants, colours, colourImages, error: clash }

  let nextVariants = variants ?? []
  let nextColours = colours ?? []
  let nextImages = colourImages ?? {}

  if (previous && previous !== finalName) {
    const renamed = renameColour(nextVariants, nextColours, previous, finalName)
    if (renamed.error) return { variants, colours, colourImages, error: renamed.error }
    nextVariants = renamed.variants
    nextColours = renamed.colours
    nextImages = renameColourImages(nextImages, previous, finalName)
  } else if (!previous && !nextColours.includes(finalName)) {
    nextColours = [...nextColours, finalName]
  }

  nextVariants = replaceColourRows(
    nextVariants,
    finalName,
    (rows ?? []).map((row) => ({ ...row, color: finalName })),
  )
  nextImages = { ...nextImages, [finalName]: images ?? [] }

  return {
    variants: nextVariants,
    colours: nextColours,
    colourImages: nextImages,
    error: null,
  }
}

/**
 * A colour, gone: its rows, its photos and its place in the list.
 *
 * All three, in one call, because a delete that dropped the card and left the rows
 * would be a colour the storefront still sells — `variantProblems` would not even
 * notice, since the rows are the only place a colour exists to the database. The app
 * removes the card and lets the save do the rest; the difference is which line the
 * rows disappear on, not whether they do.
 */
export function removeColourEverywhere({ variants, colours, colourImages, name }) {
  const wanted = colourOf({ color: name })
  return {
    variants: (variants ?? []).filter((variant) => colourOf(variant) !== wanted),
    colours: (colours ?? []).filter((colour) => colourOf({ color: colour }) !== wanted),
    colourImages: removeColourImages(colourImages, name),
  }
}

/** Does this colour have any sizes at all? The sheet's "No sizes added yet". */
export function hasRowsFor(variants, colour) {
  return rowsForColour(variants, colour).some((row) => sizeOf(row))
}
