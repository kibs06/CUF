import { Suspense, lazy, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { RotateCcw } from 'lucide-react'

import { getLensEnv, lensConfigStatus } from '../lib/lensConfig.js'

// Direct player owns its own MediaStream, so it can open any physical
// camera by deviceId (the wrapper drops deviceId on all mobile) and dial
// zoom to minimum. Lazy so the Camera Kit runtime stays out of the main
// bundle until this hidden route mounts.
const DirectLensPlayer = lazy(() => import('./DirectLensPlayer.jsx'))

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
          {/* Direct player: rear camera by default, feet in front of the phone. */}
          <DirectLensPlayer
            key={refreshKey}
            apiToken={env.apiToken}
            lensId={env.lensId}
            lensGroupId={env.lensGroupId}
            onError={(message) => setLensError(message)}
          />
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
