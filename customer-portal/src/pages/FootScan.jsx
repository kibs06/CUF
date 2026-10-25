import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { ArrowLeft, Camera, Loader2, RotateCcw } from 'lucide-react'

import { useAuth } from '../hooks/useAuth.jsx'
import { supabase } from '../lib/supabase.js'
import {
  CAPTURE_INTERVAL_MS,
  SWEEP_DURATION_MS,
  TARGET_FRAME_COUNT,
  angleCoverageDeg,
  compassHeadingFrom,
  createOrbitTracker,
  isFrameUsable,
  isSweepUsable,
  lumaStats,
  sweepFailureMessage,
} from '../lib/footScanCapture.js'
import { getZoomRange, openWidestLensStream, pinMinZoom } from '../lib/wideLens.js'
import {
  bytesProgress,
  createFootScanJob,
  failFootScanJob,
  finishFootScanUpload,
  listUploadedFrames,
  retryable,
  setFootScanUploading,
  uploadedFrameSizes,
  uploadScanFrame,
} from '../lib/footScanJobs.js'

/**
 * 360° foot scan — the measurement-first capture flow.
 *
 * Guides the customer once around their foot while the page
 * auto-captures angle-tagged frames, gates the sweep on coverage, and
 * uploads it as a `foot_scan_jobs` row for cloud reconstruction. The
 * mesh and the numbers appear on the results page (`/foot-scan/:jobId`);
 * this page only ever promises the capture, never the measurement.
 *
 * Own-build, no vendor: frames stay in our Supabase project, and the
 * angle tag is a coverage receipt — the reconstruction worker re-solves
 * real poses from image overlap.
 */

const PHASES = {
  intro: 'intro',
  camera: 'camera',
  capturing: 'capturing',
  reviewing: 'reviewing',
  uploading: 'uploading',
  queued: 'queued',
}

/** Downscale a video frame to the upload budget, return JPEG blob + thumbnail luma. */
async function snapshotFrame(video) {
  const vw = video.videoWidth
  const vh = video.videoHeight
  if (!vw || !vh) return null
  const scale = Math.min(1, 1280 / Math.max(vw, vh))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(vw * scale)
  canvas.height = Math.round(vh * scale)
  const ctx = canvas.getContext('2d')
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
  const thumb = document.createElement('canvas')
  thumb.width = 48
  thumb.height = Math.max(1, Math.round((48 * canvas.height) / canvas.width))
  const tctx = thumb.getContext('2d')
  tctx.drawImage(canvas, 0, 0, thumb.width, thumb.height)
  const pixels = tctx.getImageData(0, 0, thumb.width, thumb.height).data
  const { brightness, sharpness } = lumaStats(pixels)
  if (!isFrameUsable({ sharpness, brightness })) return { skipped: true }
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.82))
  return blob ? { blob } : { skipped: true }
}

/**
 * Short lens names for the switcher. The 1x guess is the plain rear
 * lens — phone labels rarely say "main", so the non-ultra, non-tele
 * rear lens is it. Duplicates are numbered at list build time.
 */
function lensDisplayName(label, total) {
  const l = label ?? ''
  if (/ultra|0\.5|0\.6|wide[\s_-]*angle/i.test(l)) return 'Ultra-wide'
  if (/tele|periscope|[2-9]\s?[x×]/i.test(l)) return 'Tele'
  return total > 1 ? '1×' : 'Rear camera'
}

