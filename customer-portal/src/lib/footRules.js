/**
 * The foot profile — a port of `lib/utils/customer_profile_fields.dart` and the
 * foot half of `AppConstants`.
 *
 * The app's Size Your Foot screen has two ways in: an AR scan ("Foot Size 2.0")
 * and a manual picker. A browser can do the picker and not the scan, so this is
 * the picker's half of the rules — the same size lists, the same scale labels,
 * the same summary sentence — and it writes the same `profiles` columns
 * (`20260812130000_add_customer_profile_fields.sql`, plus `foot_size_category`
 * from `20260917130000`).
 *
 * Why port it at all rather than let the portal ask for a number: the column is
 * the *shopping size* the whole app reads (`hasFootSize` gates the home
 * reminder, `savedFootSizeCategory` decides whether a product page says US 9 or
 * US 10.5 for the same EU 42). A portal that wrote a free-text size would be
 * writing a value the app cannot interpret.
 *
 * Pure and tested, like the other rule modules, because the size list and the
 * scale labels are exactly the kind of thing that is wrong in a way nobody
 * notices until a customer wears the wrong pair.
 */
import { formatSize } from './sizeKeyRules.js'

/** EU sizes for an adult scale, half-size steps — `customerEuSizes`. */
export const EU_ADULT_SIZES = [
  '35', '35.5', '36', '36.5', '37', '37.5', '38', '38.5', '39', '39.5',
  '40', '40.5', '41', '41.5', '42', '42.5', '43', '43.5', '44', '44.5',
  '45', '45.5', '46', '46.5', '47', '47.5', '48',
]

/**
 * EU sizes for the Kids' scale — `customerKidsEuSizes`.
 *
 * Kids' stops at 35 because the chart's children's band ends there and hands 36
 * and up to the women's/men's bands. Without it a child wearing EU 28 had to
 * pick a size they do not wear.
 */
export const EU_KIDS_SIZES = [
  '22', '22.5', '23', '23.5', '24', '24.5', '25', '25.5', '26', '26.5',
  '27', '27.5', '28', '28.5', '29', '29.5', '30', '30.5', '31', '31.5',
  '32', '32.5', '33', '33.5', '34', '34.5', '35',
]

/** `AppConstants.footWidthOptions` — stored verbatim in `profiles.foot_width`. */
export const FOOT_WIDTHS = ['Narrow', 'Regular', 'Wide']

/**
 * The three shopping scales — `customerFootSizeCategories`.
 *
 * A sizing SCALE, not identity: EU 42 is EU 42 for everyone, but it is labelled
 * US 9 on the men's chart and US 10.5 on the women's. A woman shopping men's
 * shoes picks Men's; the account's `gender` answers a different question.
 */
export const FOOT_SIZE_CATEGORIES = [
  { value: 'men', label: "Men's" },
  { value: 'women', label: "Women's" },
  { value: 'kids', label: "Kids'" },
]

/** `AppConstants.footProfile*` — the `foot_profile_source` values. */
export const FOOT_PROFILE_SOURCE = {
  arScan: 'ar_scan',
  manual: 'manual',
  skipped: 'skipped',
}

/** The sizes the picker offers for a scale — `customerEuSizesFor`. */
export function euSizesFor(category) {
  return category === 'kids' ? EU_KIDS_SIZES : EU_ADULT_SIZES
}

/** `'men'` → `"Men's"`, or null when unset/unrecognised — never a guess. */
export function footSizeCategoryLabel(value) {
  const found = FOOT_SIZE_CATEGORIES.find((option) => option.value === value)
  return found ? found.label : null
}

/**
 * A stored size as it is displayed: `40` stays `40`, `40.5` stays `40.5`.
 *
 * `size_key.dart`'s `formatSizeNumber`, and the reason it exists is that a
 * NUMERIC column round-trips as `40.0` — a size nobody has ever worn.
 */
export function formatFootSize(raw) {
  if (raw === null || raw === undefined || raw === '') return ''
  const number = Number(raw)
  if (!Number.isFinite(number)) return String(raw).trim()
  // `String(40)` is "40" in JavaScript, unlike Dart's `40.0.toString()`, so
  // there is no trailing-zero branch to get wrong here.
  return String(number)
}

/**
 * Whether the customer has a usable foot size on file — `hasFootSize`.
 *
 * TWO independent markers count, because either can be the only one left
 * behind: the source, or the stored size. `skipped` deliberately does NOT count
 * as set — "skip" must never mean "never ask again silently".
 */
export function hasFootSize(profile) {
  if (!profile) return false
  const source = profile.foot_profile_source
  if (source && source !== '' && source !== FOOT_PROFILE_SOURCE.skipped) return true

  const size = profile.foot_size_ph
  if (size === null || size === undefined) return false
  return String(size).trim() !== ''
}

