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
  // Luxe by slug: the app links `?product=<uuid>`, and the effect was filed
  // by product name, so the page resolves the name (see DeepArShoe) and the
  // direct slug still works for shared links.
  if (id === 'luxe-cross-strap-sandals') {
    return '/effects/luxe_cross_strap_sandals.deepar'
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
  return deepArEffectForProduct(slug)
}

export function deepArShoeStatus(env = getDeepArShoeEnv(), productId) {
  const missing = []
  if (!env.webKey) missing.push('VITE_DEEPAR_WEB_KEY')
  const effect = deepArEffectForProduct(productId)
  if (productId && !effect) missing.push('no-effect-for-product')
  return { ready: missing.length === 0, missing, effect }
}
