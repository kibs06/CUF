import { Suspense, lazy, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { RotateCcw } from 'lucide-react'

import { getLensEnv, lensConfigStatus } from '../lib/lensConfig.js'

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
// Throwaway probe overlay (same constraints, reports real track settings).
// Decides whether the tight framing is browser camera selection or the
// Lens render path. Hidden QA route only — delete before public launch.
const LensCameraDebug = lazy(() => import('./LensCameraDebug.jsx'))

/**
 * Hidden QA route: `/try-lens?product=<id>`.
 * Not linked in nav — entered from the product page's "Try in Snapchat"
 * button (shown only when this Lens is configured AND the product has
 * a model). `FootTryOnViewer` (Prototype B) is untouched.
 *
 * Fullscreen camera: once configured, the page is nothing but the Lens
 * feed — no header, no product card, no footer. A small floating back
 * button is the only chrome, so the whole screen is viewfinder.
 *
 * Needs (never commit — see `.env.example`):
 *   VITE_CAMERAKIT_API_TOKEN, VITE_CAMERAKIT_LENS_ID,
 *   VITE_CAMERAKIT_LENS_GROUP_ID
 */
export default function TryLens() {
  const [params] = useSearchParams()
  const productId = params.get('product')
  const env = getLensEnv()
  const status = lensConfigStatus(env)
  const [lensError, setLensError] = useState(null)
  const [refreshKey, setRefreshKey] = useState(0)

  if (!status.ready) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-10">
        <p className="text-sm font-medium text-stone-500">Hidden spike · /try-lens</p>
        <h1 className="mt-2 text-2xl font-semibold">Lens Studio footwear spike</h1>
        <div className="mt-4 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm">
          <p className="font-medium">Not configured — stub mode.</p>
          <p className="mt-1">
            Missing: <code>{status.missing.join(', ')}</code>
          </p>
          <p className="mt-1 text-stone-600">See docs/BUILD_LENS.md.</p>
        </div>
        <p className="mt-4 text-sm">
          <Link to={productId ? `/product/${productId}` : '/shop'} className="underline">
            ← Back to {productId ? 'product' : 'shop'}
          </Link>
        </p>
      </div>
    )
  }

  return (
    <div data-testid="lens-mount" className="fixed inset-0 h-dvh w-full overflow-hidden bg-black">
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
                // Portrait end-to-end: this phone's track is true portrait
                // (probe: 960x1280 zoom=1). The wrapper swaps w/h on ALL
                // mobile, so match-input sized the render target landscape
                // and cover-cropped the portrait texture = the zoom.
                // Fixed portrait render keeps texture:target:screen all
                // portrait. No cameraRotation: texture is already portrait.
                // zoom ideal 1 asks for 1x at creation — the only zoom hook
                // that works, since the wrapper owns the live track.
                cameraConstraints: {
                  width: { ideal: 960 },
                  height: { ideal: 1280 },
                  zoom: { ideal: 1 },
                },
              },
            }}
            // Fixed portrait render matching probe track: avoids wrapper
            // mobile w/h swap that made match-input landscape.
            outputSize={{ mode: 'fixed', width: 960, height: 1280 }}
            className="h-full w-full [&_canvas]:h-full [&_canvas]:w-full [&_canvas]:object-cover"
            onError={(error) => setLensError(error?.message ?? String(error))}
          />
          <LensSessionState />
          <LensCameraDebug />
        </CameraKitProvider>
      </Suspense>
      {/* The only chrome: a floating back button. Everything else is feed. */}
      <Link
        to={productId ? `/product/${productId}` : '/shop'}
        aria-label="Back"
        className="absolute left-3 top-3 rounded-full bg-stone-950/70 px-3 py-2 text-sm text-stone-100 backdrop-blur"
      >
        ←
      </Link>
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
  )
}
