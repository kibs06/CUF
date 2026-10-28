import { Suspense, lazy, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Footprints, RotateCcw } from 'lucide-react'

import { getLensEnv, lensConfigStatus } from '../lib/lensConfig.js'
import useProductModel from '../hooks/useProductModel.js'

// Lazy so the stub stays light until a published Lens is configured:
// the Camera Kit runtime only downloads when env is ready.
const CameraKitProvider = lazy(() =>
  import('@snap/react-camera-kit').then((m) => ({ default: m.CameraKitProvider })),
)
const LensPlayer = lazy(() =>
  import('@snap/react-camera-kit').then((m) => ({ default: m.LensPlayer })),
)
// Status pill (sdk / camera-source / lens phases) — lazy for the same reason:
// `useCameraKit` lives in the same package, so it shares the split chunk.
const LensSessionState = lazy(() => import('./LensSessionState.jsx'))
// Camera un-zoomer: dials an over-zoomed track back to 1x once the session
// is live. Same chunk as the pill — `useCameraKit` already splits it out.
const LensZoomNormalizer = lazy(() => import('./LensZoomNormalizer.jsx'))

/**
 * Hidden QA route: `/try-lens?product=<id>`.
 * Not linked in nav — entered from the product page's "Try in Snapchat"
 * button (shown only when this Lens is configured AND the product has
 * a model). `FootTryOnViewer` (Prototype B) is untouched.
 *
 * Needs (never commit — see `.env.example`):
 *   VITE_CAMERAKIT_API_TOKEN, VITE_CAMERAKIT_LENS_ID,
 *   VITE_CAMERAKIT_LENS_GROUP_ID
 */
export default function TryLens() {
  const [params] = useSearchParams()
  const productId = params.get('product')
  const { model } = useProductModel(productId)
  const env = getLensEnv()
  const status = lensConfigStatus(env)
  const [lensError, setLensError] = useState(null)
  const [refreshKey, setRefreshKey] = useState(0)

  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      <p className="flex items-center gap-2 text-sm font-medium text-stone-500">
        <Footprints className="h-4 w-4" /> Hidden spike · /try-lens
      </p>
      <h1 className="mt-2 text-2xl font-semibold">Lens Studio footwear spike</h1>

      <div className="mt-4 rounded-xl border border-stone-200 bg-stone-50 p-4 text-sm">
        <p>
          <span className="font-medium">Product:</span> {productId ?? '(no ?product= id)'}
        </p>
        <p className="mt-1 break-all">
          <span className="font-medium">Model URL:</span>{' '}
          {model?.url ?? '— no active product_models row for this product'}
        </p>
      </div>

      {!status.ready ? (
        <div className="mt-4 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm">
          <p className="font-medium">Not configured — stub mode.</p>
          <p className="mt-1">
            Missing: <code>{status.missing.join(', ')}</code>
          </p>
          <p className="mt-1 text-stone-600">See docs/BUILD_LENS.md.</p>
        </div>
      ) : (
        <div
          data-testid="lens-mount"
          className="relative mt-4 aspect-[3/4] overflow-hidden rounded-xl bg-stone-950"
        >
          <Suspense
            fallback={
              <div className="flex h-full items-center justify-center text-center text-sm text-stone-300">
                Loading the Lens…
              </div>
            }
          >
            <CameraKitProvider apiToken={env.apiToken}>
              {/* Rear camera: feet are in front of the phone, not the user.
                  The wrapper defaults to the selfie camera, which is why the
                  mount stayed black — a working pipeline pointed at no feet. */}
              <LensPlayer
                key={refreshKey}
                lensId={env.lensId}
                lensGroupId={env.lensGroupId}
                source={{
                  kind: 'camera',
                  options: {
                    cameraFacing: 'environment',
                    // Widest capture the lens supports: 4:3 matches the mount
                    // (`aspect-[3/4]`) so the box shows the frame, not a crop.
                    cameraConstraints: {
                      width: { ideal: 1280 },
                      height: { ideal: 960 },
                    },
                  },
                }}
                className="h-full w-full"
                onError={(error) => setLensError(error?.message ?? String(error))}
              />
              <LensSessionState />
              <LensZoomNormalizer />
            </CameraKitProvider>
          </Suspense>
          {lensError && (
            <div className="absolute inset-x-0 bottom-0 flex items-center justify-between gap-2 bg-stone-950/85 p-3 text-sm text-stone-200">
              <span className="min-w-0 flex-1 truncate">Lens error: {lensError}</span>
              <button
                type="button"
                onClick={() => {
                  setLensError(null)
                  setRefreshKey((k) => k + 1)
                }}
                className="inline-flex shrink-0 items-center gap-1 rounded-lg border border-stone-600 px-2 py-1 text-xs hover:bg-stone-800"
              >
                <RotateCcw className="h-3 w-3" /> Retry
              </button>
            </div>
          )}
        </div>
      )}

      <p className="mt-4 text-sm">
        <Link to={productId ? `/product/${productId}` : '/shop'} className="underline">
          ← Back to {productId ? 'product' : 'shop'}
        </Link>
      </p>
    </div>
  )
}
