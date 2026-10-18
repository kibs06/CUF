import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { Footprints, X } from 'lucide-react'

import ConfirmDialog from '../ui/ConfirmDialog.jsx'
import { APP_DOWNLOAD_URL, tryOnAppPrompt } from '../../lib/appDownload.js'
import { useScrollLock } from '../../hooks/useScrollLock.js'
import {
  pickFoot,
  placementFromFoot,
  shouldDrawShoe,
  smoothAngle,
  smoothPoint,
} from '../../lib/footTryOn.js'

/**
 * **Foot-tracked try-on (beta)** — the shoe stuck to the foot, in the browser.
 *
 * The rear camera feeds MediaPipe Pose Landmarker (Lite, in a Web Worker —
 * the video call blocks its thread) while Three.js draws the *same* verified
 * `.glb` the 3D viewer draws, laid flat over the foot's heel→toe axis and
 * scaled to its length. Sibling of `Product3DViewer`: same dialog shape,
 * same scroll lock, same Escape layering, same honest footer.
 *
 * What this is not, stated up front in the UI as well as here: the tracker
 * sees three points per foot (ankle, heel, foot-index), so this is a
 * screen-space sticker that follows, turns and sizes with the foot — not the
 * fitted, occluded, depth-measured try-on the app does. The footer says
 * "approximate" and offers the app for the precise fit.
 *
 * Failure states, each drawn rather than thrown:
 * - camera denied / absent → a sentence + the app door;
 * - worker fails to start → one silent retry on the main thread, and
 *   only if that fails too, a sentence + the app door;
 * - tracker or model fails to load → a sentence + the app door;
 * - foot leaves frame → the shoe coasts briefly, then a coaching line
 *   ("Step back so ankle and toes show") replaces it — the pose model
 *   needs ankle + toes, not a toe close-up.
 */
/** What the loading overlay names while the try-on starts up, in order. */
const LOAD_PHASE_LABELS = {
  starting: 'Starting…',
  '3d library': 'Loading the 3D engine…',
  camera: 'Starting the camera…',
  'shoe model': 'Loading the shoe…',
  'foot tracker': 'Loading the foot tracker…',
  'foot tracker (main thread)': 'Loading the foot tracker…',
}

