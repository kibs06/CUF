/**
 * Foot-tracked shoe overlay math — the prototype that sticks the shoe to the
 * foot on the customer portal.
 *
 * MediaPipe Pose Landmarker is a sparse whole-body tracker, not a foot
 * tracker: each foot is exactly three points (ankle, heel, foot-index). That
 * is enough for a screen-space prototype — position from the heel→toe axis,
 * yaw from its angle, size from its length — and not enough for fitted,
 * occluded, 6-DoF tracking (that stays in the app, where ARCore depth and
 * the foot tracker live). Everything here is pure so it can be tested
 * without a camera or a browser.
 *
 * Coordinate space: normalized image UV (0–1, origin top-left), the same
 * space the landmarker reports. Pixel conversion happens at the edges.
 */

/** Pose Landmarker indices for the six foot points. */
export const FOOT_LANDMARKS = {
  left: { ankle: 27, heel: 29, toe: 31 },
  right: { ankle: 28, heel: 30, toe: 32 },
}

/** Minimum visibility below which a point is treated as missing. Kept low
 * on purpose: the web beta points at feet, often half-cropped, where the
 * pose model reports low visibility even when the axis is right. */
export const MIN_VISIBILITY = 0.3

/** How long a lost foot is coasted before the shoe lets go (ms). */
export const COAST_MS = 1200

function point(landmarks, index) {
  const p = landmarks?.[index]
  if (!p) return null
  const visibility = p.visibility ?? p.presence ?? 1
  if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) return null
  if (visibility < MIN_VISIBILITY) return null
  return { x: p.x, y: p.y, score: visibility }
}

/**
 * The feet the tracker can see right now — at most one entry per side, and
 * only when heel AND toe are both visible (an axis needs two points; the
 * ankle steadies it but is optional).
 */
export function extractFeet(landmarks) {
  const feet = []
  for (const side of ['left', 'right']) {
    const idx = FOOT_LANDMARKS[side]
    const heel = point(landmarks, idx.heel)
    const toe = point(landmarks, idx.toe)
    if (!heel || !toe) continue
    const ankle = point(landmarks, idx.ankle)
    feet.push({
      side,
      heel,
      toe,
      ankle,
      score: Math.min(heel.score, toe.score),
    })
  }
  return feet
}

/**
 * Which foot wears the shoe this frame: the best visible one, with a stick
 * to the previously worn side so the shoe does not jump feet when both are
 * in frame and scores are close.
 */
export function pickFoot(feet, previousSide = null) {
  if (feet.length === 0) return null
  if (feet.length === 1) return feet[0]
  const ranked = [...feet].sort((a, b) => b.score - a.score)
  const prev = feet.find((f) => f.side === previousSide)
  // A small hysteresis: the previous foot keeps the shoe unless the other
  // foot is clearly better.
  if (prev && ranked[0].score - prev.score < 0.15) return prev
  return ranked[0]
}

/** Normalized UV → pixels for the current video frame size. */
export function toPixels(p, videoW, videoH) {
  return { x: p.x * videoW, y: p.y * videoH }
}

/**
 * Pose foot-index (31/32) sits proximal to the true toe tip and the heel
 * point sits forward of the true heel back — a shoe scaled to their raw
 * distance renders short. These extend the axis to the true shoe length.
 */
export const TOE_EXTENSION = 0.28
/** How far behind the detected heel the true heel back sits. */
export const HEEL_BACK = 0.16

/**
 * Where the shoe goes, in video pixels: anchored at the extended heel,
 * pointing at the extended toe. The renderer draws the model with its toe
 * forward along this axis and its length matched to `lengthPx`.
 *
 * `lengthPx` already includes the toe/heel extension, so callers must not
 * re-apply it — `yawGroup.scale` takes it as-is.
 */
export function placementFromFoot(foot, videoW, videoH) {
  const rawHeel = toPixels(foot.heel, videoW, videoH)
  const rawToe = toPixels(foot.toe, videoW, videoH)
  const dx = rawToe.x - rawHeel.x
  const dy = rawToe.y - rawHeel.y
  const rawLen = Math.hypot(dx, dy)
  if (!(rawLen > 1)) return null
  const ux = dx / rawLen
  const uy = dy / rawLen
  const heelBackPx = rawLen * HEEL_BACK
  const toeExtPx = rawLen * TOE_EXTENSION
  const heel = { x: rawHeel.x - ux * heelBackPx, y: rawHeel.y - uy * heelBackPx }
  const toe = { x: rawToe.x + ux * toeExtPx, y: rawToe.y + uy * toeExtPx }
  const lengthPx = rawLen + heelBackPx + toeExtPx
  return {
    heel,
    toe,
    lengthPx,
    rawLen,
    angleRad: Math.atan2(dy, dx),
    side: foot.side,
    score: foot.score,
  }
}

