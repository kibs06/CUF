import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { Footprints, X } from 'lucide-react'

import ConfirmDialog from '../ui/ConfirmDialog.jsx'
import { APP_DOWNLOAD_URL, tryOnAppPrompt } from '../../lib/appDownload.js'
import { useScrollLock } from '../../hooks/useScrollLock.js'
import {
  HANDOFF_MS,
  blendFootLength,
  estimateFootLengthFromLeg,
  handoffPose,
  isPlausiblePlacement,
  isStagedDrawable,
  pickFoot,
  placementFromFoot,
  shouldDrawShoe,
  smoothAngle,
  smoothPoint,
  stepInGate,
} from '../../lib/footTryOn.js'
import {
  FORWARD_YAW,
  computeModelNormalization,
  normalizeForwardAxis,
  normalizeModelScale,
} from '../../lib/modelNormalization.js'
import { getZoomRange, pickWidestRearLens } from '../../lib/wideLens.js'

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
 * - foot leaves frame → the shoe coasts briefly, then returns to its
 *   staged spot for another step-in — the pose model needs ankle +
 *   toes, not a toe close-up.
 */
/**
 * One pose-message step of the staged step-in gate. The shoe waits staged
 * (today's manual placement); a found foot must dwell inside it, slowly,
 * before it counts — this replaces the old instant manual takeover.
 *
 * Returns true while the shoe stays staged (the caller keeps the stage
 * shoe drawn and skips the worn branch); false once the gate arms (the
 * caller snapshots the stage pose, starts the handoff, and falls through
 * to the worn branch untouched). All counters live on the track object so
 * dwelling accumulates across pose messages.
 */
function stepInUpdate(t, foot, vw, vh, now) {
  if (!foot) {
    // A hand-placed shoe survives empty frames.
    t.overlapFrames = 0
    t.stepPhase = 'staged'
    t.stepOverlap = 0
    t.lastStepMid = null
    return true
  }
  const place = placementFromFoot(foot, vw, vh)
  if (!place || !isPlausiblePlacement(place, vw, vh)) {
    t.overlapFrames = 0
    t.stepPhase = 'staged'
    t.stepOverlap = 0
    t.lastStepMid = null
    t.lastRawLen = place?.rawLen ?? null
    return true
  }
  t.lastRawLen = place.rawLen
  const mid = {
    x: (place.heel.x + place.toe.x) / 2,
    y: (place.heel.y + place.toe.y) / 2,
  }
  let velocity = 0
  if (t.lastStepMid && Number.isFinite(t.lastStepT) && now > t.lastStepT) {
    velocity =
      (Math.hypot(mid.x - t.lastStepMid.x, mid.y - t.lastStepMid.y) /
        (now - t.lastStepT)) *
      1000
  }
  t.lastStepMid = mid
  t.lastStepT = now
  const gate = stepInGate({
    footHeel: place.heel,
    footToe: place.toe,
    stageHeel: t.heel,
    stageToe: t.toe,
    footVelocityPxPerSec: velocity,
    overlapFrames: t.overlapFrames ?? 0,
  })
  t.overlapFrames = gate.overlapFrames
  t.stepOverlap = gate.overlapRatio
  t.stepPhase = gate.overlapRatio > 0 ? 'arming' : 'staged'
  return !gate.armed
}

/** What the loading overlay names while the try-on starts up, in order. */
const LOAD_PHASE_LABELS = {
  starting: 'Starting…',
  '3d library': 'Loading the 3D engine…',
  camera: 'Starting the camera…',
  'shoe model': 'Loading the shoe…',
  'foot tracker': 'Loading the foot tracker…',
  'foot tracker (main thread)': 'Loading the foot tracker…',
}

