import { useEffect, useRef, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import {
  deepArEffectForProductName,
  deepArShoeStatus,
  getDeepArShoeEnv,
} from '../lib/deeparShoe.js'
import { supabase } from '../lib/supabase.js'

/**
 * Hidden QA route: `/deepar-shoe?product=<id>`.
 * DeepAR Web SDK pinned to 5.6.3 (last line with foot tracking) + rear camera.
 * Enter from the app's DeepAR entry or directly in mobile Chrome.
 *
 * Needs (never commit): VITE_DEEPAR_WEB_KEY (Web App key, NOT the Android key).
 * Effects live in public/effects/ (Studio exports, bundled): Luna Loafers +
 * Luxe Cross-Strap Sandals (the latter filed by product name — the page reads
 * `products.name` for a bare uuid and slug-matches it).
 */

export default function DeepArShoe() {
  const [params] = useSearchParams()
  const productId = params.get('product')
  const env = getDeepArShoeEnv()
  const direct = deepArShoeStatus(env, productId)
  // A bare row uuid (what the app links) carries no name — resolve it to the
  // Luxe effect once the product row names it, rather than hardcoding an id
  // the effect handover never recorded.
  const [namedEffect, setNamedEffect] = useState(null)
  useEffect(() => {
    if (direct.effect || !productId) return
    let cancelled = false
    supabase
      .from('products')
      .select('name')
      .eq('id', productId)
      .maybeSingle()
      .then(({ data }) => {
        if (!cancelled && data?.name) setNamedEffect(deepArEffectForProductName(data.name))
      })
    return () => {
      cancelled = true
    }
  }, [direct.effect, productId])
  // When the name resolves, the only honest missing entry is the key — the
  // effect question is answered, and the stub must not still claim it.
  const status = direct.effect
    ? direct
    : {
        ...direct,
        ready: Boolean(namedEffect && env.webKey),
        effect: namedEffect,
        missing: (direct.missing ?? []).filter((m) =>
          namedEffect ? m !== 'no-effect-for-product' : true,
        ),
      }
  const canvasRef = useRef(null)
  const [error, setError] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!status.ready) {
      setLoading(false)
      return
    }
    let cancelled = false
    let deepAR = null

    async function start() {
      try {
        const deepar = await import('deepar')
        if (cancelled) return
        // 5.3.0 API: initialize wants a real <canvas>, not a div.
        // Size it to the screen (×dpr) so a tall phone doesn't stretch
        // the feed — DeepAR fits the camera into these pixels.
        // Rear camera for feet; foot tracking lazy-loads from the effect.
        const canvas = canvasRef.current
        if (!canvas) throw new Error('No canvas element provided.')
        const fitCanvas = () => {
          const dpr = window.devicePixelRatio || 1
          const w = Math.floor(window.innerWidth * dpr)
          const h = Math.floor(window.innerHeight * dpr)
          if (canvas.width !== w || canvas.height !== h) {
            canvas.width = w
            canvas.height = h
          }
        }
        fitCanvas()
        window.addEventListener('resize', fitCanvas)
        try {
          deepAR = await deepar.initialize({
            licenseKey: env.webKey,
            canvas,
            effect: status.effect,
            additionalOptions: {
              cameraConfig: { facingMode: 'environment' },
              hint: 'footInit',
            },
          })
        } finally {
          window.removeEventListener('resize', fitCanvas)
        }
        if (cancelled) return
        setLoading(false)
      } catch (e) {
        if (!cancelled) {
          setError(String(e?.message ?? e))
          setLoading(false)
        }
      }
    }

    start()
    return () => {
      cancelled = true
      try {
        deepAR?.shutdown?.()
      } catch {
        // ignore teardown errors in the spike
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [productId])

  if (!status.ready) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-10">
        <p className="text-sm font-medium text-stone-500">Hidden spike · /deepar-shoe</p>
        <h1 className="mt-2 text-2xl font-semibold">DeepAR shoe spike (web 5.3.0)</h1>
        <div className="mt-4 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm">
          <p className="font-medium">Not configured — stub mode.</p>
          <p className="mt-1">
            Missing: <code>{status.missing.join(', ')}</code>
          </p>
          <p className="mt-1 text-stone-600">
            Add a Web App in developer.deepar.ai (domain only, no https), copy the Web key to{' '}
            <code>.env.local</code> as <code>VITE_DEEPAR_WEB_KEY</code>. Not the Android key.
          </p>
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
    <div data-testid="deepar-shoe-mount" className="fixed inset-0 h-dvh w-full overflow-hidden bg-black">
      <canvas ref={canvasRef} className="h-full w-full object-cover" style={{ objectFit: 'cover' }} />
      {loading && (
        <div className="absolute inset-0 flex items-center justify-center text-center text-sm text-stone-300">
          Loading the shoe… point rear camera at feet.
        </div>
      )}
      <Link
        to={productId ? `/product/${productId}` : '/shop'}
        aria-label="Back"
        className="absolute left-3 top-3 rounded-full bg-stone-950/70 px-3 py-2 text-sm text-stone-100 backdrop-blur"
      >
        ←
      </Link>
      {error && (
        <div className="absolute inset-x-0 bottom-0 bg-stone-950/85 p-3 text-sm text-stone-200">
          DeepAR error: {error}
        </div>
      )}
      {!error && !loading && (
        <div className="absolute inset-x-0 bottom-0 bg-stone-950/60 p-2 text-center text-xs text-stone-300">
          Rear camera · ~1m back · ankle + toes in frame · good light
        </div>
      )}
    </div>
  )
}