/**
 * False-positive guard for the shin望tiny-shoe symptom: when the pose model
 * loses body context on a foot close-up it collapses heel+toe into a short
 * axis up the leg. Anything shorter than ~12% of the short frame edge is
 * not a foot — the caller should coast/hide, never draw a tiny shoe on
 * the shin.
 */
export function isPlausiblePlacement(place, videoW, videoH) {
  if (!place) return false
  if (!Number.isFinite(videoW) || !Number.isFinite(videoH)) return false
  if (!(videoW > 0) || !(videoH > 0)) return false
  const minLen = Math.min(videoW, videoH) * 0.12
  const maxLen = Math.max(videoW, videoH) * 0.95
  if (!(place.lengthPx >= minLen)) return false
  if (place.lengthPx > maxLen) return false
  for (const p of [place.heel, place.toe]) {
    if (!p || !Number.isFinite(p.x) || !Number.isFinite(p.y)) return false
    // Allow slightly off-frame close-ups, but not a point a full frame away.
    if (p.x < -videoW * 0.25 || p.x > videoW * 1.25) return false
    if (p.y < -videoH * 0.25 || p.y > videoH * 1.25) return false
  }
  return true
}

/** Exponential moving average for a point — the wobble remover. */
export function smoothPoint(prev, next, alpha = 0.45) {
  if (!prev) return next
  return {
    x: prev.x + alpha * (next.x - prev.x),
    y: prev.y + alpha * (next.y - prev.y),
  }
}

/** EMA for an angle, turning the short way around the circle. */
export function smoothAngle(prevRad, nextRad, alpha = 0.35) {
  if (prevRad === null || prevRad === undefined) return nextRad
  let delta = nextRad - prevRad
  while (delta > Math.PI) delta -= 2 * Math.PI
  while (delta < -Math.PI) delta += 2 * Math.PI
  return prevRad + alpha * delta
}

/**
 * Whether the shoe should still be drawn: visible now, or lost recently
 * enough to coast through a detection gap (the detector runs a few times a
 * second; a gap is not the foot leaving).
 */
export function shouldDrawShoe({ seenNow, lastSeenMs, nowMs }) {
  if (seenNow) return true
  if (!Number.isFinite(lastSeenMs)) return false
  return nowMs - lastSeenMs <= COAST_MS
}

/**
 * Phase 3 -- leg-proportion scale prior (fix the scale at its source).
 *
 * Measurement basis (`docs/FOOT_TRYON_PHASE3_REPORT.md`): across the 15
 * phone fixture frames the extended heel-to-toe axis lands at ~20-37% of the
 * true foot length (~110-206px vs ~550px), with large framing variance.
 * The axis alone cannot know the scale, so a second, independent length
 * estimate is blended in.
 *
 * The prior: foot length ~= 0.626 x knee-to-ankle shank length (Hora et al.
 * 2017, quotients of group means, men and women, adults 19-38 -- see
 * `docs/foot-tryon-research.md`). The shank spans several hundred pixels
 * where the collapsed foot axis spans tens, so it is collapse-resistant;
 * when the two disagree wildly the leg wins and the overlay says so.
 *
 * Limits, stated plainly: the ratio is a population mean, not per-person
 * truth; a foot pointing at the camera is foreshortened and neither
 * estimate models perspective; with no visible knee there is no prior and
 * the axis estimate passes through unchanged (no invented close-up
 * correction -- the data do not justify one).
 */

/** Pose Landmarker indices for the knees. */
export const KNEE_LANDMARKS = { left: 25, right: 26 }

/**
 * Minimum knee visibility. Stricter than the foot gate (0.3): the prior
 * multiplies the shank pixel distance, so a guessed knee scales the error.
 * 0.5 mirrors MediaPipe's own drawing threshold.
 */
export const KNEE_MIN_VISIBILITY = 0.5

/** Foot / shank length ratio (Hora et al. 2017, see research doc). */
export const FOOT_SHANK_RATIO = 0.626

/**
 * Disagreement ratio above which the blend stops trusting the axis.
 * Provisional from fixture variance (extended/true spans 0.20-0.37, i.e. up
 * to ~3x under-read): 1.8 splits honest framing noise from collapse. Needs
 * live validation once knee-visible framings have fixtures.
 */
