/** Same `.glb` as the 3D viewer (`useProductModel`); `product_models` stays source of truth. */
export function getLensEnv() {
  return {
    apiToken: import.meta.env.VITE_CAMERAKIT_API_TOKEN ?? '',
    lensId: import.meta.env.VITE_CAMERAKIT_LENS_ID ?? '',
    lensGroupId: import.meta.env.VITE_CAMERAKIT_LENS_GROUP_ID ?? '',
    lensProductIds: import.meta.env.VITE_CAMERAKIT_LENS_PRODUCT_IDS ?? '',
  }
}

/**
 * Products with a published Snap lens. One lens per shoe in Lens Studio, so
 * the single global lens ID must never load for any other product (it would
 * show the wrong shoe). Comma-separated IDs; empty means no product has one.
 */
export function lensAvailableForProduct(env = getLensEnv(), productId) {
  if (!productId) return false
  return String(env.lensProductIds)
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .includes(String(productId))
}

export function lensConfigStatus(env = getLensEnv()) {
  const missing = []
  if (!env.apiToken) missing.push('VITE_CAMERAKIT_API_TOKEN')
  if (!env.lensId) missing.push('VITE_CAMERAKIT_LENS_ID')
  if (!env.lensGroupId) missing.push('VITE_CAMERAKIT_LENS_GROUP_ID')
  return { ready: missing.length === 0, missing }
}
