/**
 * The seller's product draft — what the form edits, what the `products` row
 * gets, and every reason a save would be refused.
 *
 * ## Why the draft is not the row
 *
 * Three columns are stored in a shape a form cannot use directly:
 *
 *  - `tags` is a `TEXT[]` of preset ids and encoded custom entries; the form
 *    holds parsed entries so a chip can be drawn (`productTags.js`);
 *  - `sale_starts_at` / `sale_ends_at` are timestamps; the form holds the
 *    `YYYY-MM-DD` a date input speaks (`pricing.js`);
 *  - `audience` is a closed vocabulary where anything else must become SQL NULL
 *    rather than a 400 from the column's CHECK constraint.
 *
 * Hydrating and saving through one pair of functions is what keeps the form from
 * inventing a second interpretation of any of them.
 *
 * ## One list of problems, two severities
 *
 * `productProblems` is the only place the form asks "can this be saved, and is
 * anything about it a bad idea". Every rule it reports comes from the module that
 * owns that field — the sale rules from `pricing.js`, the tags from
 * `productTags.js`, the variants from `productVariants.js` — so there is exactly
 * one implementation of each and the form itself decides nothing.
 *
 * The split is deliberate:
 *
 *  - An **error** blocks the save. Errors are the app's own refusals (a name, a
 *    price, a sale price that is not a discount, an option with no type) plus the
 *    two shapes the schema cannot hold (a barcode over the column's habit, a
 *    colour column with no name).
 *  - A **note** does not. A note is a product that saves exactly as drawn but is
 *    probably not what the seller meant — a sale window that can never open, a
 *    Kids' audience with adult sizes, a colour with no sizes, everything at zero.
 *    Refusing those would mean this form rejects products the app accepts, which
 *    is how a seller ends up unable to fix a typo in a name.
 */

import { PRODUCT_CATEGORIES } from './constants.js'
import { saleDateInput, saleDateValue, salePriceProblem, saleWindowNote } from './pricing.js'
import { audienceSizeMismatch, productAudienceFrom } from './productAudience.js'
import { colourPhotoNotes } from './productColourImages.js'
import { customizationProblems } from './productCustomizations.js'
import { parseTags, serializeTags } from './productTags.js'
import { variantProblems } from './productVariants.js'

/**
 * The app's own limit on a barcode (`'Barcode must be under 50 characters'`).
 *
 * The column is plain TEXT with no length, so this is a form rule rather than a
 * schema one — kept because a scanner reads what fits a symbology, and a value
 * long enough to be a paragraph is a paste error rather than a barcode.
 */
export const MAX_BARCODE_LENGTH = 50

/** A blank string (or nothing) is NULL in the column. */
export function blankToNull(value) {
  const text = String(value ?? '').trim()
  return text.length > 0 ? text : null
}

/** A price as the column holds it: a number, never NaN, never negative. */
function priceOrZero(value) {
  const number = Number(value)
  if (!Number.isFinite(number)) return 0
  return Math.max(0, number)
}

/**
 * A sale price, or null for "no sale".
 *
 * Zero and blank both become NULL rather than being written as `0`: a `0` in the
 * column is a number no reader should ever treat as a price, and `isOnSale`
 * already ignores it, so the only difference between the two is that one of them
 * is a lie waiting for the next reader. The app stores the `0`; both clients show
 * the same thing either way, and this side keeps the row honest.
 */
function salePriceOrNull(value) {
  const number = Number(value)
  if (!Number.isFinite(number) || number <= 0) return null
  return number
}

/**
 * A new product's draft.
 *
 * `is_published` starts true and `is_featured` false, which is what the columns
 * default to — a seller creating a product is putting it in the shop, and the
 * form's own submit is what makes that true rather than a second step.
 */
export function emptyProductDraft(overrides = {}) {
  return {
    name: '',
    price: '',
    category: PRODUCT_CATEGORIES[0],
    description: '',
    sku: '',
    collection: '',
    barcode: '',
    tags: [],
    audience: null,
    is_published: true,
    is_featured: false,
    sale_price: '',
    sale_starts_at: '',
    sale_ends_at: '',
    ...overrides,
  }
}

/**
 * A stored product → the draft.
 *
 * `tags` are parsed and the sale dates are reduced to their date part, so what
 * the form shows is what it will write back: open a product whose window is
 * `2026-09-26T00:00:00+00:00`, change nothing, and save writes
 * `2026-09-26T00:00:00` — the same instant, not a day either side of it.
 */
export function productDraftFrom(product) {
  return emptyProductDraft({
    name: product?.name ?? '',
    price: product?.price === null || product?.price === undefined ? '' : String(product.price),
    category: product?.category || PRODUCT_CATEGORIES[0],
    description: product?.description ?? '',
    sku: product?.sku ?? '',
    collection: product?.collection ?? '',
    barcode: product?.barcode ?? '',
    tags: parseTags(product?.tags),
    audience: productAudienceFrom(product?.audience),
    is_published: product?.is_published !== false,
    is_featured: product?.is_featured === true,
    sale_price:
      product?.sale_price === null || product?.sale_price === undefined
        ? ''
        : String(product.sale_price),
    sale_starts_at: saleDateInput(product?.sale_starts_at),
    sale_ends_at: saleDateInput(product?.sale_ends_at),
  })
}