export default function FootTryOnViewer({ open, url, name, onClose }) {
  const [status, setStatus] = useState('loading')
  // Which start step the overlay names — mirrors `track.phase` in state so
  // the page re-renders as each download finishes.
  const [loadPhase, setLoadPhase] = useState('starting')
  const [hasFoot, setHasFoot] = useState(false)
  const [tryOnOpen, setTryOnOpen] = useState(false)
  const [aspect, setAspect] = useState(null)
  // Why a start failed, in the tracker's own words — shown under the error
  // heading so a report from a phone carries its diagnosis with it.
  const [errorDetail, setErrorDetail] = useState(null)
  // Retry count: bumping it re-runs the whole start sequence.
  const [attempt, setAttempt] = useState(0)
  // Camera zoom, when the phone's camera exposes it: { value, min, max }.
  // Starts at min (widest) — the complaint this answers is that the feed
  // opens looking ~2x into the feet with nowhere to step back to.
  const [zoom, setZoom] = useState(null)
  const closeRef = useRef(null)
  const videoRef = useRef(null)

  // Everything the frame loop touches lives in refs — the loop must never
  // re-render the page at camera rate.
  const trackRef = useRef({
    worker: null,
    workerReady: false,
    inflight: false,
    stream: null,
    camTrack: null,
    raf: 0,
    timer: 0,
    three: null,
    side: null,
    heel: null,
    toe: null,
    angle: null,
    length: null,
    lastSeen: NaN,
    showing: false,
    disposed: false,
    // Which start step the setup is waiting on when it stalls — the timeout
    // reports this, so a slow connection names its missing piece.
    phase: 'starting',
    // Main-thread fallback state: set once, so a failing worker gets exactly
    // one second chance and retries start clean.
    fellBack: false,
    mainTracker: null,
  })

  useEffect(() => {
    if (!open) return undefined
    const track = trackRef.current
    track.disposed = false
    setStatus('loading')
    setLoadPhase('starting')
    setHasFoot(false)
    setAspect(null)
    setErrorDetail(null)
    setZoom(null)
    track.camTrack = null
    track.phase = 'starting'
    setLoadPhase('starting')
    track.fellBack = false
    track.mainTracker = null
    track.side = null
    track.heel = null
    track.toe = null
    track.angle = null
    track.length = null
    track.lastSeen = NaN
    track.showing = false

    let cancelled = false

    // Every start failure lands here with its reason: the heading names the
    // state, `errorDetail` carries the cause to the screen and the console.
    const fail = (detail) => {
      if (cancelled) return
      window.clearTimeout(track.stallTimer)
      if (detail) {
        setErrorDetail(String(detail).slice(0, 160))
        try {
          console.error('[foot-tryon]', detail)
        } catch {
          // Logging must never break the fallback UI.
        }
      }
      setStatus('error')
    }

    // The worker is the fast path, but its wasm bootstrap can fail where
    // the main thread succeeds (module workers have no `importScripts`, and
    // the script-tag fallback needs a `document` workers lack). Any
    // init-phase worker failure lands here: same detector, same math, this
    // thread — only if that fails too does the error reach the screen.
    const startMainThreadFallback = async (workerDetail) => {
      const t = trackRef.current
      if (cancelled || t.fellBack) return
      t.fellBack = true
      t.worker?.terminate()
      t.worker = null
      t.phase = 'foot tracker (main thread)'
      if (!cancelled) setLoadPhase('foot tracker (main thread)')
      armStallTimer()
      try {
        const { createMainThreadTracker } = await import(
          '../../lib/footTrackerMain.js'
        )
        if (cancelled) return
        t.mainTracker = await createMainThreadTracker()
        if (cancelled) return
        window.clearTimeout(track.stallTimer)
        setStatus('live')
      } catch (err) {
        fail(
          `worker: ${workerDetail ?? 'start failed'} / main: ${err?.message ?? 'start failed'}`,
        )
      }
    }

    // A stall is a failure with a name. On a slow connection every download
    // hangs instead of throwing, so without this the page sits on its
    // spinner forever; with it, the wait names the missing piece. A stall
    // while the worker itself is starting gets one fallback attempt first.
    const armStallTimer = () => {
      window.clearTimeout(track.stallTimer)
      track.stallTimer = window.setTimeout(() => {
        const t = trackRef.current
        if (t.disposed) return
        if (t.phase === 'foot tracker' && !t.workerReady && !t.fellBack) {
          startMainThreadFallback('stalled starting')
          return
        }
        fail(`still waiting on ${t.phase} — connection too slow?`)
      }, 45000)
    }
    armStallTimer()

    const setup = async () => {
      // The two heavy downloads happen only for a visit that taps the
      // button — same rule as the 3D viewer's dynamic import.
      track.phase = '3d library'
      if (!cancelled) setLoadPhase('3d library')
      const [three, loaderMod] = await Promise.all([
        import('three'),
        import('three/examples/jsm/loaders/GLTFLoader.js'),
      ])
      if (cancelled) return
      const THREE = three

      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: 'environment',
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
        audio: false,
      })
      if (cancelled) {
        stream.getTracks().forEach((t) => t.stop())
        return
      }
      track.phase = 'camera'
      if (!cancelled) setLoadPhase('camera')
      track.stream = stream
      track.camTrack = stream.getVideoTracks()[0] ?? null

      // Widest view first, where the hardware allows it. Several phone
      // cameras open part-way into their zoom range, which reads as a
      // broken zoomed-in feed next to the camera app.
      try {
        const caps = track.camTrack?.getCapabilities?.()
        if (caps?.zoom && Number.isFinite(caps.zoom.min)) {
          const min = caps.zoom.min
          const max = caps.zoom.max ?? min
          if (max > min) {
            await track.camTrack
              ?.applyConstraints({ advanced: [{ zoom: min }] })
              .catch(() => {})
            if (!cancelled) setZoom({ value: min, min, max })
          }
        }
      } catch {
        // No zoom capability on this camera — the slider stays hidden.
      }

      const video = videoRef.current
      if (!video) {
        stream.getTracks().forEach((t) => t.stop())
        return
      }
      video.srcObject = stream
      await video.play()
      if (cancelled) return
      const vw = video.videoWidth
      const vh = video.videoHeight
      if (!vw || !vh) {
        fail()
        return
      }
      setAspect(`${vw} / ${vh}`)

      // Overlay renderer: transparent, exactly the video's pixels, so one
      // three unit is one video pixel and the shoe lands where the math says.
      const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true })
      renderer.setSize(vw, vh)
      renderer.domElement.style.display = 'block'
      renderer.domElement.style.width = '100%'
      renderer.domElement.style.height = '100%'
      const holder = video.parentElement?.querySelector('[data-tryon-stage]')
      holder?.appendChild(renderer.domElement)

      const scene = new THREE.Scene()
      const camera = new THREE.OrthographicCamera(
        -vw / 2, vw / 2, vh / 2, -vh / 2, 0.1, 100,
      )
      camera.position.set(0, 0, 10)
      camera.lookAt(0, 0, 0)
      scene.add(new THREE.HemisphereLight(0xffffff, 0x444455, 1.6))
      const key = new THREE.DirectionalLight(0xffffff, 1.4)
      key.position.set(2, 4, 6)
      scene.add(key)

      // yaw → flat → normalized model. Nesting keeps each rotation honest:
      // the yaw turns in screen space, the flat lays the shoe down, and the
      // inner fit removes the model's own size and centering.
      const yawGroup = new THREE.Group()
      const flatGroup = new THREE.Group()
      flatGroup.rotation.x = -Math.PI / 2
      yawGroup.add(flatGroup)
      yawGroup.visible = false
      scene.add(yawGroup)

      track.phase = 'shoe model'
      if (!cancelled) setLoadPhase('shoe model')
      const gltf = await new loaderMod.GLTFLoader().loadAsync(url)
      if (cancelled) return
      const model = gltf.scene
      const box = new THREE.Box3().setFromObject(model)
      const size = new THREE.Vector3()
      const center = new THREE.Vector3()
      box.getSize(size)
      box.getCenter(center)
      if (!(size.z > 1e-6)) {
        fail()
        return
      }
      // Unit length along the model's forward axis (toe on +Z by the
      // authoring contract), heel at the origin, sole on the ground.
      const s = 1 / size.z
      const inner = new THREE.Group()
      inner.add(model)
      inner.scale.set(s, s, s)
      inner.position.set(-center.x * s, -box.min.y * s, (-center.z + size.z / 2) * s)
      flatGroup.add(inner)

      track.three = { THREE, renderer, scene, camera, yawGroup }

      track.phase = 'foot tracker'
      if (!cancelled) setLoadPhase('foot tracker')
      const worker = new Worker(
        new URL('../../lib/footTracker.worker.js', import.meta.url),
        { type: 'module' },
      )
      track.worker = worker
      // Named so the main-thread fallback can feed it synthetic pose
      // messages — one handler for feet however they arrive.
      const onWorkerMessage = (event) => {
        const msg = event.data
        if (msg?.type === 'ready') {
          if (cancelled) return
          track.workerReady = true
          window.clearTimeout(track.stallTimer)
          setStatus('live')
          return
        }
        if (msg?.type === 'error') {
          // Init-phase worker failures fall through to the main thread;
          // only a mid-stream failure is fatal.
          if (!trackRef.current.workerReady) {
            startMainThreadFallback(msg.message ?? 'tracker download failed')
            return
          }
          fail(msg.message ?? 'tracker download failed')
          return
        }
        if (msg?.type !== 'pose') return
        track.inflight = false
        const t = trackRef.current
        const foot = pickFoot(msg.feet ?? [], t.side)
        const now = performance.now()
        if (foot) {
          t.side = foot.side
          const place = placementFromFoot(foot, vw, vh)
          if (place) {
            t.heel = smoothPoint(t.heel, place.heel)
            t.toe = smoothPoint(t.toe, place.toe)
            t.angle = smoothAngle(t.angle, place.angleRad)
            t.length =
              t.length === null
                ? place.lengthPx
                : t.length + 0.4 * (place.lengthPx - t.length)
            t.lastSeen = now
          }
        }
        const draw = shouldDrawShoe({
          seenNow: Boolean(foot),
          lastSeenMs: t.lastSeen,
          nowMs: now,
        })
        if (draw !== t.showing) {
          t.showing = draw
          if (!cancelled) setHasFoot(draw)
        }
        if (draw && t.heel && t.toe && t.angle !== null && t.length) {
          // Screen space is y-down; three is y-up. The toe direction
          // (dx, dy) on screen is (dx, −dy) in the scene, and the yaw that
          // takes the model's +Y-projected toe onto it is atan2(−dx, −dy).
          const dx = t.toe.x - t.heel.x
          const dy = t.toe.y - t.heel.y
          yawGroup.position.set(t.heel.x - vw / 2, vh / 2 - t.heel.y, 0)
          yawGroup.rotation.z = Math.atan2(-dx, -dy)
          yawGroup.scale.set(t.length, t.length, t.length)
          yawGroup.visible = true
        } else {
          yawGroup.visible = false
        }
      }
      worker.onmessage = onWorkerMessage
      worker.onerror = () => {
        // Same rule as a posted error: init-phase failure falls through to
        // the main thread; only a mid-stream failure is fatal.
        if (!trackRef.current.workerReady) {
          startMainThreadFallback('tracker file failed to start')
          return
        }
        fail('tracker file failed to start')
      }
      worker.postMessage({ type: 'init' })

      // The pump: at most one frame in flight, so a slow phone degrades to
      // fewer answers rather than a queue of stale ones. On the main-thread
      // fallback the video element goes straight into the detector and the
      // feet re-enter through the same message handler — no bitmap copy.
      track.timer = window.setInterval(() => {
        const t = trackRef.current
        if (t.disposed) return
        const v = videoRef.current
        if (!v || v.readyState < 2) return
        if (t.mainTracker) {
          if (t.inflight) return
          t.inflight = true
          try {
            const feet = t.mainTracker.detect(v, performance.now())
            if (!t.disposed) onWorkerMessage({ data: { type: 'pose', feet } })
            else t.inflight = false
          } catch {
            // A dropped frame is silence, never a fault: the page coasts.
            t.inflight = false
          }
          return
        }
        if (!t.workerReady || t.inflight) return
        t.inflight = true
        createImageBitmap(v)
          .then((bitmap) => {
            if (t.disposed) {
              bitmap.close()
              return
            }
            t.worker?.postMessage(
              { type: 'frame', bitmap, timestampMs: performance.now() },
              [bitmap],
            )
          })
          .catch(() => {
            t.inflight = false
          })
      }, 100)

      const loop = () => {
        if (track.disposed) return
        track.raf = requestAnimationFrame(loop)
        track.three?.renderer.render(track.three.scene, track.three.camera)
      }
      loop()

      // Stay on the loading overlay until the worker says `ready` (or the
      // fallback does). Going `live` here is the stuck-pill bug: the pump
      // sends nothing until `workerReady`, so the page would show the
      // camera + "point at your feet" forever while the ~19 MB tracker
      // download is still in flight. The stall timer stays armed meanwhile
      // so a slow connection names its missing piece instead of hanging.
    }

    setup().catch((err) => {
      // A denied camera is the common case, and it has its own face below.
      if (err?.name === 'NotAllowedError') {
        if (!cancelled) {
          window.clearTimeout(track.stallTimer)
          setStatus('denied')
        }
        return
      }
      fail(err?.message ?? 'start failed')
    })

    return () => {
      cancelled = true
      track.disposed = true
      cancelAnimationFrame(track.raf)
      window.clearInterval(track.timer)
      window.clearTimeout(track.stallTimer)
      track.worker?.terminate()
      track.worker = null
      track.workerReady = false
      track.inflight = false
      try {
        track.mainTracker?.close()
      } catch {
        // Already closed — harmless.
      }
      track.mainTracker = null
      track.stream?.getTracks().forEach((t) => t.stop())
      track.stream = null
      track.three?.renderer.dispose()
      const el = track.three?.renderer.domElement
      el?.parentElement?.removeChild(el)
      track.three = null
      if (videoRef.current) videoRef.current.srcObject = null
    }
  }, [open, url, attempt])

  useEffect(() => {
    if (!open) return undefined
    const onKeyDown = (event) => {
      if (event.key === 'Escape' && !tryOnOpen) onClose?.()
    }
    window.addEventListener('keydown', onKeyDown)
    closeRef.current?.focus()
    return () => {
      window.removeEventListener('keydown', onKeyDown)
    }
  }, [open, onClose, tryOnOpen])

  useScrollLock(open)

  if (!open || !url) return null

  return (
    <>
      {createPortal(
        <div
          className="fade-enter fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-scrim p-3 backdrop-blur-[2px] sm:items-center sm:p-6"
          onClick={() => onClose?.()}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="foot-tryon-title"
            onClick={(event) => event.stopPropagation()}
            className="rise-enter w-full max-w-5xl overflow-hidden rounded-card border border-hairline bg-raised shadow-premium"
          >
            <header className="flex items-center gap-2.5 border-b border-hairline-soft px-4 py-3 sm:px-5">
              <Footprints size={16} strokeWidth={2} className="shrink-0 text-clay-ink" />
              <h2
                id="foot-tryon-title"
                className="min-w-0 flex-1 truncate font-display text-base font-semibold text-ink"
              >
                {name} — try on your feet
              </h2>
              <button
                ref={closeRef}
                type="button"
                onClick={() => onClose?.()}
                aria-label="Close the foot try-on"
                className="-mr-1 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-muted transition-colors duration-200 hover:bg-subtle hover:text-ink"
              >
                <X size={16} strokeWidth={2} />
              </button>
            </header>

            <div
              className="relative w-full bg-black"
              style={aspect ? { aspectRatio: aspect } : { aspectRatio: '4 / 3' }}
            >
              {/* The camera. Stretched to exactly the stage box (which shares
                  the video's own aspect), so video pixels and overlay pixels
                  stay in register. */}
              <video
                ref={videoRef}
                muted
                playsInline
                className="absolute inset-0 h-full w-full"
              />
              {/* The shoe stage — the worker-driven Three.js canvas mounts
                  here, transparent, over the video. */}
              <div data-tryon-stage className="absolute inset-0" />

              {status === 'loading' && (
                <div className="absolute inset-0 grid place-items-center bg-black/40 p-6 text-center">
                  <div>
                    <p className="text-sm text-white">
                      {LOAD_PHASE_LABELS[loadPhase] ?? 'Starting…'}
                    </p>
                    {/* The tracker is the heavy download (~19 MB first
                        visit, then cached): say so where it matters, before
                        a slow connection looks like a hang. */}
                    {(loadPhase === 'foot tracker' ||
                      loadPhase === 'foot tracker (main thread)') && (
                      <p className="mx-auto mt-2 max-w-64 text-[11px] leading-relaxed text-white/60">
                        First visit downloads about 19 MB — WiFi recommended.
                      </p>
                    )}
                  </div>
                </div>
              )}

              {status === 'live' && !hasFoot && (
                <p className="absolute left-1/2 top-4 -translate-x-1/2 rounded-full bg-black/60 px-4 py-2 text-center text-xs font-medium text-white">
                  Step back so ankle and toes show, hold still
                </p>
              )}

              {/* Camera zoom, only where the hardware offers it: a slider
                  from the widest the lens goes. View-only — the tracker
                  reads the same pixels at any zoom, so the shoe stays put. */}
              {status === 'live' && zoom && (
                <div className="absolute bottom-3 left-1/2 w-64 max-w-[80%] -translate-x-1/2 rounded-full bg-black/60 px-4 py-1.5 backdrop-blur-sm">
                  <label className="flex items-center gap-2 text-white">
                    <span className="text-[11px] font-medium tabular-nums opacity-80">
                      {zoom.value.toFixed(1)}x
                    </span>
                    <input
                      type="range"
                      min={zoom.min}
                      max={zoom.max}
                      step={0.1}
                      value={zoom.value}
                      aria-label="Camera zoom"
                      className="w-full accent-white"
                      onChange={(event) => {
                        const value = event.target.valueAsNumber
                        setZoom({ ...zoom, value })
                        trackRef.current.camTrack
                          ?.applyConstraints({ advanced: [{ zoom: value }] })
                          .catch(() => {})
                      }}
                    />
                  </label>
                </div>
              )}

              {(status === 'denied' || status === 'error') && (
                <div className="absolute inset-0 grid place-items-center bg-black/60 p-6 text-center">
                  <div>
                    <p className="text-sm font-semibold text-white">
                      {status === 'denied'
                        ? 'The camera is off, so there is nothing to fit onto.'
                        : 'The foot tracker could not start on this phone.'}
                    </p>
                    <p className="mt-2 text-xs leading-relaxed text-white/70">
                      Allow the camera and try again — or get the precise,
                      fitted try-on in the app instead.
                    </p>
                    {status === 'error' && (
                      <p className="mx-auto mt-2 max-w-64 text-[11px] leading-relaxed text-white/50">
                        {errorDetail ?? 'unknown cause'}
                      </p>
                    )}
                    {status === 'error' && (
                      <button
                        type="button"
                        onClick={() => setAttempt((n) => n + 1)}
                        className="mt-3 rounded-full border border-white/40 px-5 py-2 text-xs font-semibold text-white transition-colors duration-200 hover:bg-white/10"
                      >
                        Try again
                      </button>
                    )}
                  </div>
                </div>
              )}
            </div>

            <div className="flex flex-col gap-3 border-t border-hairline-soft px-4 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-5">
              <p className="text-xs leading-relaxed text-muted">
                Beta — an approximate look, not a fitted size. The shoe follows
                your foot; the app measures it.
              </p>
              <button
                type="button"
                onClick={() => setTryOnOpen(true)}
                className="btn btn-primary w-full shrink-0 gap-2 sm:w-auto"
              >
                <Footprints size={16} strokeWidth={2} aria-hidden="true" />
                Precise fit in the app
              </button>
            </div>
          </div>
        </div>,
        document.body,
      )}

      <ConfirmDialog
        open={tryOnOpen}
        {...tryOnAppPrompt()}
        tone="primary"
        confirmHref={APP_DOWNLOAD_URL}
        onConfirm={() => setTryOnOpen(false)}
        onClose={() => setTryOnOpen(false)}
      />
    </>
  )
}
