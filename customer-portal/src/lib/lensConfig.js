/** Same `.glb` as the 3D viewer (`useProductModel`); `product_models` stays source of truth. */
export function getLensEnv() {
  return {
    apiToken: import.meta.env.VITE_CAMERAKIT_API_TOKEN ?? '',
    lensId: import.meta.env.VITE_CAMERAKIT_LENS_ID ?? '',
    lensGroupId: import.meta.env.VITE_CAMERAKIT_LENS_GROUP_ID ?? '',
  }
}

export function lensConfigStatus(env = getLensEnv()) {
  const missing = []
  if (!env.apiToken) missing.push('VITE_CAMERAKIT_API_TOKEN')
  if (!env.lensId) missing.push('VITE_CAMERAKIT_LENS_ID')
  if (!env.lensGroupId) missing.push('VITE_CAMERAKIT_LENS_GROUP_ID')
  return { ready: missing.length === 0, missing }
}
