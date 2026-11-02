import { useEffect, useRef, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import {
  checkDeepArConventionExists,
  deepArConventionEffectForName,
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
  // An uploaded effect wins over every bundled one: it is the product's own
  // Studio file, published from the admin shelf, and it works for any row id
  // without hardcoding. Below it, the old resolutions in order — direct map
  // (Luna ids, Luxe slug), then the product-name fallback for a bare uuid.
  const [dbEffect, setDbEffect] = useState(null)
  const [namedEffect, setNamedEffect] = useState(null)
  // Convention fallback: the `/effects/<snake>.deepar` file shipped with
  // this deploy. Probed (HEAD) only when nothing else answered, so a new
  // shoe goes live with just the file + deploy — no map edit.
  const [conventionEffect, setConventionEffect] = useState(null)
  useEffect(() => {
    if (!productId) return
    let cancelled = false
    supabase
      .from('product_ar_effects')
      .select('storage_path')
      .eq('product_id', productId)
      .eq('status', 'active')
      .order('version', { ascending: false })
      .limit(1)
      .maybeSingle()
      .then(({ data }) => {
        if (cancelled) return
        if (data?.storage_path) {
          const { data: pub } = supabase.storage
            .from('shoe-ar-effects')
            .getPublicUrl(data.storage_path)
          if (pub?.publicUrl) setDbEffect(pub.publicUrl)
        }
      })
    return () => {
      cancelled = true
    }
  }, [productId])
  useEffect(() => {
    if (direct.effect || dbEffect || !productId) return
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
  }, [direct.effect, dbEffect, productId])
  useEffect(() => {
    if (direct.effect || dbEffect || namedEffect || !productId) return
    let cancelled = false
    supabase
      .from('products')
      .select('name')
      .eq('id', productId)
      .maybeSingle()
      .then(async ({ data }) => {
        if (cancelled || !data?.name) return
        const url = deepArConventionEffectForName(data.name)
        if (!url) return
        if (await checkDeepArConventionExists(url)) {
          if (!cancelled) setConventionEffect(url)
        }
      })
    return () => {
      cancelled = true
    }
  }, [direct.effect, dbEffect, namedEffect, productId])
  // The first resolution that answers wins; when one does, the only honest
  // missing entry is the key — the effect question is answered, and the stub
  // must not still claim it.
  const resolved = dbEffect ?? direct.effect ?? namedEffect ?? conventionEffect
  const status = resolved
    ? {
        ...direct,
        ready: Boolean(env.webKey),
        effect: resolved,
        missing: (direct.missing ?? []).filter((m) => m !== 'no-effect-for-product'),
      }
    : direct
  const canvasRef = useRef(null)
  const [error, setError] = useState(null)
  const [loading, setLoading] = useState(true)
  // What the loader is waiting on right now, so a slow start names its
  // stage instead of one flat line. `showSlowHint` flips after 30 s of
  // still loading — a phone on a slow connection (or with the camera
  // permission prompt unanswered) otherwise sits on the same sentence
  // with no way to tell waiting from stuck.
  const [loadStage, setLoadStage] = useState('Starting camera…')
  const [showSlowHint, setShowSlowHint] = useState(false)
  // Which effect URL the live DeepAR instance was started for. The effect
  // often resolves *after* first paint (uploaded-row read, then the
  // product-name fallback for a bare uuid like Luxe) — without this the
  // one-shot `[productId]` init ran while `status.ready` was still false,
  // the canvas then mounted with no instance behind it: a pure black
  // screen with no error.
  const startedForRef = useRef(null)

  useEffect(() => {
    if (!status.ready) {
      setLoading(false)
      return
    }
    if (startedForRef.current === status.effect) return
    startedForRef.current = status.effect
    setError(null)
    setLoading(true)
    setShowSlowHint(false)
    setLoadStage('Downloading camera engine…')
    let cancelled = false
    let deepAR = null
    // Name the wait instead of timing out: the SDK + WASM + effect can
    // take a minute on a slow connection, and the camera-permission
    // prompt can sit unanswered — both look like a freeze on one line.
    const slowTimer = setTimeout(() => {
      if (!cancelled) setShowSlowHint(true)
    }, 30000)

    async function start() {
      try {
        const deepar = await import('deepar')
        if (cancelled) return
        setLoadStage('Loading shoe…')
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
        // The camera-permission prompt appears during initialize on most
        // phones — the stage line tells the customer to look for it.
        setLoadStage('Opening camera — allow access when asked…')
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
        clearTimeout(slowTimer)
        setLoading(false)
      } catch (e) {
        if (!cancelled) {
          clearTimeout(slowTimer)
          setError(String(e?.message ?? e))
          setLoading(false)
        }
      }
    }

    start()
    return () => {
      cancelled = true
      clearTimeout(slowTimer)
      // Only tear down the instance this run created: the ready→not-ready
      // flip unmounts the canvas anyway, and clearing the ref lets a later
      // effect URL start fresh.
      startedForRef.current = null
      try {
        deepAR?.shutdown?.()
      } catch {
        // ignore teardown errors in the spike
      }
    }
  }, [productId, status.ready, status.effect])

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
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 px-8 text-center text-sm text-stone-300">
          <p>{loadStage}</p>
          <p className="text-xs text-stone-500">Point rear camera at feet.</p>
          {showSlowHint && (
            <p className="mt-2 max-w-xs text-xs leading-relaxed text-stone-400">
              Still loading — usually a slow connection or the camera permission
              waiting for an answer. Check the permission prompt, move to faster
              Wi-Fi, and close background tabs, then reopen this page.
            </p>
          )}
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
