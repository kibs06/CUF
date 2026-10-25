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
  isFrameUsable,
  isSweepUsable,
  lumaStats,
  orbitAngleFor,
  sweepFailureMessage,
} from '../lib/footScanCapture.js'
import {
  createFootScanJob,
  failFootScanJob,
  finishFootScanUpload,
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

export default function FootScan() {
  const { session } = useAuth()
  const navigate = useNavigate()
  const userId = session?.user?.id ?? null

  const [phase, setPhase] = useState(PHASES.intro)
  const [error, setError] = useState(null)
  const [progress, setProgress] = useState(0)
  const [frameCount, setFrameCount] = useState(0)
  const [coverage, setCoverage] = useState(0)
  const [uploadProgress, setUploadProgress] = useState(0)
  const [queuedJobId, setQueuedJobId] = useState(null)

  const videoRef = useRef(null)
  const streamRef = useRef(null)
  const framesRef = useRef([])
  const timerRef = useRef(null)
  const startRef = useRef(0)

  const stopCamera = useCallback(() => {
    window.clearInterval(timerRef.current)
    timerRef.current = null
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
  }, [])

  useEffect(() => stopCamera, [stopCamera])

  const startCamera = useCallback(async () => {
    setError(null)
    setPhase(PHASES.camera)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment', width: { ideal: 1280 }, height: { ideal: 720 } },
        audio: false,
      })
      streamRef.current = stream
      // Wait a frame so the ref is mounted before assigning.
      requestAnimationFrame(() => {
        if (videoRef.current) videoRef.current.srcObject = stream
      })
    } catch {
      setError('Camera unavailable — allow camera access and try again.')
      setPhase(PHASES.intro)
    }
  }, [])

  const beginSweep = useCallback(() => {
    framesRef.current = []
    setFrameCount(0)
    setCoverage(0)
    setProgress(0)
    setError(null)
    setPhase(PHASES.capturing)
    startRef.current = Date.now()
    timerRef.current = window.setInterval(async () => {
      const video = videoRef.current
      if (!video) return
      const elapsed = Date.now() - startRef.current
      const angle = orbitAngleFor(elapsed)
      setProgress(Math.min(1, elapsed / SWEEP_DURATION_MS))
      try {
        const shot = await snapshotFrame(video)
        if (shot && !shot.skipped) {
          framesRef.current.push({ blob: shot.blob, angle })
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
    setUploadProgress(0)
    let jobId = null
    try {
      const job = await createFootScanJob(supabase, userId)
      jobId = job.id
      for (let i = 0; i < frames.length; i++) {
        await uploadScanFrame(supabase, userId, jobId, i, frames[i].angle, frames[i].blob)
        setUploadProgress((i + 1) / frames.length)
      }
      await finishFootScanUpload(supabase, jobId, {
        frameCount: frames.length,
        coverageDeg,
      })
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
          await failFootScanJob(supabase, jobId, 'upload_failed', err?.message ?? 'Upload failed')
        } catch {
          // The row update is best-effort; the message below is the truth.
        }
      }
      setError(err?.message ?? 'Upload failed — check your connection and retry.')
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
        <div className="mt-6 overflow-hidden rounded-card border border-hairline bg-black shadow-card">
          <video
            ref={videoRef}
            autoPlay
            playsInline
            muted
            className="aspect-[4/3] w-full object-cover"
          />
          <div className="space-y-3 bg-raised p-4">
            {phase === PHASES.capturing && (
              <div>
                <div className="h-2 overflow-hidden rounded-full bg-hairline">
                  <div
                    className="h-full rounded-full bg-ink transition-[width]"
                    style={{ width: `${Math.round(progress * 100)}%` }}
                  />
                </div>
                <p className="mt-2 text-xs text-muted">
                  {frameCount} frames · {coverage}° covered — keep going around
                </p>
              </div>
            )}
            {phase === PHASES.camera && (
              <button
                type="button"
                onClick={beginSweep}
                className="inline-flex items-center gap-2 rounded-premium bg-ink px-5 py-3 text-sm font-semibold text-white"
              >
                Start the sweep
              </button>
            )}
            {phase === PHASES.reviewing && (
              <div className="flex flex-wrap items-center gap-3">
                <p className="text-sm text-ink">
                  {frameCount} frames · {coverage}° covered
                </p>
                <button
                  type="button"
                  onClick={uploadSweep}
                  className="inline-flex items-center gap-2 rounded-premium bg-ink px-5 py-3 text-sm font-semibold text-white"
                >
                  Upload sweep
                </button>
                <button
                  type="button"
                  onClick={retry}
                  className="inline-flex items-center gap-2 rounded-premium border border-hairline px-4 py-3 text-sm font-semibold text-ink"
                >
                  <RotateCcw size={14} strokeWidth={2} />
                  Sweep again
                </button>
              </div>
            )}
            {error && <p className="text-sm text-red-600">{error}</p>}
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