export default function FootTryOnViewer({ open, url, name, onClose, forwardAxis = '+z', defaultScale = 1 }) {
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
  // Rear cameras on this phone, once permission reveals their labels —
  // lets a tele-default phone switch to its ultrawide (real magnification
  // change; the zoom slider cannot go wider than its lens).
  const [rearCams, setRearCams] = useState([])
  const [camIdx, setCamIdx] = useState(0)
  // Manual placement: the pose model needs body context a foot close-up
  // never gives it, so the shoe would stay invisible forever. Tapping
  // "Place it manually" drops the shoe mid-frame and dragging moves it;
  // auto-tracking takes over the moment a real foot is found.
  const [manual, setManual] = useState(false)
  // User size trim: the pose axis under-reads true foot length and every
  // .glb is authored at a different scale, so the shoe gets − / + buttons
  // while live. Multiplies the tracked length; manual drags keep it too.
  const [shoeScale, setShoeScale] = useState(1)
  // Phase 1 debug overlay: `?footdebug=1` or `localStorage footdebug=1`.
  // Off by default — adds nothing (no canvas, no per-frame work) for
  // normal users. When on, landmarks/axes/readout draw over the video and
  // a button downloads recent landmark frames (numbers only, no images).
  const [debug] = useState(() => {
    try {
      if (new URLSearchParams(window.location.search).get('footdebug') === '1') return true
      return window.localStorage?.getItem('footdebug') === '1'
    } catch {
      return false
    }
  })
  const closeRef = useRef(null)
  const videoRef = useRef(null)
  const debugCanvasRef = useRef(null)

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
    userScale: 1,
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
    setRearCams([])
    setCamIdx(0)
    setManual(false)
    setShoeScale(1)
    track.manual = false
    track.userScale = 1
    track.placeManual = null
    track.nudgeManual = null
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
    track.stepPhase = null
    track.overlapFrames = 0
    track.stepOverlap = null
    track.handoff = null
    track.lastStepMid = null
    track.lastStepT = 0

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

      // A previous lens switch (or the first open) decides the constraint:
      // an exact deviceId where the user already picked a lens, otherwise
      // the rear camera. Resolution stays landscape 720p either way.
      const baseVideo = {
        facingMode: 'environment',
        width: { ideal: 1280 },
        height: { ideal: 720 },
      }
      const openStream = (video) =>
        navigator.mediaDevices.getUserMedia({ video, audio: false })
      let stream
      if (track.wantDeviceId) {
        try {
          stream = await openStream({
            deviceId: { exact: track.wantDeviceId },
            width: { ideal: 1280 },
            height: { ideal: 720 },
          })
        } catch {
          stream = await openStream(baseVideo)
        }
      } else {
        stream = await openStream(baseVideo)
      }
      if (cancelled) {
        stream.getTracks().forEach((t) => t.stop())
        return
      }
      track.phase = 'camera'
      if (!cancelled) setLoadPhase('camera')
      track.stream = stream
      track.camTrack = stream.getVideoTracks()[0] ?? null

      // Magnification is a lens choice, not a zoom setting: several phones
      // default to the tele lens, so min-zoom is still tight. Once
      // permission reveals labels, prefer the ultrawide automatically on
      // first open — and remember every rear lens for the switch button.
      try {
        const devices = await navigator.mediaDevices.enumerateDevices()
        const videos = devices.filter(
          (d) => d.kind === 'videoinput' && d.deviceId,
        )
        const rear = videos.filter(
          (d) => !/front|user|selfie|internal/i.test(d.label ?? ''),
        )
        const list = (rear.length ? rear : videos).map((d) => ({
          deviceId: d.deviceId,
          label: d.label || 'Camera',
        }))
        if (!cancelled && list.length) {
          setRearCams(list)
          const currentId =
            track.camTrack?.getSettings?.().deviceId ?? null
          if (!track.wantDeviceId) {
            const wideId = pickWidestRearLens(devices)
            const ultra = wideId ? list.find((d) => d.deviceId === wideId) : undefined
            if (ultra && ultra.deviceId !== currentId) {
              try {
                const wide = await openStream({
                  deviceId: { exact: ultra.deviceId },
                  width: { ideal: 1280 },
                  height: { ideal: 720 },
                })
                if (cancelled) {
                  wide.getTracks().forEach((t) => t.stop())
                } else {
                  stream.getTracks().forEach((t) => t.stop())
                  stream = wide
                  track.stream = wide
                  track.camTrack = wide.getVideoTracks()[0] ?? null
                  track.wantDeviceId = ultra.deviceId
                }
              } catch {
                // Ultrawide refused — stay on the default lens.
              }
            }
          }
          if (!cancelled) {
            const activeId =
              track.camTrack?.getSettings?.().deviceId ??
              track.wantDeviceId ??
              currentId
            const at = Math.max(
              0,
              list.findIndex((d) => d.deviceId === activeId),
            )
            setCamIdx(at)
          }
        }
      } catch {
        // Labels unavailable — single-lens path below still works.
      }

      // Widest view first, where the hardware allows it. Several phone
      // cameras open part-way into their zoom range, which reads as a
      // broken zoomed-in feed next to the camera app.
      try {
        const range = getZoomRange(track.camTrack)
        if (range && range.max > range.min) {
          await track.camTrack
            ?.applyConstraints({ advanced: [{ zoom: range.min }] })
            .catch(() => {})
          if (!cancelled) setZoom({ value: range.min, min: range.min, max: range.max })
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
      // Sole-side-up fix: glTF is Y-up with the sole facing −Y, but the
      // flat group (rotation.x = −π/2) maps model +Y to −Z — away from the
      // camera at +Z — so the shoe renders upside down. A half-turn about
      // the toe axis (+Z, untouched, so heel→toe yaw math is unchanged)
      // puts the upper toward the camera before measuring normalizes it.
      model.rotation.z = Math.PI
      // Per-model forward axis (Phase 2): the yaw goes on BEFORE measuring,
      // so the measured box is already post-yaw and the unit contract
      // (heel at origin, toe at +1) holds however the asset was authored.
      // Unknown axes fall back to +z — byte-identical to the legacy path.
      const normAxis = normalizeForwardAxis(forwardAxis)
      const normScale = normalizeModelScale(defaultScale)
      model.rotation.y = FORWARD_YAW[normAxis]
      model.updateMatrixWorld(true)
      track.modelAxis = normAxis
      const box = new THREE.Box3().setFromObject(model)
      const size = new THREE.Vector3()
      const center = new THREE.Vector3()
      box.getSize(size)
      box.getCenter(center)
      const norm = computeModelNormalization(
        {
          size: { x: size.x, y: size.y, z: size.z },
          center: { x: center.x, y: center.y, z: center.z },
          min: { x: box.min.x, y: box.min.y, z: box.min.z },
        },
        normAxis,
        normScale,
      )
      if (!norm) {
        fail()
        return
      }
      const inner = new THREE.Group()
      inner.add(model)
      inner.scale.set(norm.uniformScale, norm.uniformScale, norm.uniformScale)
      inner.position.set(norm.offset.x, norm.offset.y, norm.offset.z)
      flatGroup.add(inner)

      track.three = { THREE, renderer, scene, camera, yawGroup }

      // Manual placement, defined once the stage exists: center-frame at
      // half the short edge, toe pointing up-screen, then draggable.
      const drawManual = () => {
        const t = trackRef.current
        if (!t.heel || !t.toe || t.angle === null || !t.length) return
        const dx = t.toe.x - t.heel.x
        const dy = t.toe.y - t.heel.y
        yawGroup.position.set(t.heel.x - vw / 2, vh / 2 - t.heel.y, 0)
        yawGroup.rotation.z = Math.atan2(-dx, -dy)
        const fitted = t.length * (t.userScale ?? 1)
        yawGroup.scale.set(fitted, fitted, fitted)
        yawGroup.visible = true
      }
      track.placeManual = () => {
        const t = trackRef.current
        const len = Math.min(vw, vh) * 0.55
        const cx = vw / 2
        const cy = vh * 0.55
        t.heel = { x: cx, y: cy + len / 2 }
        t.toe = { x: cx, y: cy - len / 2 }
        t.angle = -Math.PI / 2
        t.length = len
        t.lastSeen = NaN
        t.side = null
        t.showing = true
        t.manual = true
        drawManual()
        if (!cancelled) {
          setManual(true)
          setHasFoot(true)
        }
      }
      track.nudgeManual = (dxPx, dyPx) => {
        const t = trackRef.current
        if (!t.manual || !t.heel || !t.toe) return
        t.heel = { x: t.heel.x + dxPx, y: t.heel.y + dyPx }
        t.toe = { x: t.toe.x + dxPx, y: t.toe.y + dyPx }
        drawManual()
      }

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
        // Auto-stage on the first answer: the shoe waits center-frame from
        // the start (draggable as before) instead of an empty camera.
        if (!t.stepPhase && !t.manual && t.placeManual) {
          t.placeManual()
          t.stepPhase = 'staged'
          t.overlapFrames = 0
          t.stepOverlap = null
          t.handoff = null
          t.lastStepMid = null
        }
        const foot = pickFoot(msg.feet ?? [], t.side)
        const now = performance.now()
        // Staged step-in gate (replaces the old instant manual takeover):
        // while the shoe waits, a found foot must dwell inside it before
        // it counts. A hold skips the worn branch below — the stage shoe
        // stays drawn and the shared coast/debug code handles the rest.
        let tracked = foot
        let stagedHold = false
        if (t.manual && !t.handoff) {
          stagedHold = stepInUpdate(t, foot, vw, vh, now)
          if (!stagedHold) {
            // Gate armed: snapshot the stage pose for the handoff lerp,
            // then fall through to the worn branch untouched.
            t.handoff = {
              from: {
                heel: { ...t.heel },
                toe: { ...t.toe },
                angle: t.angle,
                length: t.length,
              },
              startMs: now,
            }
            t.stepPhase = 'handoff'
            t.manual = false
            if (!cancelled) setManual(false)
          } else {
            tracked = null
            t.lastBlend = null
          }
        }
        // A staged hold skips the worn branch: the stage shoe stays drawn.
        if (foot && !stagedHold) {
          const place = placementFromFoot(foot, vw, vh)
          t.lastRawLen = place?.rawLen ?? null
          // Collapsed heel+toe axes (the tiny-shoe-on-the-shin report) are
          // rejected here: the shoe coasts/hides instead of jumping up
          // the leg at doll size.
          if (!place || !isPlausiblePlacement(place, vw, vh)) {
            tracked = null
          } else {
            t.side = foot.side
            t.heel = smoothPoint(t.heel, place.heel)
            t.toe = smoothPoint(t.toe, place.toe)
            t.angle = smoothAngle(t.angle, place.angleRad)
            // Phase 3: independent leg prior blended with the axis
            // length. With no visible knee the blend returns the axis
            // unchanged, so those frames render exactly as before.
            const knee = (msg.knees ?? {})[foot.side] ?? null
            const prior = estimateFootLengthFromLeg({
              knee,
              ankle: foot.ankle,
              videoW: vw,
              videoH: vh,
            })
            const blended = blendFootLength({
              axisLengthPx: place.lengthPx,
              axisConfidence: foot.score ?? 0.5,
              legPriorPx: prior?.lengthPx ?? null,
              legConfidence: prior?.confidence ?? 0,
            })
            t.lastBlend = blended
            const targetLen = blended?.lengthPx ?? place.lengthPx
            t.length =
              t.length === null
                ? targetLen
                : t.length + 0.4 * (targetLen - t.length)
            t.lastSeen = now
          }
          if (!tracked) t.lastBlend = null
        }
        // A staged shoe waits visibly: it has no lastSeen yet, so the
        // coast check alone would hide the stage on the first empty pose
        // message. Worn follows tracking exactly as before.
        const draw = shouldDrawShoe({
          seenNow: Boolean(tracked) || isStagedDrawable(t),
          lastSeenMs: t.lastSeen,
          nowMs: now,
        })
        if (draw !== t.showing) {
          t.showing = draw
          if (!cancelled) setHasFoot(draw)
        }
        // Long loss after wearing: put the shoe back on stage for another
        // step-in instead of leaving an empty camera. Coast gaps still
        // draw through above; this only fires past COAST_MS.
        if (!draw && !t.manual && !t.handoff && t.stepPhase === 'worn' && t.placeManual) {
          t.placeManual()
          t.stepPhase = 'staged'
          t.overlapFrames = 0
          t.stepOverlap = null
          t.handoff = null
          t.lastStepMid = null
        }
        if (draw && t.heel && t.toe && t.angle !== null && t.length) {
          let heel = t.heel
          let toe = t.toe
          let angle = t.angle
          let length = t.length
          // Handoff: ease the drawn shoe from the snapped stage pose to
          // the live tracked pose over HANDOFF_MS so attaching never pops.
          if (t.handoff) {
            const k = (now - t.handoff.startMs) / HANDOFF_MS
            if (k >= 1) {
              t.handoff = null
              t.stepPhase = 'worn'
            } else {
              ;({ heel, toe, angle, length } = handoffPose({
                from: t.handoff.from,
                to: { heel, toe, angle, length },
                t: k,
              }))
            }
          }
          // Screen space is y-down; three is y-up. The toe direction
          // (dx, dy) on screen is (dx, −dy) in the scene, and the yaw that
          // takes the model's +Y-projected toe onto it is atan2(−dx, −dy).
          const dx = toe.x - heel.x
          const dy = toe.y - heel.y
          yawGroup.position.set(heel.x - vw / 2, vh / 2 - heel.y, 0)
          yawGroup.rotation.z = Math.atan2(-dx, -dy)
          const fitted = length * (t.userScale ?? 1)
          yawGroup.scale.set(fitted, fitted, fitted)
          yawGroup.visible = true
        } else {
          yawGroup.visible = false
        }
        // Phase 1 debug record: what the overlay + fixtures read. Written
        // every pose message; the overlay draws it in RAF, never via state.
        if (debug) {
          t.lastDebug = {
            feet: (msg.feet ?? []).map((f) => ({
              side: f.side,
              heel: f.heel ? { ...f.heel } : null,
              toe: f.toe ? { ...f.toe } : null,
              ankle: f.ankle ? { ...f.ankle } : null,
            })),
            heel: t.heel ? { ...t.heel } : null,
            toe: t.toe ? { ...t.toe } : null,
            length: t.length,
            rawLen: t.lastRawLen ?? null,
            blendSource: t.lastBlend?.source ?? 'axis',
            disagree: t.lastBlend?.disagree ?? false,
            userScale: t.userScale ?? 1,
            plausible: Boolean(tracked),
            plausibleReason: foot ? (tracked ? null : t.manual ? 'staged' : 'rejected') : 'no-foot',
            stepPhase: t.stepPhase ?? null,
            stepOverlap: t.stepOverlap ?? null,
            showing: t.showing,
            side: t.side,
            modelAxis: t.modelAxis ?? '+z',
          }
          t.frames = t.frames ?? []
          t.frames.push({
            t: Math.round(now),
            vw,
            vh,
            feet: t.lastDebug.feet,
            lengthPx: t.length,
            rawLen: t.lastRawLen ?? null,
            blendSource: t.lastBlend?.source ?? 'axis',
            disagree: t.lastBlend?.disagree ?? false,
            stepPhase: t.stepPhase ?? null,
            stepOverlap: t.stepOverlap ?? null,
          })
          if (t.frames.length > 300) t.frames.splice(0, t.frames.length - 300)
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
            const { feet, knees } = t.mainTracker.detect(v, performance.now())
            if (!t.disposed) onWorkerMessage({ data: { type: 'pose', feet, knees } })
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
        if (debug) drawDebugOverlay()
      }
      // Debug overlay: 2D canvas over the video, drawn in the same RAF so
      // it never re-renders React at camera rate. Reads `track.lastDebug`
      // written by the pose-message handler below.
      const drawDebugOverlay = () => {
        const canvas = debugCanvasRef.current
        const t = trackRef.current
        const d = t.lastDebug
        if (!canvas || !d) return
        if (canvas.width !== vw || canvas.height !== vh) {
          canvas.width = vw
          canvas.height = vh
        }
        const ctx = canvas.getContext('2d')
        if (!ctx) return
        ctx.clearRect(0, 0, vw, vh)
        // FPS (EMA over RAF ticks).
        const now = performance.now()
        t.fps = t.fps == null ? 60 : t.fps + 0.05 * (1000 / Math.max(1, now - (t.lastFpsT ?? now)) - t.fps)
        t.lastFpsT = now
        const dot = (p, color, label) => {
          if (!p) return
          ctx.fillStyle = color
          ctx.beginPath()
          ctx.arc(p.x, p.y, Math.max(4, vw * 0.008), 0, Math.PI * 2)
          ctx.fill()
          ctx.fillStyle = '#fff'
          ctx.font = `${Math.max(12, vw * 0.02)}px monospace`
          ctx.fillText(label, p.x + 10, p.y - 8)
        }
        // Raw landmarks (UV → px) with visibility scores.
        for (const f of d.feet ?? []) {
          for (const [key, color] of [['heel', '#4ade80'], ['toe', '#f87171'], ['ankle', '#60a5fa']]) {
            const p = f[key]
            if (p && Number.isFinite(p.x) && Number.isFinite(p.y) && p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1) {
              dot({ x: p.x * vw, y: p.y * vh }, color, `${f.side[0]}:${key} ${(p.score ?? 0).toFixed(2)}`)
            }
          }
        }
        // Extended (smoothed) axis the shoe is drawn on.
        if (d.heel && d.toe) {
          ctx.strokeStyle = '#facc15'
          ctx.lineWidth = Math.max(2, vw * 0.004)
          ctx.beginPath()
          ctx.moveTo(d.heel.x, d.heel.y)
          ctx.lineTo(d.toe.x, d.toe.y)
          ctx.stroke()
          // Model toe-direction arrow (extends past the toe).
          const dx = d.toe.x - d.heel.x
          const dy = d.toe.y - d.heel.y
          const len = Math.hypot(dx, dy) || 1
          const ax = d.toe.x + (dx / len) * len * 0.25
          const ay = d.toe.y + (dy / len) * len * 0.25
          ctx.strokeStyle = '#22d3ee'
          ctx.beginPath()
          ctx.moveTo(d.toe.x, d.toe.y)
          ctx.lineTo(ax, ay)
          ctx.stroke()
        }
        const lines = [
          `len=${d.length == null ? '—' : Math.round(d.length)}px raw=${d.rawLen == null ? '—' : Math.round(d.rawLen)}px x${(d.userScale ?? 1).toFixed(2)} src=${d.blendSource ?? 'axis'}${d.disagree ? ' DISAGREE' : ''}`,
          `plausible=${d.plausible ? 'yes' : 'NO (' + (d.plausibleReason ?? '?') + ')'} showing=${d.showing ? 'yes' : 'no'} side=${d.side ?? '—'} step=${d.stepPhase ?? '—'}${d.stepOverlap != null ? ' ' + Math.round(d.stepOverlap * 100) + '%' : ''}`,
          `axis=${d.modelAxis ?? '+z'} fps=${Math.round(t.fps ?? 0)} frames=${(t.frames ?? []).length}`,
        ]
        ctx.fillStyle = 'rgba(0,0,0,0.65)'
        const fs = Math.max(12, vw * 0.02)
        ctx.font = `${fs}px monospace`
        lines.forEach((line, i) => {
          const y = fs * 1.4 * (i + 1) + 6
          const w = ctx.measureText(line).width
          ctx.fillRect(6, y - fs, w + 12, fs + 6)
          ctx.fillStyle = '#fff'
          ctx.fillText(line, 12, y)
          ctx.fillStyle = 'rgba(0,0,0,0.65)'
        })
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

  // Phase 1: downloads recent landmark frames (numbers only, no images)
  // so real tracker output becomes unit-test fixtures.
  const saveDebugFrames = () => {
    const frames = trackRef.current.frames ?? []
    const blob = new Blob(
      [JSON.stringify({ exportedAt: new Date().toISOString(), product: name ?? null, frames }, null, 2)],
      { type: 'application/json' },
    )
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `foot-frames-${Date.now()}.json`
    a.click()
    window.setTimeout(() => URL.revokeObjectURL(a.href), 5000)
  }

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
              {debug && (
                <canvas
                  ref={debugCanvasRef}
                  aria-hidden="true"
                  className="pointer-events-none absolute inset-0 h-full w-full"
                />
              )}
              {/* The shoe stage — the worker-driven Three.js canvas mounts
                  here, transparent, over the video. In manual mode it also
                  takes drags: the shoe follows the finger while auto-track
                  has nothing. */}
              <div
                data-tryon-stage
                className="absolute inset-0"
                style={manual ? { touchAction: 'none' } : undefined}
                onPointerDown={(event) => {
                  const t = trackRef.current
                  if (!manual || !t.manual) return
                  t.dragFrom = { x: event.clientX, y: event.clientY }
                  event.currentTarget.setPointerCapture?.(event.pointerId)
                }}
                onPointerMove={(event) => {
                  const t = trackRef.current
                  if (!manual || !t.manual || !t.dragFrom) return
                  const rect = event.currentTarget.getBoundingClientRect()
                  const v = videoRef.current
                  const scale = v?.videoWidth
                    ? v.videoWidth / Math.max(1, rect.width)
                    : 1
                  const dx =
                    (event.clientX - t.dragFrom.x) * scale
                  const dy =
                    (event.clientY - t.dragFrom.y) * scale
                  t.dragFrom = { x: event.clientX, y: event.clientY }
                  t.nudgeManual?.(dx, dy)
                }}
                onPointerUp={() => {
                  trackRef.current.dragFrom = null
                }}
                onPointerCancel={() => {
                  trackRef.current.dragFrom = null
                }}
              />


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
                <div className="absolute left-1/2 top-4 flex -translate-x-1/2 flex-col items-center gap-2">
                  <p className="rounded-full bg-black/60 px-4 py-2 text-center text-xs font-medium text-white">
                    Step back so ankle and toes show, hold still
                  </p>
                  <button
                    type="button"
                    onClick={() => trackRef.current.placeManual?.()}
                    className="rounded-full border border-white/50 bg-black/60 px-4 py-1.5 text-xs font-semibold text-white backdrop-blur-sm transition-colors duration-200 hover:bg-white/20"
                  >
                    Place it manually
                  </button>
                </div>
              )}
              {status === 'live' && manual && hasFoot && (
                <p className="absolute left-1/2 top-4 -translate-x-1/2 rounded-full bg-black/60 px-4 py-2 text-center text-xs font-medium text-white">
                  Drag to move — step your foot in to wear it
                </p>
              )}
              {/* Shoe size trim: pose axis under-reads true foot length and
                  .glb scales vary, so the wearer trims it live. Applies to
                  both auto-track and manual drags via track.userScale. */}
              {debug && status === 'live' && (
                <button
                  type="button"
                  onClick={saveDebugFrames}
                  className="absolute bottom-3 right-3 rounded-full bg-black/60 px-4 py-1.5 text-xs font-semibold text-white backdrop-blur-sm transition-colors duration-200 hover:bg-white/20"
                >
                  Save frames
                </button>
              )}
              {status === 'live' && hasFoot && (
                <div className="absolute right-3 top-1/2 flex -translate-y-1/2 flex-col items-center gap-1 rounded-full bg-black/60 px-1.5 py-2 backdrop-blur-sm">
                  <button
                    type="button"
                    aria-label="Make the shoe bigger"
                    onClick={() => {
                      setShoeScale((s) => {
                        const next = Math.min(1.6, Math.round((s + 0.05) * 100) / 100)
                        const t = trackRef.current
                        t.userScale = next
                        const g = t.three?.yawGroup
                        if (g && t.length) {
                          const fitted = t.length * next
                          g.scale.set(fitted, fitted, fitted)
                        }
                        return next
                      })
                    }}
                    className="inline-flex h-7 w-7 items-center justify-center rounded-full text-base font-semibold text-white transition-colors duration-200 hover:bg-white/20"
                  >
                    +
                  </button>
                  <span className="text-[10px] font-medium tabular-nums text-white/80">
                    {Math.round(shoeScale * 100)}%
                  </span>
                  <button
                    type="button"
                    aria-label="Make the shoe smaller"
                    onClick={() => {
                      setShoeScale((s) => {
                        const next = Math.max(0.7, Math.round((s - 0.05) * 100) / 100)
                        const t = trackRef.current
                        t.userScale = next
                        const g = t.three?.yawGroup
                        if (g && t.length) {
                          const fitted = t.length * next
                          g.scale.set(fitted, fitted, fitted)
                        }
                        return next
                      })
                    }}
                    className="inline-flex h-7 w-7 items-center justify-center rounded-full text-base font-semibold text-white transition-colors duration-200 hover:bg-white/20"
                  >
                    −
                  </button>
                </div>
              )}

              {/* Camera zoom, only where the hardware offers it: a slider
                  from the widest the lens goes. View-only — the tracker
                  reads the same pixels at any zoom, so the shoe stays put.
                  The lens button alongside it is the real de-magnifier:
                  it cycles the rear lenses (ultrawide first) where the
                  phone has more than one. */}
              {(status === 'live' || status === 'loading') &&
                (zoom || rearCams.length > 1) && (
                <div className="absolute bottom-3 left-1/2 flex w-64 max-w-[80%] -translate-x-1/2 items-center gap-2 rounded-full bg-black/60 px-4 py-1.5 backdrop-blur-sm">
                  {rearCams.length > 1 && (
                    <button
                      type="button"
                      aria-label="Switch rear camera lens"
                      title={rearCams[camIdx]?.label ?? 'Switch lens'}
                      onClick={() => {
                        const next = (camIdx + 1) % rearCams.length
                        trackRef.current.wantDeviceId =
                          rearCams[next].deviceId
                        setCamIdx(next)
                        setAttempt((n) => n + 1)
                      }}
                      className="shrink-0 rounded-full border border-white/40 px-2.5 py-1 text-[11px] font-semibold text-white transition-colors duration-200 hover:bg-white/10"
                    >
                      {camIdx + 1}/{rearCams.length}
                    </button>
                  )}
                  {zoom ? (
                    <label className="flex flex-1 items-center gap-2 text-white">
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
                  ) : (
                    <span className="max-w-full truncate text-[11px] text-white/70">
                      {rearCams[camIdx]?.label ?? 'Rear camera'}
                    </span>
                  )}
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
