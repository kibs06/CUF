import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, Loader2, RotateCcw, Save } from 'lucide-react'

import { useAuth } from '../hooks/useAuth.jsx'
import { supabase } from '../lib/supabase.js'
import { getFootScanJob } from '../lib/footScanJobs.js'
import { measurementSummary } from '../lib/meshMeasure.js'

/**
 * 360° scan result — polls the job row until the cloud finishes.
 *
 * Three states, each honest: `processing` (spinner, no fake progress),
 * `failed` (the job's own customer-safe sentence + retry), `done`
 * (mesh preview + measurements + save). The mesh preview loads the
 * GLB straight from the private bucket via a signed URL — the file
 * never becomes public to be viewable.
 */

const POLL_MS = 3000

function measurementsOf(job) {
  const m = job?.measurements
  if (!m || typeof m !== 'object') return null
  if (!Number.isFinite(m.lengthMm) || !Number.isFinite(m.widthMm)) return null
  return m
}

export default function FootScanResult() {
  const { jobId } = useParams()
  const { session } = useAuth()

  const [job, setJob] = useState(null)
  const [error, setError] = useState(null)
  const [retrying, setRetrying] = useState(false)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [meshUrl, setMeshUrl] = useState(null)

  useEffect(() => {
    let cancelled = false
    let timer = null
    const poll = async () => {
      try {
        const row = await getFootScanJob(supabase, jobId)
        if (cancelled) return
        setJob(row)
        if (row.status === 'processing' || row.status === 'queued' || row.status === 'uploading') {
          timer = window.setTimeout(poll, POLL_MS)
        }
      } catch (err) {
        if (!cancelled) setError(err?.message ?? 'Could not load this scan.')
      }
    }
    poll()
    return () => {
      cancelled = true
      window.clearTimeout(timer)
    }
  }, [jobId])

  // Signed mesh URL once the job is done — private bucket, 1-hour grant.
  useEffect(() => {
    if (job?.status !== 'done' || !job.mesh_path) return
    let cancelled = false
    supabase.storage
      .from('foot-scans')
      .createSignedUrl(job.mesh_path, 3600)
      .then(({ data, error: urlError }) => {
        if (!cancelled && !urlError) setMeshUrl(data.signedUrl)
      })
    return () => {
      cancelled = true
    }
  }, [job?.status, job?.mesh_path])

  const retry = useCallback(async () => {
    setRetrying(true)
    setError(null)
    try {
      const { error: invokeError } = await supabase.functions.invoke('reconstruct-foot', {
        body: { jobId },
      })
      if (invokeError) throw new Error(invokeError.message)
      const row = await getFootScanJob(supabase, jobId)
      setJob(row)
    } catch (err) {
      setError(err?.message ?? 'Retry failed — try again in a bit.')
    } finally {
      setRetrying(false)
    }
  }, [jobId])

  const saveMeasurement = useCallback(async () => {
    const m = measurementsOf(job)
    const userId = session?.user?.id
    if (!m || !userId) return
    setSaving(true)
    setError(null)
    try {
      const { error: insertError } = await supabase.from('foot_measurements').insert({
        user_id: userId,
        foot_length_left_mm: m.lengthMm,
        foot_width_left_mm: m.widthMm,
        foot_length_right_mm: m.lengthMm,
        foot_width_right_mm: m.widthMm,
        recommended_eu_size: m.euSize ?? null,
        paper_size_used: 'ar',
        foot_condition: 'bare',
        measurement_source: 'portal_360',
        algorithm_version: 'portal-v1',
        overall_confidence_score: m.confidence ?? null,
        confidence_level: m.confidenceLevel ?? null,
        raw_sample_count: job.frame_count ?? null,
        final_sample_count: job.frame_count ?? null,
      })
      if (insertError) throw new Error(insertError.message)
      setSaved(true)
    } catch (err) {
      setError(err?.message ?? 'Could not save — try again.')
    } finally {
      setSaving(false)
    }
  }, [job, session])

  const measurement = measurementsOf(job)

  return (
    <div className="mx-auto max-w-2xl px-4 py-10 sm:px-6 lg:px-8">
      <Link
        to="/foot-scan"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-muted transition-colors duration-200 hover:text-ink"
      >
        <ArrowLeft size={14} strokeWidth={2} />
        New scan
      </Link>

      <header className="mt-4">
        <p className="overline">3D foot scan</p>
        <h1 className="mt-2 font-display text-3xl font-semibold text-ink">
          Your measurement
        </h1>
      </header>

      {error && (
        <p className="mt-6 rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs text-ink">
          {error}
        </p>
      )}

      {!job && !error && (
        <div className="mt-6 rounded-card border border-hairline bg-raised p-6 text-center shadow-card">
          <Loader2 size={24} className="mx-auto animate-spin text-muted" />
          <p className="mt-3 text-sm text-muted">Loading your scan…</p>
        </div>
      )}

      {job &&
        (job.status === 'queued' ||
          job.status === 'uploading' ||
          job.status === 'processing') && (
          <div className="mt-6 rounded-card border border-hairline bg-raised p-6 text-center shadow-card">
            <Loader2 size={24} className="mx-auto animate-spin text-muted" />
            <p className="mt-3 text-sm font-semibold text-ink">
              Reconstructing your foot…
            </p>
            <p className="mt-1 text-xs text-muted">
              {job.frame_count} frames · {Math.round(job.angle_coverage_deg ?? 0)}°
              covered. This page updates on its own — no need to refresh.
            </p>
          </div>
        )}

      {job?.status === 'failed' && (
        <div className="mt-6 rounded-card border border-hairline bg-raised p-6 text-center shadow-card">
          <p className="text-sm text-ink">
            {job.error_message ?? 'Reconstruction failed.'}
          </p>
          <button
            type="button"
            onClick={retry}
            disabled={retrying}
            className="mt-4 inline-flex items-center gap-2 rounded-premium bg-ink px-5 py-3 text-sm font-semibold text-white disabled:opacity-60"
          >
            <RotateCcw size={14} strokeWidth={2} />
            {retrying ? 'Retrying…' : 'Retry reconstruction'}
          </button>
        </div>
      )}

      {job?.status === 'done' && (
        <div className="mt-6 space-y-6">
          {meshUrl ? (
            <div className="overflow-hidden rounded-card border border-hairline bg-black shadow-card">
              {/* model-viewer is already a portal dependency — lazy so the
                  results page carries no 3D weight until a mesh exists. */}
              <model-viewer
                src={meshUrl}
                camera-controls
                auto-rotate
                style={{ width: '100%', height: '320px' }}
              />
            </div>
          ) : (
            <div className="rounded-card border border-hairline bg-raised p-6 text-center shadow-card">
              <Loader2 size={20} className="mx-auto animate-spin text-muted" />
              <p className="mt-2 text-xs text-muted">Loading your 3D foot…</p>
            </div>
          )}

          <div className="rounded-card border border-hairline bg-raised p-6 shadow-card">
            <p className="font-display text-lg font-semibold text-ink">
              {measurement ? measurementSummary(measurement) : 'Measurement coming…'}
            </p>
            {!measurement && (
              <p className="mt-1 text-xs text-muted">
                The mesh is ready but the numbers are not — try again in a bit.
              </p>
            )}
            {measurement && !saved && (
              <button
                type="button"
                onClick={saveMeasurement}
                disabled={saving}
                className="mt-4 inline-flex items-center gap-2 rounded-premium bg-ink px-5 py-3 text-sm font-semibold text-white disabled:opacity-60"
              >
                <Save size={14} strokeWidth={2} />
                {saving ? 'Saving…' : 'Save as my foot size'}
              </button>
            )}
            {saved && (
              <p className="mt-4 text-sm font-semibold text-ink">
                Saved — product pages will use this measurement.
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