export default function FootScan() {
  const { session } = useAuth()
  const navigate = useNavigate()
  const userId = session?.user?.id ?? null

  const [phase, setPhase] = useState(PHASES.intro)
  const [error, setError] = useState(null)
  const [progress, setProgress] = useState(0)
  const [frameCount, setFrameCount] = useState(0)
  const [coverage, setCoverage] = useState(0)
  const [compassTracked, setCompassTracked] = useState(false)
  const [uploadProgress, setUploadProgress] = useState(0)
  const [queuedJobId, setQueuedJobId] = useState(null)
  // User-adjustable zoom for the live preview. Null range = the hardware
  // reports no zoom control, so no slider is shown. Set when the camera
  // starts, cleared when it stops.
  const [zoomRange, setZoomRange] = useState(null)
  const [zoom, setZoom] = useState(null)
  // Rear lens list for the switcher + which one is live. Empty = the
  // phone exposed one lens (or labels unreadable), so no switcher.
  const [rearCams, setRearCams] = useState([])
  const [camIdx, setCamIdx] = useState(0)

  const videoRef = useRef(null)
  const streamRef = useRef(null)
  const framesRef = useRef([])
  const timerRef = useRef(null)
  const startRef = useRef(0)
  // Latest compass heading (degrees) or null — written by the
  // deviceorientation listener, read by the capture tick. A ref, not
  // state: it updates ~60 Hz and must never re-render the page.
  const headingRef = useRef(null)
  const trackerRef = useRef(null)
  // The in-progress upload's job row — retained across interruptions so
  // a retry resumes the same job instead of starting a second one.
  const uploadJobRef = useRef(null)

  const stopCamera = useCallback(() => {
    window.clearInterval(timerRef.current)
    timerRef.current = null
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
    setZoomRange(null)
    setZoom(null)
    setRearCams([])
    setCamIdx(0)
  }, [])

  useEffect(() => stopCamera, [stopCamera])

  // Compass feed for the orbit tracker: absolute-frame alpha (Android)
  // or the iOS compass heading. Relative-only alphas read null and the
  // tracker falls back to time tags — same behavior as before.
  useEffect(() => {
    if (typeof window === 'undefined' || !('DeviceOrientationEvent' in window)) {
      return undefined
    }
    const onOrientation = (event) => {
      const heading = compassHeadingFrom({
        webkitCompassHeading: event.webkitCompassHeading,
        alpha: event.alpha,
        absolute: event.absolute,
      })
      if (heading !== null) {
        headingRef.current = heading
        setCompassTracked(true)
      }
    }
    window.addEventListener('deviceorientationabsolute', onOrientation)
    window.addEventListener('deviceorientation', onOrientation)
    return () => {
      window.removeEventListener('deviceorientationabsolute', onOrientation)
      window.removeEventListener('deviceorientation', onOrientation)
    }
  }, [])

  const startCamera = useCallback(async () => {
    setError(null)
    setPhase(PHASES.camera)
    try {
      const openStream = (video) =>
        navigator.mediaDevices.getUserMedia({ video, audio: false })
      let stream = await openStream({
        facingMode: 'environment',
        width: { ideal: 1280 },
        height: { ideal: 720 },
      })
      // Widest lens + min zoom via the shared helper both camera
      // surfaces use. Best-effort: a refusal keeps the base stream,
      // never a black screen.
      try {
        stream = await openWidestLensStream({
          open: openStream,
          enumerate: () => navigator.mediaDevices.enumerateDevices(),
          stream,
          width: 1280,
          height: 720,
        })
      } catch {
        // Requested lens refused - stay on the default lens.
      }
      await pinMinZoom(stream.getVideoTracks()[0])
      // Expose the hardware zoom to the user: start wide (min), let
      // them push toward 1x if the foot is too small in frame.
      const track = stream.getVideoTracks()[0] ?? null
      const range = getZoomRange(track)
      if (range) {
        setZoomRange(range)
        let current = range.min
        try {
          const reported = track.getSettings?.()?.zoom
          if (Number.isFinite(reported)) current = reported
        } catch {
          // Unreadable setting — the pinned min is the truth.
        }
        setZoom(current)
      } else {
        setZoomRange(null)
        setZoom(null)
      }
      // Rear lens list for the switcher: permission is granted by now,
      // so labels are visible. Failures hide the switcher, never the feed.
      try {
        const devices = await navigator.mediaDevices.enumerateDevices()
        const videos = devices.filter(
          (d) => d.kind === 'videoinput' && d.deviceId,
        )
        const rear = videos.filter(
          (d) => !/front|user|selfie|internal/i.test(d.label ?? ''),
        )
        const pool = rear.length ? rear : videos
        const counts = {}
        const list = pool.map((d) => {
          let name = lensDisplayName(d.label, pool.length)
          if (counts[name]) {
            counts[name] += 1
            name = `${name} ${counts[name]}`
          } else {
            counts[name] = 1
          }
          return { deviceId: d.deviceId, label: d.label || 'Camera', name }
        })
        if (list.length) {
          setRearCams(list)
          const currentId = track.getSettings?.()?.deviceId ?? null
          setCamIdx(Math.max(0, list.findIndex((d) => d.deviceId === currentId)))
        }
      } catch {
        // Labels unavailable — single-lens path still works.
      }
      streamRef.current = stream
      // Wait a frame so the ref is mounted before assigning.
      requestAnimationFrame(() => {
        if (videoRef.current) videoRef.current.srcObject = stream
      })
    } catch {
      setError('Camera unavailable — allow camera access and try again.')
      setZoomRange(null)
      setZoom(null)
      setRearCams([])
      setCamIdx(0)
      setPhase(PHASES.intro)
    }
  }, [])

  // User-driven zoom for the live preview only — the sweep keeps
  // whatever zoom is set when it starts. Best-effort: a refusal keeps
  // the previous zoom, never a black screen.
  const applyZoom = useCallback(async (value) => {
    if (!zoomRange) return
    const clamped = Math.min(zoomRange.max, Math.max(zoomRange.min, value))
    const track = streamRef.current?.getVideoTracks()[0] ?? null
    if (!track) return
    try {
      await track.applyConstraints({ advanced: [{ zoom: clamped }] })
      setZoom(clamped)
    } catch {
      // Hardware refused — stay where we are.
    }
  }, [zoomRange])

  // Lens switcher — the real de-magnifier. The zoom slider only moves
  // within one physical lens, so a tele default can never reach the
  // main-camera 1x view; switching the lens can. Best-effort with
  // fallback to the current lens, and the previous zoom carries over
  // clamped into the new lens's range. Preview only — the sweep keeps
  // whatever lens is live when it starts.
  const switchLens = useCallback(async (index) => {
    const next = rearCams[index]
    if (!next || index === camIdx) return
    setError(null)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          deviceId: { exact: next.deviceId },
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
        audio: false,
      })
      const old = streamRef.current
      streamRef.current = stream
      if (videoRef.current) videoRef.current.srcObject = stream
      old?.getTracks().forEach((t) => t.stop())
      const track = stream.getVideoTracks()[0] ?? null
      const range = getZoomRange(track)
      if (range) {
        setZoomRange(range)
        const target = zoom != null
          ? Math.min(range.max, Math.max(range.min, zoom))
          : range.min
        try {
          await track.applyConstraints({ advanced: [{ zoom: target }] })
          setZoom(target)
        } catch {
          setZoom(range.min)
        }
      } else {
        setZoomRange(null)
        setZoom(null)
      }
      setCamIdx(index)
    } catch {
      setError('That lens refused — staying on the current one.')
    }
  }, [rearCams, camIdx, zoom])

  const beginSweep = useCallback(async () => {
    framesRef.current = []
    // A new sweep is a new job: never pour fresh frames into the old row.
    uploadJobRef.current = null
    setFrameCount(0)
    setCoverage(0)
    setProgress(0)
    setError(null)
    // iOS gates the compass behind a permission prompt, and it must be
    // requested from a user gesture — this tap is that gesture. Denial
    // is not an error: the tracker falls back to time tags.
    try {
      const requestPermission = DeviceOrientationEvent?.requestPermission
      if (typeof requestPermission === 'function') {
        await requestPermission.call(DeviceOrientationEvent)
      }
    } catch {
      // Compass unavailable — time fallback covers the sweep.
    }
    trackerRef.current = createOrbitTracker({ sweepDurationMs: SWEEP_DURATION_MS })
    setPhase(PHASES.capturing)
    startRef.current = Date.now()
    timerRef.current = window.setInterval(async () => {
      const video = videoRef.current
      if (!video) return
      const elapsed = Date.now() - startRef.current
      setProgress(Math.min(1, elapsed / SWEEP_DURATION_MS))
      try {
        const shot = await snapshotFrame(video)
        if (shot && !shot.skipped) {
          const { angle, source } = trackerRef.current.push({
            elapsedMs: elapsed,
            headingDeg: headingRef.current,
          })
          framesRef.current.push({ blob: shot.blob, angle, source })
          setFrameCount(framesRef.current.length)
          setCoverage(angleCoverageDeg(framesRef.current.map((f) => f.angle)))
        }
      } catch {
        // One bad tick must not kill the sweep — the gates judge the total.
      }
      const done =
        elapsed >= SWEEP_DURATION_MS ||
        framesRef.current.length >= TARGET_FRAME_COUNT
      if (done) {
        window.clearInterval(timerRef.current)
        timerRef.current = null
        setPhase(PHASES.reviewing)
      }
    }, CAPTURE_INTERVAL_MS)
  }, [])

  const uploadSweep = useCallback(async () => {
    const frames = framesRef.current
    const coverageDeg = angleCoverageDeg(frames.map((f) => f.angle))
    if (!isSweepUsable({ frameCount: frames.length, coverageDeg })) {
      setError(sweepFailureMessage({ frameCount: frames.length, coverageDeg }))
      return
    }
    if (!userId) {
      setError('Sign in again to save this scan.')
      return
    }
    setError(null)
    setPhase(PHASES.uploading)
    // Resume, not restart: the same sweep keeps its job row, and frames
    // the bucket already holds are skipped. A drop at frame 49 resumes
    // at frame 49 — `uploadJobRef` is what survives the interruption.
    let jobId = uploadJobRef.current
    const totalBytes = frames.reduce((sum, f) => sum + (f.blob?.size ?? 0), 0)
    try {
      if (jobId) {
        await setFootScanUploading(supabase, jobId)
      } else {
        const job = await createFootScanJob(supabase, userId)
        jobId = job.id
        uploadJobRef.current = jobId
      }
      // The receipt of what is already there: one listing, then skip.
      // Remote sizes count toward progress — the bar shows bytes the
      // bucket actually holds, never bytes the page hopes are there.
      let doneBytes = 0
      try {
        const remote = uploadedFrameSizes(await listUploadedFrames(supabase, userId, jobId))
        for (const [index, size] of remote) {
          if (index < frames.length) doneBytes += size || frames[index].blob?.size || 0
        }
        var present = remote
      } catch {
        // Listing failed — upload everything; skips are an optimization,
        // and upsert makes repeats harmless.
        var present = new Map()
      }
      setUploadProgress(bytesProgress(doneBytes, totalBytes))
      for (let i = 0; i < frames.length; i++) {
        if (present.has(i)) continue
        await retryable(
          () => uploadScanFrame(supabase, userId, jobId, i, frames[i].angle, frames[i].blob),
          { attempts: 3 },
        )
        doneBytes += frames[i].blob?.size ?? 0
        setUploadProgress(bytesProgress(doneBytes, totalBytes))
      }
      await finishFootScanUpload(supabase, jobId, {
        frameCount: frames.length,
        coverageDeg,
        headingShare: trackerRef.current?.headingShare() ?? 0,
      })
      uploadJobRef.current = null
      // Fire-and-forget: the job row is the truth and the results page
      // polls it, so a trigger failure here must not fail the upload.
      try {
        await supabase.functions.invoke('reconstruct-foot', { body: { jobId } })
      } catch {
        // Results page retry covers it.
      }
      stopCamera()
      setQueuedJobId(jobId)
      setPhase(PHASES.queued)
    } catch (err) {
      if (jobId) {
        try {
          await failFootScanJob(
            supabase,
            jobId,
            'upload_interrupted',
            'Upload paused — your frames so far are saved. Retry to resume where it stopped.',
          )
        } catch {
          // The row update is best-effort; the message below is the truth.
        }
      }
      setError('Upload paused — your frames so far are saved. Retry to resume where it stopped.')
      setPhase(PHASES.reviewing)
    }
  }, [stopCamera, userId])

  const retry = useCallback(() => {
    setError(null)
    setPhase(PHASES.camera)
  }, [])

  return (
    <div className="mx-auto max-w-2xl px-4 py-10 sm:px-6 lg:px-8">
      <Link
        to="/settings/foot-size"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-muted transition-colors duration-200 hover:text-ink"
      >
        <ArrowLeft size={14} strokeWidth={2} />
        Foot size
      </Link>

      <header className="mt-4">
        <p className="overline">3D foot scan</p>
        <h1 className="mt-2 font-display text-3xl font-semibold text-ink">
          Walk around your foot
        </h1>
        <p className="mt-2 text-sm text-muted">
          Beta — the sweep takes about 20 seconds. Keep the whole foot in
          frame while the ring fills.
        </p>
      </header>

      {phase === PHASES.intro && (
        <div className="mt-6 rounded-card border border-hairline bg-raised p-6 shadow-card">
          <ol className="list-decimal space-y-2 pl-5 text-sm text-ink">
            <li>Put your bare foot on the floor with room to walk around it.</li>
            <li>Hold the phone low, pointing at your foot.</li>
            <li>Tap Start and walk slowly once around your foot.</li>
          </ol>
          <button
            type="button"
            onClick={startCamera}
            className="mt-6 inline-flex items-center gap-2 rounded-premium bg-ink px-5 py-3 text-sm font-semibold text-white"
          >
            <Camera size={16} strokeWidth={2} />
            Start camera
          </button>
          {error && <p className="mt-3 text-sm text-red-600">{error}</p>}
        </div>
      )}

      {(phase === PHASES.camera ||
        phase === PHASES.capturing ||
        phase === PHASES.reviewing) && (
        <div className="fixed inset-0 z-40 bg-black">
          <video
            ref={videoRef}
            autoPlay
            playsInline
            muted
            className="absolute inset-0 h-full w-full bg-black object-contain"
          />
          {/* Top scrim: title stays readable over a bright floor. The page
              header scrolls away underneath - this is the fullscreen one. */}
          <div className="pointer-events-none absolute inset-x-0 top-0 bg-gradient-to-b from-black/70 to-transparent px-4 pb-10 pt-[max(1rem,env(safe-area-inset-top))]">
            <Link
              to="/settings/foot-size"
              className="pointer-events-auto inline-flex items-center gap-1.5 text-xs font-semibold text-white/90"
            >
              <ArrowLeft size={14} strokeWidth={2} />
              Foot size
            </Link>
            <p className="mt-3 text-[11px] font-semibold uppercase tracking-widest text-white/70">
              3D foot scan
            </p>
            <h1 className="mt-1 font-display text-2xl font-semibold text-white">
              Walk around your foot
            </h1>
          </div>
          <div className="absolute inset-x-0 bottom-0 space-y-3 bg-gradient-to-t from-black/70 to-transparent p-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-10">
            {phase === PHASES.capturing && (
              <div>
                <div className="h-2 overflow-hidden rounded-full bg-white/20">
                  <div
                    className="h-full rounded-full bg-white transition-[width]"
                    style={{ width: `${Math.round(progress * 100)}%` }}
                  />
                </div>
                <p className="mt-2 text-xs text-white/90">
                  {frameCount} frames · {coverage}° covered — keep going around
                </p>
              </div>
            )}
            {phase === PHASES.camera && rearCams.length > 1 && (
              <div>
                <div className="flex items-center justify-between gap-2">
                  <p className="text-xs text-white/90">
                    Lens — 1× matches your camera app&apos;s main camera
                  </p>
                  <div className="flex items-center gap-2">
                    {rearCams.map((c, i) => (
                      <button
                        key={c.deviceId}
                        type="button"
                        title={c.label}
                        onClick={() => switchLens(i)}
                        className={i === camIdx
                          ? 'rounded-premium bg-white px-3 py-1.5 text-xs font-semibold text-black'
                          : 'rounded-premium border border-white/40 px-3 py-1.5 text-xs font-semibold text-white'}
                      >
                        {c.name}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            )}
            {phase === PHASES.camera && zoomRange && (
              <div>
                <div className="flex items-center justify-between gap-2">
                  <p className="text-xs text-white/90">
                    Zoom {zoom != null ? `${zoom.toFixed(1)}×` : ''} — locks when the sweep starts
                  </p>
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => applyZoom(zoomRange.min)}
                      className="rounded-premium border border-white/40 px-3 py-1.5 text-xs font-semibold text-white"
                    >
                      Wide
                    </button>
                    {zoomRange.max >= 1 && (
                      <button
                        type="button"
                        onClick={() => applyZoom(1)}
                        className="rounded-premium border border-white/40 px-3 py-1.5 text-xs font-semibold text-white"
                      >
                        1×
                      </button>
                    )}
                  </div>
                </div>
                <input
                  type="range"
                  aria-label="Camera zoom"
                  min={zoomRange.min}
                  max={zoomRange.max}
                  step={Math.max(0.05, Number(((zoomRange.max - zoomRange.min) / 20).toFixed(2)))}
                  value={zoom ?? zoomRange.min}
                  onChange={(e) => applyZoom(Number(e.target.value))}
                  className="mt-2 w-full accent-white"
                />
              </div>
            )}
            {phase === PHASES.camera && (
              <button
                type="button"
                onClick={beginSweep}
                className="inline-flex items-center gap-2 rounded-premium bg-white px-5 py-3 text-sm font-semibold text-black"
              >
                Start the sweep
              </button>
            )}
            {phase === PHASES.reviewing && (
              <div className="flex flex-wrap items-center gap-3">
                <p className="text-sm text-white">
                  {frameCount} frames · {coverage}° covered
                  {compassTracked ? ' · compass-tracked' : ' · timer-tracked'}
                </p>
                <button
                  type="button"
                  onClick={uploadSweep}
                  className="inline-flex items-center gap-2 rounded-premium bg-white px-5 py-3 text-sm font-semibold text-black"
                >
                  Upload sweep
                </button>
                <button
                  type="button"
                  onClick={retry}
                  className="inline-flex items-center gap-2 rounded-premium border border-white/40 px-4 py-3 text-sm font-semibold text-white"
                >
                  <RotateCcw size={14} strokeWidth={2} />
                  Sweep again
                </button>
              </div>
            )}
            {error && <p className="text-sm text-red-300">{error}</p>}
          </div>
        </div>
      )}

      {phase === PHASES.uploading && (
        <div className="mt-6 rounded-card border border-hairline bg-raised p-6 text-center shadow-card">
          <Loader2 size={24} className="mx-auto animate-spin text-muted" />
          <p className="mt-3 text-sm text-ink">
            Uploading {Math.round(uploadProgress * 100)}% — keep this page open.
          </p>
        </div>
      )}

      {phase === PHASES.queued && (
        <div className="mt-6 rounded-card border border-hairline bg-raised p-6 text-center shadow-card">
          <p className="text-sm font-semibold text-ink">Sweep uploaded.</p>
          <p className="mt-1 text-sm text-muted">
            Reconstruction runs in the cloud — this page will show your
            measurement when it is ready.
          </p>
          <button
            type="button"
            onClick={() => navigate(`/foot-scan/${queuedJobId}`)}
            className="mt-4 inline-flex items-center gap-2 rounded-premium bg-ink px-5 py-3 text-sm font-semibold text-white"
          >
            View result
          </button>
        </div>
      )}
    </div>
  )
}
