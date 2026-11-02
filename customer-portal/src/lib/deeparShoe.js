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
  return null
}

export function deepArShoeStatus(env = getDeepArShoeEnv(), productId) {
  const missing = []
  if (!env.webKey) missing.push('VITE_DEEPAR_WEB_KEY')
  const effect = deepArEffectForProduct(productId)
  if (productId && !effect) missing.push('no-effect-for-product')
  return { ready: missing.length === 0, missing, effect }
}