/**
 * The draft → the `products` columns the form owns.
 *
 * Identity (`store_id`, `seller_id`, `id`) and the derived `is_active` are
 * deliberately absent: the caller adds the first two when it creates a row, and
 * `saveProductVariants` owns the third because stock is what derives it.
 */
export function productColumnsFromDraft(draft) {
  return {
    name: String(draft?.name ?? '').trim(),
    description: blankToNull(draft?.description),
    price: priceOrZero(draft?.price),
    category: blankToNull(draft?.category) ?? PRODUCT_CATEGORIES[0],
    collection: blankToNull(draft?.collection),
    sku: blankToNull(draft?.sku),
    barcode: blankToNull(draft?.barcode),
    tags: serializeTags(draft?.tags ?? []),
    is_published: draft?.is_published !== false,
    is_featured: draft?.is_featured === true,
    // Normalised, so an unrecognised value clears the column instead of tripping
    // its CHECK constraint as a 400 the form would flatten into "something went
    // wrong".
    audience: productAudienceFrom(draft?.audience),
    // Always sent, so a sale can be started and stopped by editing the fields —
    // and so clearing a date really clears it.
    sale_price: salePriceOrNull(draft?.sale_price),
    sale_starts_at: saleDateValue(draft?.sale_starts_at),
    sale_ends_at: saleDateValue(draft?.sale_ends_at),
  }
}

/** `Sole colour: Choose a kind of option.` — which option the message is about. */
function labelProblems(label, { errors, notes }) {
  return {
    errors: errors.map((message) => `${label}: ${message}`),
    notes: notes.map((message) => `${label}: ${message}`),
  }
}

/**
 * Everything wrong with a draft, and everything worth saying about it.
 *
 * @param {object} input
 * @param {object} input.draft            the `products` fields
 * @param {Array}  [input.variants]       the flat (size, colour) rows
 * @param {Array}  [input.colours]        the colour columns, in order
 * @param {Array}  [input.customizations] the option rows
 * @param {object} [input.colourImages]   each colour's photos, keyed by name
 */
export function productProblems({
  draft,
  variants = [],
  colours = [],
  customizations = [],
  colourImages = {},
}) {
  const errors = []
  const notes = []

  const name = String(draft?.name ?? '').trim()
  if (!name) errors.push('Give the product a name.')

  const rawPrice = draft?.price
  if (rawPrice === '' || rawPrice === null || rawPrice === undefined) {
    errors.push('Enter a price.')
  } else {
    const price = Number(rawPrice)
    if (!Number.isFinite(price) || price < 0) {
      errors.push('Enter a price of 0 or more.')
    }
  }

  const saleProblem = salePriceProblem({
    price: draft?.price,
    salePrice: draft?.sale_price,
  })
  if (saleProblem) errors.push(saleProblem)

  const barcode = String(draft?.barcode ?? '').trim()
  if (barcode.length > MAX_BARCODE_LENGTH) {
    errors.push(`Barcode must be under ${MAX_BARCODE_LENGTH} characters.`)
  }

  const variant = variantProblems({ variants, colours })
  errors.push(...variant.errors)
  notes.push(...variant.notes)

  customizations.forEach((customization, index) => {
    const label =
      String(customization?.option_name ?? '').trim() || `Option ${index + 1}`
    const problems = labelProblems(label, customizationProblems(customization))
    errors.push(...problems.errors)
    notes.push(...problems.notes)
  })

  /*
    A colour with no photos is a NOTE. Every coloured product in the catalog
    predates `product_color_images`, and the migration's own words are that they
    are left as-is and the seller is prompted on their next edit — so this asks,
    it never refuses. The colour SHEET is where a photo is required, because that
    is a colour being created rather than a product being saved.
  */
  notes.push(...colourPhotoNotes({ colours, colourImages }))

  const windowNote = saleWindowNote({
    saleStartsAt: draft?.sale_starts_at,
    saleEndsAt: draft?.sale_ends_at,
  })
  if (windowNote) notes.push(windowNote)

  if (
    audienceSizeMismatch({
      audience: draft?.audience,
      sizes: variants.map((row) => row?.size),
    })
  ) {
    notes.push('These sizes look like adult sizing — check the audience is right.')
  }

  // `is_active` is derived from stock — the app re-derives it after every
  // variant write — so a product with nothing in stock is about to be marked
  // unavailable. Saying so is the difference between a consequence and a
  // surprise.
  const hasRows = variants.some((row) => String(row?.size ?? '').trim())
  const hasStock = variants.some((row) => Number(row?.stock) > 0)
  if (hasRows && !hasStock) {
    notes.push(
      'Every size is at zero, so this product will be marked unavailable until something is restocked.',
    )
  }

  return { errors, notes }
}
