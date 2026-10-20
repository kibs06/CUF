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
