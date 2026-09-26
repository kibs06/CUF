// Values here mirror `lib/constants/app_constants.dart`. Where the app has a
// canonical list, this is the same list — not a retyped approximation.

export const ROLES = {
  CUSTOMER: 'customer',
  SELLER: 'seller',
  ADMIN: 'admin',
}

/**
 * The association, in one sentence.
 *
 * One string rather than a copy per surface, for the usual reason: the makers
 * page header and the home page's makers banner are the two places a customer
 * meets the association, and two hand-typed copies of a sentence about who its
 * members are is two chances to disagree about it.
 *
 * "Here" is deliberate and reads the same on both — *here* is the marketplace,
 * not the page — so the sentence is reused verbatim rather than rephrased into
 * something with a weaker claim in it.
 */
export const ASSOCIATION_INTRO =
  'Every store here belongs to a CUFMAI member artisan — shoemakers from Poblacion 3, Liburon and Valladolid who have been making footwear in Carcar for generations.'

/**
 * Canonical product categories — `AppConstants.productCategories`, used by the
 * seller product form and the customer category filter so the two can never
 * drift. Products carrying a category outside this list (legacy free text) are
 * still surfaced by unioning in whatever the catalog actually holds.
 */
export const PRODUCT_CATEGORIES = [
  'Casual',
  'Formal',
  'Sports',
  'Sandals',
  'Boots',
  'Sneakers',
  'Slip-ons',
  'Custom',
]

/** Product audience — Men's / Women's / Kids' / Unisex. */
export const PRODUCT_AUDIENCES = ["Men's", "Women's", "Kids'", 'Unisex']

/** Order statuses the customer sees on the timeline (`placed → received`). */
export const ORDER_STATUSES = [
  'placed',
  'preparing',
  'ready',
  'received',
  'cancellation_requested',
  'cancelled',
]

export function formatCurrency(value) {
  const num = Number(value) || 0
  return `₱${num.toLocaleString('en-PH', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`
}

/** Whole pesos — for a large hero figure where cents are noise. */
export function formatCurrencyCompact(value) {
  const num = Number(value) || 0
  return `₱${num.toLocaleString('en-PH', { maximumFractionDigits: 0 })}`
}

export function formatDate(value) {
  if (!value) return '—'
  return new Date(value).toLocaleDateString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

/**
 * Pluralise a count with its noun — "1 store", "3 stores". Used on the store
 * cards and section counts.
 */
export function pluralize(count, singular, plural = `${singular}s`) {
  return `${count} ${count === 1 ? singular : plural}`
}

/** The initials on a store's fallback avatar when it has no logo. */
export function getInitials(name) {
  const source = (name || '?').trim()
  const parts = source.split(/\s+/)
  if (parts.length >= 2) {
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
  }
  return source.slice(0, 2).toUpperCase()
}

/** A store's own colour, or the brand clay when it has none set. */
export function storeColor(store) {
  const value = store?.brand_color
  if (typeof value === 'string' && /^#?[0-9a-f]{6}$/i.test(value.trim())) {
    return value.trim().startsWith('#') ? value.trim() : `#${value.trim()}`
  }
  return '#8B5A2B'
}
