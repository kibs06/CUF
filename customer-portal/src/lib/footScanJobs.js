/**
 * Foot-scan job storage — the portal's client half of the 360° contract.
 *
 * One sweep is one `foot_scan_jobs` row plus `<uid>/<jobId>/frames/*.jpg`
 * objects in the private `foot-scans` bucket. The reconstruction worker
 * (Edge Function `reconstruct-foot`, Phase 2) reads the same paths. This
 * module owns the path convention so the page, the function, and the
 * worker can never disagree about where a frame lives.
 */

export const FOOT_SCANS_BUCKET = 'foot-scans'

/** Storage prefix for one job's frames: `<uid>/<jobId>/frames`. */
export function jobFramesPrefix(userId, jobId) {
  return `${userId}/${jobId}/frames`
}

/** Storage path for one mesh: `<uid>/<jobId>/mesh/foot.glb`. */
export function jobMeshPath(userId, jobId) {
  return `${userId}/${jobId}/mesh/foot.glb`
}

/** Zero-padded frame object name — sorts in capture order. */
export function frameObjectName(index, angleDeg) {
  return `frame-${String(index).padStart(3, '0')}-a${String(Math.round(angleDeg)).padStart(3, '0')}.jpg`
}

/**
 * Create the job row before uploading (status `uploading`).
 * Returns the new row.
 */
export async function createFootScanJob(supabase, userId) {
  const { data, error } = await supabase
    .from('foot_scan_jobs')
    .insert({ user_id: userId, status: 'uploading' })
    .select()
    .single()
  if (error) throw new Error(error.message)
  return data
}

/**
 * Upload one JPEG frame blob to the job's prefix.
 */
export async function uploadScanFrame(supabase, userId, jobId, index, angleDeg, blob) {
  const path = `${jobFramesPrefix(userId, jobId)}/${frameObjectName(index, angleDeg)}`
  const { error } = await supabase.storage
    .from(FOOT_SCANS_BUCKET)
    .upload(path, blob, { contentType: 'image/jpeg', upsert: true })
  if (error) throw new Error(error.message)
  return path
}

/**
 * Mark the upload finished: frame count + coverage, back to `queued`
 * for the reconstruction worker to pick up.
 */
export async function finishFootScanUpload(supabase, jobId, { frameCount, coverageDeg, headingShare = 0 }) {
  const { data, error } = await supabase
    .from('foot_scan_jobs')
    .update({
      status: 'queued',
      frame_count: frameCount,
      angle_coverage_deg: coverageDeg,
      heading_share: headingShare,
      updated_at: new Date().toISOString(),
    })
    .eq('id', jobId)
    .select()
    .single()
  if (error) throw new Error(error.message)
  return data
}

/** Mark the job failed with a machine code + customer-safe message. */
export async function failFootScanJob(supabase, jobId, errorCode, errorMessage) {
  const { error } = await supabase
    .from('foot_scan_jobs')
    .update({
      status: 'failed',
      error_code: errorCode,
      error_message: errorMessage,
      updated_at: new Date().toISOString(),
    })
    .eq('id', jobId)
  if (error) throw new Error(error.message)
}

/**
 * Run an async operation with per-frame retry (exponential backoff).
 * Pure orchestration — `sleep` is injectable so tests never wait.
 * Throws the last error after `attempts` tries.
 */
export async function retryable(operation, { attempts = 3, baseDelayMs = 500, sleep = (ms) => new Promise((r) => setTimeout(r, ms)) } = {}) {
  let lastError = null
  for (let attempt = 1; attempt <= Math.max(1, attempts); attempt++) {
    try {
      return await operation(attempt)
    } catch (err) {
      lastError = err
      if (attempt < attempts) await sleep(baseDelayMs * 2 ** (attempt - 1))
    }
  }
  throw lastError
}

/**
 * Reopen an interrupted job for resume: `failed`/`uploading` → `uploading`.
 * The already-uploaded frames stay in the bucket; the uploader skips them.
 */
export async function setFootScanUploading(supabase, jobId) {
  const { error } = await supabase
    .from('foot_scan_jobs')
    .update({
      status: 'uploading',
      error_code: null,
      error_message: null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', jobId)
  if (error) throw new Error(error.message)
}

/**
 * Frames already in the bucket for this job: `[{ name, size }]`.
 * Sizes come from the remote listing, so progress can count bytes the
 * bucket actually holds — not bytes the page hopes are there.
 */
export async function listUploadedFrames(supabase, userId, jobId) {
  const { data, error } = await supabase.storage
    .from(FOOT_SCANS_BUCKET)
    .list(jobFramesPrefix(userId, jobId), { limit: 100 })
  if (error) throw new Error(error.message)
  return (data ?? []).map((f) => ({
    name: f.name,
    size: Number(f.metadata?.size) || 0,
  }))
}

/**
 * Index → remote byte size for listed frame objects.
 * Names are `frame-<NNN>-a<AAA>.jpg`; anything else is not ours.
 */
export function uploadedFrameSizes(files) {
  const sizes = new Map()
  for (const file of files ?? []) {
    const match = /^frame-(\d{3})-a\d{3}\.jpg$/.exec(file?.name ?? '')
    if (match) sizes.set(Number(match[1]), file.size || 0)
  }
  return sizes
}

/** Byte progress 0–1, clamped — the bar counts confirmed bytes only. */
export function bytesProgress(doneBytes, totalBytes) {
  if (!Number.isFinite(doneBytes) || !Number.isFinite(totalBytes) || totalBytes <= 0) return 0
  return Math.min(1, Math.max(0, doneBytes / totalBytes))
}

/** Poll the job row (results page) — single read, caller schedules. */
export async function getFootScanJob(supabase, jobId) {
  const { data, error } = await supabase
    .from('foot_scan_jobs')
    .select('*')
    .eq('id', jobId)
    .single()
  if (error) throw new Error(error.message)
  return data
}

/** The user's recent jobs, newest first (history list). */
export async function listFootScanJobs(supabase, userId, limit = 10) {
  const { data, error } = await supabase
    .from('foot_scan_jobs')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(limit)
  if (error) throw new Error(error.message)
  return data ?? []
}
