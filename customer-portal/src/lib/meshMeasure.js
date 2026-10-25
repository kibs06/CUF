/**
 * Mesh measurement — numbers from a reconstructed foot mesh.
 *
 * Pure, no three.js import: the worker (or the results page, once it
 * loads the GLB) supplies an axis-aligned bounding box in meters and
 * the sweep evidence behind it; this module turns that into
 * millimeters, a confidence score, and an EU size suggestion.
 *
 * The confidence blends three independent doubts the way the app's AR
 * pipeline blends sample spread (median/IQR spirit — tight evidence =
 * high confidence, never a bare number without its uncertainty):
 *   1. orbit coverage — holes in the circle hide the true outline;
 *   2. frame count — fewer gated frames, noisier surface;
 *   3. reconstruction residual — what the worker admits it could not fit.
 */

export const MIN_MESH_CONFIDENCE = 0.5

/**
 * Adult foot-length → EU size table (foot length, not last length —
 * the +1cm wear allowance is already inside the boundaries).
 * Covers EU 35–48; outside returns null rather than a guess.
 */
const EU_TABLE = [
  [221, '35'], [226, '36'], [231, '37'], [236, '38'], [241, '39'],
  [246, '40'], [251, '41'], [256, '42'], [261, '43'], [266, '44'],
  [271, '45'], [276, '46'], [281, '47'], [286, '48'],
]

/** Foot length in mm → EU size, or null outside the table. */
export function euSizeFromLengthMm(lengthMm) {
  if (!Number.isFinite(lengthMm)) return null
  // Below a UK-3 foot there is no adult size to give — null, not '35'.
  if (lengthMm < EU_TABLE[0][0] - 5) return null
  for (let i = 0; i < EU_TABLE.length; i++) {
    if (lengthMm < EU_TABLE[i][0] + 5) return EU_TABLE[i][1]
  }
  return null
}

/**
 * Measure a reconstructed foot mesh.
 *
 * @param box {{size:{x,y,z}}} axis-aligned bounding box in meters,
 *   Y-up (three.js `Box3` convention): x = width, y = height, z = length.
 * @param evidence {coverageDeg, frameCount, residualMm} sweep evidence.
 * @returns null on a degenerate box, else
 *   `{ lengthMm, widthMm, heightMm, confidence, confidenceLevel, euSize }`.
 */
export function measureFootMesh(box, evidence = {}) {
  const size = box?.size ?? {}
  const { x, y, z } = size
  if (![x, y, z].every((v) => Number.isFinite(v) && v > 0)) return null
  // Plausibility: a foot is 15–35cm long, 5–15cm wide, 4–15cm tall.
  // Anything else is a misscaled or partial reconstruction — say so
  // with null, not with a shoe size.
  if (z < 0.15 || z > 0.35 || x < 0.05 || x > 0.15 || y < 0.04 || y > 0.15) {
    return null
  }

  const lengthMm = Math.round(z * 1000)
  const widthMm = Math.round(x * 1000)
  const heightMm = Math.round(y * 1000)

  const coverage = Number.isFinite(evidence.coverageDeg)
    ? Math.min(1, Math.max(0, evidence.coverageDeg / 360))
    : 0.5
  const frames = Number.isFinite(evidence.frameCount)
    ? Math.min(1, Math.max(0, evidence.frameCount / 50))
    : 0.5
  const residual = Number.isFinite(evidence.residualMm)
    ? Math.min(1, Math.max(0, 1 - evidence.residualMm / 5))
    : 0.5

  // Coverage dominates: a half-orbit hides the outline no frame count fixes.
  const confidence = Math.round((coverage * 0.5 + frames * 0.2 + residual * 0.3) * 100) / 100
  const confidenceLevel = confidence >= 0.8 ? 'high' : confidence >= MIN_MESH_CONFIDENCE ? 'medium' : 'low'

  return {
    lengthMm,
    widthMm,
    heightMm,
    confidence,
    confidenceLevel,
    euSize: euSizeFromLengthMm(lengthMm),
  }
}

/**
 * Customer-safe sentence for the measurement — same honesty contract
 * as the capture gates: the number plus its uncertainty, never a bare
 * number that reads more precise than the sweep was.
 */
export function measurementSummary(measurement) {
  if (!measurement) return 'No measurement yet.'
  const { lengthMm, widthMm, confidenceLevel, euSize } = measurement
  const size = euSize ? ` — about EU ${euSize}` : ''
  return `${lengthMm} mm long, ${widthMm} mm wide${size} (${confidenceLevel} confidence).`
}
