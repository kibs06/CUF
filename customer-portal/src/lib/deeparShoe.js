/** DeepAR Web shoe spike (5.3.0 pinned — last line with feet).
 *
 * Web key is separate from the Android key: developer.deepar.ai → CUFMAI →
 * Web App → + ADD APP (domain, no protocol). Never commit — see `.env.example`.
 * Effect is bundled at /effects/luna_loafers.deepar (copied from Studio export).
 */
export function getDeepArShoeEnv() {
  return {
    webKey: import.meta.env.VITE_DEEPAR_WEB_KEY ?? '',
  }
}

/** `Luxe Cross-Strap Sandals` → `luxe-cross-strap-sandals`. */
export function deepArSlugForName(name) {
  return String(name ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

export function deepArEffectForProduct(productId) {
  const id = String(productId ?? '').trim()
  if (!id) return null
  // Luna Loafers first (same id as the native spike + Snap allow-list).
  if (
    id === '0aebaa64-4d9e-44f8-8876-6b3ee9855fae' ||
    id === 'luna-loafers'
  ) {
    return '/effects/luna_loafers.deepar'
  }
  // Luxe Cross-Strap Sandals, same as Luna: row id first (Caramel colourway),
  // slug for shared links. The product-name fallback below stays as cover for
  // sibling colourways whose row ids were never recorded.
  if (
    id === '77b8c0a3-0f09-41a6-aa70-fc1db04e4cc1' ||
    id === 'luxe-cross-strap-sandals'
  ) {
    return '/effects/luxe_cross_strap_sandals.deepar'
  }
  // JBC Crown Leather Sandals, same as Luxe: slug for shared links. Row ids
  // resolve through the product-name fallback below.
  if (id === 'jbc-crown-leather-sandals') {
    return '/effects/jbc_crown_leather_sandals.deepar'
  }
  return null
}

/** Name-based fallback: any Luxe Cross-Strap Sandals row id resolves once the
 *  page has read its `products.name` (see DeepArShoe). */
export function deepArEffectForProductName(name) {
  const slug = deepArSlugForName(name)
  if (!slug) return null
  if (slug.includes('luxe') && slug.includes('cross') && slug.includes('strap')) {
    return '/effects/luxe_cross_strap_sandals.deepar'
  }
  if (slug.includes('jbc') && slug.includes('crown') && slug.includes('leather')) {
    return '/effects/jbc_crown_leather_sandals.deepar'
  }
  return deepArEffectForProduct(slug)
}

/** Convention URL: `JBC Crown Leather Sandals` → `/effects/jbc_crown_leather_sandals.deepar`.
 *
 *  This is what makes the button automatic: drop a Studio export at
 *  `customer-portal/public/effects/<snake>.deepar`, deploy to Vercel, and the
 *  entry appears with no map edit — the page probes this URL (see
 *  `checkDeepArConventionExists`) and shows the button on a 200. */
export function deepArSnakeForName(name) {
  return deepArSlugForName(name).replace(/-/g, '_')
}

export function deepArConventionEffectForName(name) {
  const snake = deepArSnakeForName(name)
  if (!snake) return null
  return `/effects/${snake}.deepar`
}

const conventionProbeCache = new Map()

/** HEAD-probe for a convention effect URL. Cached per URL: a 200 (or opaque
 *  success) means the file shipped with this deploy, so the button shows;
 *  anything else keeps it hidden exactly as before. Never throws. */
export async function checkDeepArConventionExists(url) {
  if (!url) return false
  if (conventionProbeCache.has(url)) return conventionProbeCache.get(url)
  const promise = (async () => {
    try {
      const res = await fetch(url, { method: 'HEAD' })
      return res.ok
    } catch {
      return false
    }
  })()
  conventionProbeCache.set(url, promise)
  const ok = await promise
  conventionProbeCache.set(url, ok)
  return ok
}

export function deepArShoeStatus(env = getDeepArShoeEnv(), productId) {
  const missing = []
  if (!env.webKey) missing.push('VITE_DEEPAR_WEB_KEY')
  const effect = deepArEffectForProduct(productId)
  if (productId && !effect) missing.push('no-effect-for-product')
  return { ready: missing.length === 0, missing, effect }
}