export const MAX_DISAGREE_RATIO = 1.8

function kneePoint(landmarks, index) {
  const p = landmarks?.[index]
  if (!p) return null
  const visibility = p.visibility ?? p.presence ?? 1
  if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) return null
  if (visibility < KNEE_MIN_VISIBILITY) return null
  return { x: p.x, y: p.y, score: visibility }
}

/**
 * Feet + knees from one detector result, in tracker-agnostic shape.
 * Both backends (Pose worker, main-thread fallback) answer pose messages
 * through here so they can never disagree about the message shape:
 * `{ feet, knees }` with `knees = { left, right }` (null per missing side).
 */
export function poseFromLandmarks(landmarksList) {
  const feet = []
  const knees = { left: null, right: null }
  for (const landmarks of landmarksList ?? []) {
    for (const foot of extractFeet(landmarks)) feet.push(foot)
    const k = extractKnees(landmarks)
    knees.left ??= k.left
    knees.right ??= k.right
  }
  return { feet, knees }
}

/** The knees the tracker can see right now (null per side when missing). */
export function extractKnees(landmarks) {
  const out = {}
  for (const side of ['left', 'right']) {
    out[side] = kneePoint(landmarks, KNEE_LANDMARKS[side])
  }
  return out
}

/**
 * Independent foot-length estimate from the leg, in video pixels.
 * `knee`/`ankle` are normalized UV points with scores; returns
 * `{ lengthPx, confidence, shankPx }` or null when either end is missing.
 */
export function estimateFootLengthFromLeg({ knee, ankle, videoW, videoH }) {
  if (!knee || !ankle) return null
  if (!Number.isFinite(videoW) || !Number.isFinite(videoH)) return null
  if (!(videoW > 0) || !(videoH > 0)) return null
  const dx = (knee.x - ankle.x) * videoW
  const dy = (knee.y - ankle.y) * videoH
  const shankPx = Math.hypot(dx, dy)
  if (!(shankPx > 1)) return null
  return {
    lengthPx: shankPx * FOOT_SHANK_RATIO,
    confidence: Math.min(knee.score ?? 0, ankle.score ?? 0),
    shankPx,
  }
}

/**
 * Blend the axis length with the leg prior into one length.
 * - No prior (null / zero confidence) -> axis unchanged, `source: 'axis'`.
 * - Agree (ratio <= MAX_DISAGREE_RATIO) -> confidence-weighted mean.
 * - Disagree -> the leg wins (`source: 'leg-override'`, `disagree: true`)
 *   because a collapsed axis is the known failure and the shank is the
 *   longer, stabler measurement. The caller surfaces `disagree` in debug.
 * The existing length lerp still applies downstream for smoothness.
 */
export function blendFootLength({ axisLengthPx, axisConfidence = 0.5, legPriorPx = null, legConfidence = 0 }) {
  if (!(axisLengthPx > 0)) return null
  if (!Number.isFinite(axisConfidence) || axisConfidence < 0) axisConfidence = 0.5
  if (!(legPriorPx > 0) || !(legConfidence > 0)) {
    return { lengthPx: axisLengthPx, source: 'axis', disagree: false }
  }
  const hi = Math.max(axisLengthPx, legPriorPx)
  const lo = Math.min(axisLengthPx, legPriorPx)
  if (hi / lo > MAX_DISAGREE_RATIO) {
    return { lengthPx: legPriorPx, source: 'leg-override', disagree: true }
  }
  // total > 0 always here: legConfidence > 0 is guarded above and the
  // axisConfidence guard floors at 0 — no zero-division fallback needed.
  const total = axisConfidence + legConfidence
  return {
    lengthPx: (axisLengthPx * axisConfidence + legPriorPx * legConfidence) / total,
    source: 'blend',
    disagree: false,
  }
}

/**
 * Step-in gate tuning (provisional — re-derive from the first live
 * `?footdebug=1` step-in export):
 * - the foot counts as "inside" the staged shoe past this fraction of its
 *   axis within tolerance of the stage axis;
 * - it must dwell there this many consecutive pose messages (the detector
 *   answers ~10x/s, so 4 is roughly a second of stepping in);
 * - faster than this it is a walk-past, not a step-in.
 */
export const STEPIN_OVERLAP_RATIO = 0.35
export const STEPIN_SUSTAIN_FRAMES = 4
export const STEPIN_MAX_VELOCITY_PX_S = 120
/** Wall-clock length of the staged → worn handoff (smoothstep-eased). */
export const HANDOFF_MS = 300

