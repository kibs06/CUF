/**
 * Product audience — who a product is for, and the one place that decides what
 * an audience value *means*. A port of `lib/utils/product_audience.dart`.
 *
 * ## Why the value is stated rather than derived
 *
 * The obvious shortcut is to read the audience off the sizes a product stocks.
 * It cannot be done: EU sizing is unisex, so Men's and Women's share one entire
 * band, and the kids' band overlaps the adult one at the top (EU 35 is both a
 * child's size and the bottom of the women's scale). Two of the four values
 * would be guessed wrong. So `products.audience` is a value a seller picks, and
 * an unset one stays unset.
 *
 * ## The vocabulary is the shopper's, plus one
 *
 * Men's / Women's / Kids' are `FOOT_SIZE_CATEGORIES` — the same three scales the
 * size picker and the AR scan write to a profile. Spreading them in rather than
 * re-spelling them is what stops `'women'` from meaning one thing on a profile
 * and another on a product. `unisex` is the one addition, and it exists only
 * here: a shopper always shops on one chart, so their own scale is never unisex.
 *
 * ## Null is an answer, never a default
 *
 * `null` means "the seller has not said", and nothing reads it as "any
 * audience". A product with no audience stays in the catalog and in search; it
 * simply appears in no audience rail. `parse` is an exact match for the same
 * reason the column's CHECK constraint is — inventing a meaning for `'Men'` would
 * be storing a value the database does not hold.
 */
import { EU_KIDS_SIZES, FOOT_SIZE_CATEGORIES } from './footRules.js'
import { sizeNumberInEu } from './sizeKeyRules.js'

/** The children's audience value — the one band whose sizes can be checked. */
export const KIDS_AUDIENCE = 'kids'

/**
 * The one audience that is not a rail.
 *
 * A genuinely unisex product is a real answer, but listing it in Men's, Women's
 * AND Kids' would put the same card three times down the feed, so rail surfaces
 * must skip it.
 */
export const UNISEX_AUDIENCE = 'unisex'

/** Every value `products.audience` may hold, in display order. */
export const PRODUCT_AUDIENCE_OPTIONS = [
  ...FOOT_SIZE_CATEGORIES,
  { value: UNISEX_AUDIENCE, label: 'Unisex' },
]

/** The audiences that get a rail, in fixed order — `unisex` is absent by design. */
export const PRODUCT_RAIL_AUDIENCES = ['men', 'women', KIDS_AUDIENCE]

/**
 * The canonical audience value for a stored string, or null.
 *
 * **Exact match, deliberately.** No trimming and no case folding: the column's
 * CHECK constraint is itself an exact comparison, so anything that is not
 * already canonical is not one of our values. `'Men'` and `'unisex '` are null,
 * not `'men'` and `'unisex'`.
 */
export function productAudienceFrom(raw) {
  for (const option of PRODUCT_AUDIENCE_OPTIONS) {
    if (option.value === raw) return option.value
  }
  return null
}

/**
 * The label to render for a canonical value, or null.
 *
 * Null for null and for anything unrecognised, so a caller that has a label is
 * guaranteed to have a real audience — a chip group never has to decide what to
 * draw for a value it does not know.
 */
export function productAudienceLabel(value) {
  if (value === null || value === undefined) return null
  for (const option of PRODUCT_AUDIENCE_OPTIONS) {
    if (option.value === value) return option.label
  }
  return null
}

/** The kids' band, read from the list the size picker offers. */
const KIDS_BAND_MIN = Number.parseFloat(EU_KIDS_SIZES[0])
const KIDS_BAND_MAX = Number.parseFloat(EU_KIDS_SIZES[EU_KIDS_SIZES.length - 1])

/**
 * Whether a product's sizes contradict the audience a seller picked.
 *
 * Only Kids' can be contradicted: a product marked Kids' whose every stocked
 * size sits outside the children's band is almost certainly a mis-tapped chip,
 * and a soft note is worth showing. `unisex` and null claim no band, so nothing
 * can contradict them.
 *
 * **Warning only, and one-directional.** This never blocks a save, never
 * rewrites the audience and never rewrites a size — a stated value stays visible
 * and fixable rather than being reinterpreted behind the seller's back.
 *
 * False unless *every* size is readable AND every one of them is outside the
 * band: with no sizes yet, or one custom/unreadable size in the list, there is
 * nothing solid enough to contradict, so nothing is claimed. A single size
 * inside the band is enough to confirm the audience is right.
 */
export function audienceSizeMismatch({ audience, sizes }) {
  if (audience !== KIDS_AUDIENCE) return false

  let sawASize = false
  for (const raw of sizes ?? []) {
    const eu = sizeNumberInEu(raw)
    if (eu === null) return false
    if (eu >= KIDS_BAND_MIN && eu <= KIDS_BAND_MAX) return false
    sawASize = true
  }
  return sawASize
}
