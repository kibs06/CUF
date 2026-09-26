import { storeColor } from './constants.js'

/**
 * A store's banner, and what to paint when there isn't one — a port of
 * `Store.bannerUrl` and `Store.cardGradient` from `lib/models/store.dart`.
 *
 * `stores.banner_url` has been in the schema since the app's store profiles
 * shipped, and the app's hero card paints it full-bleed with the brand gradient
 * behind it as both the placeholder and the error state. The portal was reading
 * the column (every store query is a `select('*')`) and never drawing it, so a
 * workshop that had uploaded a storefront photograph — two of the three live
 * stores have — appeared on the makers page with no photograph at all.
 *
 * Pure and separate for the usual reason: the awkward cases are all about
 * values, not about pixels — a banner column that exists but holds `''`, a
 * whitespace string, a null, a row that has not been migrated — and none of
 * those need a DOM to be worth being sure about.
 */

/** The dark end of the brand gradient — `Color(0xFF1A1208)` in the app. */
const ESPRESSO = [0x1a, 0x12, 0x08]

/** How far the brand colour is pushed towards espresso: `Color.lerp(…, 0.55)`. */
export const BANNER_GRADIENT_MIX = 0.55

/**
 * The store's banner URL, or `null` when there is nothing worth putting in an
 * `src`.
 *
 * The app's guard is `bannerUrl != null && bannerUrl!.isNotEmpty`, and the
 * portal is stricter on purpose: a column that holds `''`, `'   '` or a
 * non-string is the same thing as a missing banner to a browser — except that
 * an empty `src` makes it re-request the current page, so the stricter version
 * is also the one that cannot cause a second page load per card.
 */
export function storeBannerUrl(store) {
  const value = store?.banner_url
  if (typeof value !== 'string') return null
  return value.trim() || null
}

/**
 * A `#RRGGBB` colour blended `amount` of the way to the gradient's dark end,
 * per channel — how Flutter's `Color.lerp` computes it.
 *
 * Anything that is not a six-digit hex comes back untouched rather than as
 * `NaN` in a gradient: an unparseable colour must degrade to "no gradient
 * styling", never to an `rgb(NaN, …)` the browser silently drops.
 */
export function mixTowardEspresso(hex, amount = BANNER_GRADIENT_MIX) {
  const match = /^#?([0-9a-f]{6})$/i.exec(String(hex ?? '').trim())
  if (!match) return hex

  const channels = [0, 2, 4].map((offset) => {
    const value = parseInt(match[1].slice(offset, offset + 2), 16)
    const target = ESPRESSO[offset / 2]
    return Math.round(value + (target - value) * amount)
  })

  return `#${channels.map((channel) => channel.toString(16).padStart(2, '0')).join('')}`
}

/**
 * The CSS gradient a banner-less store gets: `Store.cardGradient`'s top-left →
 * bottom-right blend from the store's own colour into espresso.
 *
 * `storeColor` owns the "what is this store's colour, and what if it has none"
 * decision, so a store with no `brand_color` gets clay here for the same reason
 * its avatar does.
 */
export function storeCardGradient(store) {
  const color = storeColor(store)
  return `linear-gradient(135deg, ${color} 0%, ${mixTowardEspresso(color)} 100%)`
}
