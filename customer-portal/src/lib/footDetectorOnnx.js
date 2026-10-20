/**
 * YOLO11-pose ONNX output decode — pure helpers shared by the worker and tests.
 *
 * Model contract (`foot` class + heel/toe keypoints, 640 input, Ultralytics
 * pose head): one row per proposal
 *   `[cx, cy, w, h, heel_x, heel_y, heel_conf, toe_x, toe_y, toe_conf, box_conf]`
 * in normalized 0–1 input space. This module does NOT run inference — it turns
 * rows into the portal's `feet` shape (`{ side, heel, toe, ankle, score }`)
 * so the rest of the pipeline (`footTryOn.js`) never knows which backend fired.
 *
 * `ankle` is always null from this backend (the model never predicts it);
 * callers already treat ankle as optional.
 */

export const FOOT_ONNX_URL = '/vendor/foot-detector/foot-v1.onnx'
/** Minimum box confidence to keep a proposal. */
export const ONNX_BOX_CONF = 0.35
/** Minimum keypoint confidence to keep a heel/toe point. */
export const ONNX_KPT_CONF = 0.3
/** IoU threshold for the tiny NMS pass (feet rarely overlap). */
export const ONNX_NMS_IOU = 0.45

function boxIoU(a, b) {
  const x1 = Math.max(a.x - a.w / 2, b.x - b.w / 2)
  const y1 = Math.max(a.y - a.h / 2, b.y - b.h / 2)
  const x2 = Math.min(a.x + a.w / 2, b.x + b.w / 2)
  const y2 = Math.min(a.y + a.h / 2, b.y + b.h / 2)
  const inter = Math.max(0, x2 - x1) * Math.max(0, y2 - y1)
  const union = a.w * a.h + b.w * b.h - inter
  if (!(union > 0)) return 0
  return inter / union
}

/**
 * Decode raw proposal rows → portal feet (normalized UV, same as Pose path).
 * Rows with low box conf, or missing heel AND toe, are dropped. Side is
 * always `left` — the single-class schema has no left/right; the viewer's
 * hysteresis keeps the shoe stable regardless.
 */
export function decodeOnnxProposals(rows) {
  const kept = []
  for (const r of rows ?? []) {
    if (!r || r.length < 11) continue
    const [cx, cy, w, h, hx, hy, hc, tx, ty, tc, conf] = r
    if (!(conf >= ONNX_BOX_CONF)) continue
    if (![cx, cy, w, h].every(Number.isFinite)) continue
    const heel =
      Number.isFinite(hx) && Number.isFinite(hy) && hc >= ONNX_KPT_CONF
        ? { x: hx, y: hy, score: hc }
        : null
    const toe =
      Number.isFinite(tx) && Number.isFinite(ty) && tc >= ONNX_KPT_CONF
        ? { x: tx, y: ty, score: tc }
        : null
    if (!heel || !toe) continue
    kept.push({ x: cx, y: cy, w, h, heel, toe, score: conf })
  }
  // Tiny NMS: highest conf wins overlapping boxes.
  kept.sort((a, b) => b.score - a.score)
  const picked = []
  for (const c of kept) {
    if (picked.some((o) => boxIoU(o, c) > ONNX_NMS_IOU)) continue
    picked.push(c)
    if (picked.length >= 2) break
  }
  return picked.map((c) => ({
    side: 'left',
    heel: c.heel,
    toe: c.toe,
    ankle: null,
    score: c.score,
  }))
}