function pointSegDist(p, a, b) {
  const dx = b.x - a.x
  const dy = b.y - a.y
  const lenSq = dx * dx + dy * dy
  if (!(lenSq > 0)) return Math.hypot(p.x - a.x, p.y - a.y)
  const u = Math.min(1, Math.max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
  return Math.hypot(p.x - (a.x + u * dx), p.y - (a.y + u * dy))
}

/**
 * Fraction of the foot axis (sampled) lying within tolerance of the stage
 * axis. Tolerance scales with the stage size so the gate behaves the same
 * near and far. All inputs are video-pixel points; returns 0 on bad input.
 */
export function axisOverlapRatio(footHeel, footToe, stageHeel, stageToe, samples = 9) {
  for (const p of [footHeel, footToe, stageHeel, stageToe]) {
    if (!p || !Number.isFinite(p.x) || !Number.isFinite(p.y)) return 0
  }
  const stageLen = Math.hypot(stageToe.x - stageHeel.x, stageToe.y - stageHeel.y)
  if (!(stageLen > 0) || !(samples >= 1)) return 0
  const tol = stageLen * STEPIN_OVERLAP_RATIO
  let inside = 0
  for (let i = 0; i < samples; i += 1) {
    const u = samples === 1 ? 0 : i / (samples - 1)
    const p = {
      x: footHeel.x + (footToe.x - footHeel.x) * u,
      y: footHeel.y + (footToe.y - footHeel.y) * u,
    }
    if (pointSegDist(p, stageHeel, stageToe) <= tol) inside += 1
  }
  return inside / samples
}

/**
 * Whether a staged shoe may attach to the foot this frame. Returns
 * `{ armed, overlapRatio, overlapFrames }` — the caller keeps
 * `overlapFrames` across pose messages so dwelling accumulates, and resets
 * it (by passing 0) whenever the foot leaves or the shoe re-stages. Bad
 * input never arms: a gate that cannot see clearly stays shut.
 */
export function stepInGate({
  footHeel,
  footToe,
  stageHeel,
  stageToe,
  footVelocityPxPerSec = 0,
  overlapFrames = 0,
}) {
  const overlapRatio = axisOverlapRatio(footHeel, footToe, stageHeel, stageToe)
  const dwelling = overlapRatio >= STEPIN_OVERLAP_RATIO
  const slow =
    Number.isFinite(footVelocityPxPerSec) &&
    footVelocityPxPerSec >= 0 &&
    footVelocityPxPerSec <= STEPIN_MAX_VELOCITY_PX_S
  const next = dwelling && slow ? overlapFrames + 1 : 0
  return {
    armed: next >= STEPIN_SUSTAIN_FRAMES,
    overlapRatio,
    overlapFrames: next,
  }
}

/**
 * Whether the staged shoe counts as drawable this frame. While staged the
 * shoe waits visibly: there is no `lastSeen` yet (NaN), so the coast check
 * alone would hide the stage on the first empty pose message. The viewer
 * ORs this into `shouldDrawShoe`'s `seenNow` — staged always draws, worn
 * follows tracking exactly as before.
 */
export function isStagedDrawable({ manual } = {}) {
  return Boolean(manual)
}

/**
 * One frame of the staged → worn handoff: smoothstep-eased (`t` is 0–1
 * wall-clock progress, clamped) interpolation of heel, toe, angle and
 * length from the stage pose to the live tracked pose. Angles take the
 * short way around (shared with the smoothing EMA). Non-finite input
 * returns the target as-is — a handoff that cannot see clearly jumps
 * rather than drawing garbage.
 */
export function handoffPose({ from, to, t }) {
  const k = Number.isFinite(t) ? Math.min(1, Math.max(0, t)) : 1
  const e = k * k * (3 - 2 * k)
  const pts = [from?.heel, from?.toe, to?.heel, to?.toe]
  const nums = [from?.angle, to?.angle, from?.length, to?.length]
  const ok =
    pts.every((p) => p && Number.isFinite(p.x) && Number.isFinite(p.y)) &&
    nums.every(Number.isFinite) &&
    to.length > 0
  if (!ok) return { ...to }
  const lerp = (a, b) => a + (b - a) * e
  return {
    heel: { x: lerp(from.heel.x, to.heel.x), y: lerp(from.heel.y, to.heel.y) },
    toe: { x: lerp(from.toe.x, to.toe.x), y: lerp(from.toe.y, to.toe.y) },
    angle: smoothAngle(from.angle, to.angle, e),
    length: lerp(from.length, to.length),
  }
}
