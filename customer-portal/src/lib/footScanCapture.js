/**
 * Guided 360° foot-scan capture helpers — pure, no browser APIs.
 *
 * The idea (own-build, no vendor): the user walks the phone around their
 * foot once while the page auto-captures frames. Each frame is tagged with
 * an approximate orbit angle derived from elapsed time over the expected
 * sweep duration — not survey-grade, just enough to prove coverage (the
 * reconstruction worker re-solves real poses from image overlap anyway;
 * our angle is the *coverage receipt*, not the calibration).
 *
 * Quality gates reuse the portal's existing foot detector upstream
 * (`footDetectorOnnx.js`); what lives here is the timing/geometry math
 * that decides WHEN to capture and WHETHER the sweep covered the foot.
 */

/** Expected full-sweep duration (ms) — a slow walk around a foot. */
export const SWEEP_DURATION_MS = 20000

/** Target frames per sweep — ~1 per 6° at full coverage. */
export const TARGET_FRAME_COUNT = 50

/** Minimum gated frames for a usable sweep. */
export const MIN_FRAME_COUNT = 40

/** Minimum orbit coverage (degrees) for a usable sweep. */
export const MIN_COVERAGE_DEG = 300

/** Capture interval (ms) derived from sweep duration and target count. */
export const CAPTURE_INTERVAL_MS = Math.floor(SWEEP_DURATION_MS / TARGET_FRAME_COUNT)

/**
 * Approximate orbit angle (0–360) for an elapsed sweep time.
 * Linear by design: the guide ring moves at constant speed and the user
 * follows it, so time is the honest proxy we have (no gyro fusion yet).
 */
export function orbitAngleFor(elapsedMs, sweepDurationMs = SWEEP_DURATION_MS) {
  if (!Number.isFinite(elapsedMs) || elapsedMs <= 0) return 0
  if (!Number.isFinite(sweepDurationMs) || sweepDurationMs <= 0) return 0
  const t = Math.min(elapsedMs / sweepDurationMs, 1)
  return Math.round(t * 360)
}

/**
 * Orbit coverage in degrees from a list of captured angles.
 * Sorts, then sums gaps between neighbours (wrapping at 360); coverage
 * is 360 minus the single largest gap — the arc the sweep actually saw.
 */
export function angleCoverageDeg(angles) {
  const valid = (Array.isArray(angles) ? angles : []).filter(
    (a) => Number.isFinite(a),
  )
  if (valid.length < 2) return 0
  const sorted = valid
    .map((a) => ((a % 360) + 360) % 360)
    .sort((a, b) => a - b)
  let largestGap = 0
  for (let i = 0; i < sorted.length; i++) {
    const next = sorted[(i + 1) % sorted.length]
    const curr = sorted[i]
    const gap = i === sorted.length - 1 ? sorted[0] + 360 - curr : next - curr
    if (gap > largestGap) largestGap = gap
  }
  return Math.round(Math.min(360, Math.max(0, 360 - largestGap)))
}

/**
 * Whether a captured frame is worth uploading.
 * `sharpness` is variance-of-Laplacian normalized 0–1, `brightness` mean
 * luma 0–1 — both computed at the capture edge before this check.
 * Thresholds are deliberately lenient: a blurry frame wastes upload
 * bytes, but over-gating leaves holes in the orbit that no
 * reconstruction can fill.
 */
export function isFrameUsable({ sharpness, brightness } = {}) {
  if (!Number.isFinite(sharpness) || !Number.isFinite(brightness)) return false
  return sharpness >= 0.15 && brightness >= 0.12 && brightness <= 0.95
}

/**
 * Whether the finished sweep is worth sending to reconstruction.
 * Both gates must pass: enough frames AND enough orbit covered.
 */
export function isSweepUsable({ frameCount, coverageDeg } = {}) {
  return (
    Number.isFinite(frameCount) &&
    Number.isFinite(coverageDeg) &&
    frameCount >= MIN_FRAME_COUNT &&
    coverageDeg >= MIN_COVERAGE_DEG
  )
}

/**
 * Luma statistics for a downscaled RGBA pixel buffer.
 *
 * Pure so it is testable without a camera: `pixels` is any array-like of
 * 0–255 channel values in RGBA order. Returns mean luma and normalized
 * variance (0–1), the two signals `isFrameUsable` reads. Variance is the
 * cheap blur proxy — a sharp foot edge spreads luma, motion blur flattens
 * it — computed on a 48px thumbnail so it costs nothing per capture tick.
 */
export function lumaStats(pixels) {
  const n = Math.floor((pixels?.length ?? 0) / 4)
  if (n < 16) return { brightness: 0, sharpness: 0 }
  let sum = 0
  const lumas = new Array(n)
  for (let i = 0; i < n; i++) {
    const r = pixels[i * 4] / 255
    const g = pixels[i * 4 + 1] / 255
    const b = pixels[i * 4 + 2] / 255
    const y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    lumas[i] = y
    sum += y
  }
  const mean = sum / n
  let variance = 0
  for (let i = 0; i < n; i++) {
    const d = lumas[i] - mean
    variance += d * d
  }
  variance /= n
  // Luma variance of a real scene sits ~0.01–0.08; normalize so the
  // `isFrameUsable` sharpness floor (0.15) means "some texture present"
  // rather than a number nobody can picture.
  return { brightness: mean, sharpness: Math.min(1, variance / 0.02) }
}

/**
 * Customer-safe sentence for a sweep that failed the gates — the same
 * honesty contract as the try-on fallback banners: say what happened
 * and what to do, never a code.
 */
export function sweepFailureMessage({ frameCount, coverageDeg } = {}) {
  if (!Number.isFinite(frameCount) || frameCount < MIN_FRAME_COUNT) {
    return 'Not enough clear frames — hold steadier and sweep slower.'
  }
  if (!Number.isFinite(coverageDeg) || coverageDeg < MIN_COVERAGE_DEG) {
    return 'You only covered part of the circle — go all the way around the foot.'
  }
  return 'That sweep was not usable — try once more, slower.'
}