/**
 * `footProfileSummary` — the row's subtitle in the app, and here.
 *
 * `Not set yet` / `EU 40 · Men's · set manually` / `EU 42 · from your AR scan`.
 * The provenance is the point: a scan and a guess look identical as a number,
 * and a customer about to buy a pair that does not fit should be able to see
 * which one they are trusting.
 */
export function footProfileSummary(profile) {
  if (!hasFootSize(profile)) return 'Not set yet'

  const size = formatFootSize(profile.foot_size_ph)
  if (!size) return 'Not set yet'

  const label = footSizeCategoryLabel(profile.foot_size_category)
  // The unit comes from the one size formatter, not from a literal here:
  // `foot_size_ph` stores a bare number, and `sizeKeyRules` is the single place
  // that decides a bare size is EU (the app's P0 cleanup, plan §4.2).
  const withScale = label ? `${formatSize(size)} · ${label}` : formatSize(size)

  switch (profile.foot_profile_source) {
    case FOOT_PROFILE_SOURCE.arScan:
      return `${withScale} · from your AR scan`
    case FOOT_PROFILE_SOURCE.manual:
      return `${withScale} · set manually`
    default:
      return withScale
  }
}

/** An empty manual-entry draft. */
export function emptyFootDraft(overrides = {}) {
  return { category: '', size: '', width: '', ...overrides }
}

/** A `profiles` row as a draft. */
export function footDraftFromProfile(profile) {
  if (!hasFootSize(profile)) return emptyFootDraft()
  return emptyFootDraft({
    category: footSizeCategoryLabel(profile.foot_size_category)
      ? profile.foot_size_category
      : '',
    size: formatFootSize(profile.foot_size_ph),
    width: profile.foot_width ?? '',
  })
}

/**
 * Every problem with a draft, keyed by field.
 *
 * A scale and a size are both required, and the size must be one this scale
 * actually offers: EU 45 is not a children's size, and accepting it would store
 * a value the chart cannot place.
 */
export function footDraftErrors(draft) {
  const errors = {}

  if (!draft?.category) {
    errors.category = 'Pick the scale you shop in'
  } else if (!FOOT_SIZE_CATEGORIES.some((option) => option.value === draft.category)) {
    errors.category = 'Pick the scale you shop in'
  }

  const size = String(draft?.size ?? '').trim()
  if (!size) {
    errors.size = 'Pick your size'
  } else if (!euSizesFor(draft?.category).includes(size)) {
    errors.size = `That is not a size in the ${
      draft?.category === 'kids' ? "Kids'" : 'adult'
    } range`
  }

  if (draft?.width && !FOOT_WIDTHS.includes(draft.width)) {
    errors.width = 'Pick one of the listed widths'
  }

  return errors
}

export function isFootDraftComplete(draft) {
  return Object.keys(footDraftErrors(draft)).length === 0
}

/**
 * The `profiles` update for a manual foot size.
 *
 * `foot_size_ph` is NUMERIC, so the half-size goes back as a number. Width is
 * only written when chosen — an empty string would be a width nobody picked.
 *
 * `foot_profile_source` is `manual`, which is load-bearing: it is what tells
 * the app (and the customer, in the summary) that this number was typed, not
 * measured.
 */
export function footProfilePayload(draft, now = new Date()) {
  const size = String(draft?.size ?? '').trim()
  return {
    foot_size_ph: Number(size),
    foot_width: draft?.width ? draft.width : null,
    foot_size_category: draft?.category || null,
    foot_profile_source: FOOT_PROFILE_SOURCE.manual,
    foot_profile_updated_at: now.toISOString(),
  }
}

/**
 * The update that records "asked and declined".
 *
 * Deliberately keeps the size and the scale: `saveFootProfile`'s comment in the
 * app says a write that does not carry a scale must not erase the one already
 * on file, and skipping the question is not a reason to forget the answer.
 * `skipped` is what stops the reminder nagging; the size itself is what the
 * size-aware surfaces still need.
 */
export function footProfileSkippedPayload(now = new Date()) {
  return {
    foot_profile_source: FOOT_PROFILE_SOURCE.skipped,
    foot_profile_updated_at: now.toISOString(),
  }
}

/** A PostgREST failure as something a customer can act on. */
export function footProfileError(error, fallback = 'We could not save your size. Please try again.') {
  const code = error?.code ?? null
  const raw = String(error?.message ?? '').trim()

  if (code === '23514' || /check constraint/i.test(raw)) {
    return 'That size or scale is not one we can store. Please pick from the list.'
  }
  if (code === '42501' || /permission denied|not authenticated/i.test(raw)) {
    return 'Your session has expired. Please sign in again.'
  }
  if (raw && !/^JSON|^Failed to fetch|network/i.test(raw)) return raw
  return fallback
}
