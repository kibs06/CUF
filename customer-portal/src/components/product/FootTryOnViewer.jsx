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
 * - tracker or model fails to load → a sentence + the app door;
 * - foot leaves frame → the shoe coasts briefly, then a coaching line
 *   ("Point your camera at your feet") replaces it.
 */
export default function FootTryOnViewer({ open, url, name, onClose }) {
  const [status, setStatus] = useState('loading')
  const [hasFoot, setHasFoot] = useState(false)
  const [tryOnOpen, setTryOnOpen] = useState(false)
  const [aspect, setAspect] = useState(null)
  const closeRef = useRef(null)
  const videoRef = useRef(null)

  // Everything the frame loop touches lives in refs — the loop must never
  // re-render the page at camera rate.
  const trackRef = useRef({
    worker: null,
    workerReady: false,
    inflight: false,
    stream: null,
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
  })

  useEffect(() => {
    if (!open) return undefined
    const track = trackRef.current
    track.disposed = false
    setStatus('loading')
    setHasFoot(false)
    setAspect(null)
    track.side = null
    track.heel = null
    track.toe = null
    track.angle = null
    track.length = null
    track.lastSeen = NaN
    track.showing = false

    let cancelled = false

    const fail = () => {
      if (!cancelled) setStatus('error')
    }

    const setup = async () => {
      // The two heavy downloads happen only for a visit that taps the
      // button — same rule as the 3D viewer's dynamic import.
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
      track.stream = stream

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

      const worker = new Worker(
        new URL('../../lib/footTracker.worker.js', import.meta.url),
        { type: 'module' },
      )
      track.worker = worker
      worker.onmessage = (event) => {
        const msg = event.data
        if (msg?.type === 'ready') {
          track.workerReady = true
          return
        }
        if (msg?.type === 'error') {
          fail()
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
      worker.onerror = fail
      worker.postMessage({ type: 'init' })

      // The pump: at most one frame in flight, so a slow phone degrades to
      // fewer answers rather than a queue of stale ones.
      track.timer = window.setInterval(() => {
        const t = trackRef.current
        if (!t.workerReady || t.inflight || t.disposed) return
        const v = videoRef.current
        if (!v || v.readyState < 2) return
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

      if (!cancelled) setStatus('live')
    }

    setup().catch((err) => {
      // A denied camera is the common case, and it has its own face below.
      if (!cancelled) {
        setStatus(err?.name === 'NotAllowedError' ? 'denied' : 'error')
      }
    })

    return () => {
      cancelled = true
      track.disposed = true
      cancelAnimationFrame(track.raf)
      window.clearInterval(track.timer)
      track.worker?.terminate()
      track.worker = null
      track.workerReady = false
      track.inflight = false
      track.stream?.getTracks().forEach((t) => t.stop())
      track.stream = null
      track.three?.renderer.dispose()
      const el = track.three?.renderer.domElement
      el?.parentElement?.removeChild(el)
      track.three = null
      if (videoRef.current) videoRef.current.srcObject = null
    }
  }, [open, url])

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
                <div className="absolute inset-0 grid place-items-center bg-black/40">
                  <p className="text-sm text-white">Starting the camera…</p>
                </div>
              )}

              {status === 'live' && !hasFoot && (
                <p className="absolute left-1/2 top-4 -translate-x-1/2 rounded-full bg-black/60 px-4 py-2 text-xs font-medium text-white">
                  Point your camera at your feet
                </p>
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
