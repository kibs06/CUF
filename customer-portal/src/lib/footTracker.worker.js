/**
 * The foot detector, off the UI thread.
 *
 * Pose Landmarker's video call is synchronous and blocks whichever thread it
 * runs on, so it lives here: the page sends video frames as transferred
 * `ImageBitmap`s and gets back only the feet (normalized UV + scores — a few
 * hundred bytes). All placement math stays in `footTryOn.js`, shared with
 * this worker so the two can never disagree about which points are a foot.
 *
 * Protocol:
 *   → `{ type: 'init' }` — loads wasm + the Lite pose bundle, answers
 *     `{ type: 'ready' }` or `{ type: 'error', message }`.
 *   → `{ type: 'frame', bitmap, timestampMs }` — answers
 *     `{ type: 'pose', feet, timestampMs }`. The bitmap is transferred and
 *     always closed here, answered or not.
 */
import { FilesetResolver, PoseLandmarker } from '@mediapipe/tasks-vision'

import { extractFeet } from './footTryOn.js'
import { FOOT_ONNX_URL, decodeOnnxProposals } from './footDetectorOnnx.js'
// Single source of truth for the model + wasm URLs — the main-thread
// fallback (`footTrackerMain.js`) owns them so the two paths can never
// download different builds.
import { TRACKER_MODEL_URL as MODEL_URL, TRACKER_WASM_URL as WASM_URL } from './footTrackerMain.js'

let landmarker = null
// Custom foot model (YOLO11n-pose → ONNX) when vendored. Null = absent or
// failed to load → Pose Landmarker path below. The page protocol is unchanged
// either way: `{ type: 'pose', feet, timestampMs }`.
let onnxSession = null

async function createLandmarker(vision, delegate) {
  return PoseLandmarker.createFromOptions(vision, {
    baseOptions: { modelAssetPath: MODEL_URL, delegate },
    runningMode: 'VIDEO',
    numPoses: 2,
    // Low on purpose: feet-first framing gives the pose model little body
    // context, so a strict gate means it never fires on the exact shot the
    // coaching asks for. False positives just coast out via visibility.
    minPoseDetectionConfidence: 0.3,
  })
}

self.onmessage = async (event) => {
  const msg = event.data
  if (!msg || typeof msg !== 'object') return

  if (msg.type === 'init') {
    // Prefer the custom foot model when it exists (trained on real dim feet).
    // A 404 / load failure is the normal pre-training state — fall through
    // to Pose silently so the beta keeps working with no model shipped.
    try {
      const probe = await fetch(FOOT_ONNX_URL, { method: 'HEAD' })
      if (probe.ok) {
        const ort = await import('onnxruntime-web')
        onnxSession = await ort.InferenceSession.create(FOOT_ONNX_URL, {
          executionProviders: ['wasm'],
        })
        self.postMessage({ type: 'ready', backend: 'onnx' })
        return
      }
    } catch {
      onnxSession = null
    }
    try {
      const vision = await FilesetResolver.forVisionTasks(WASM_URL, true)
      try {
        landmarker = await createLandmarker(vision, 'GPU')
      } catch {
        // A phone whose browser cannot do WebGL-backed inference still gets
        // a tracker, just a slower one — the page's frame-skipping absorbs it.
        landmarker = await createLandmarker(vision, 'CPU')
      }
      self.postMessage({ type: 'ready' })
    } catch (err) {
      self.postMessage({
        type: 'error',
        message: err?.message ? String(err.message) : 'tracker init failed',
      })
    }
    return
  }

  if (msg.type === 'frame') {
    try {
      if (onnxSession) {
        let feet = []
        try {
          feet = await detectOnnx(msg.bitmap)
        } catch {
          // ONNX mid-stream failure → fall back to Pose for this frame rather
          // than wedging the session on one backend forever.
          if (landmarker) {
            const result = landmarker.detectForVideo(msg.bitmap, msg.timestampMs)
            for (const landmarks of result.landmarks ?? []) {
              for (const foot of extractFeet(landmarks)) feet.push(foot)
            }
          }
        }
        self.postMessage({ type: 'pose', feet, timestampMs: msg.timestampMs, backend: 'onnx' })
        return
      }
      if (!landmarker) return
      const result = landmarker.detectForVideo(msg.bitmap, msg.timestampMs)
      const feet = []
      for (const landmarks of result.landmarks ?? []) {
        for (const foot of extractFeet(landmarks)) feet.push(foot)
      }
      self.postMessage({
        type: 'pose',
        feet,
        timestampMs: msg.timestampMs,
      })
    } catch {
      // A dropped frame is silence, never a fault: the page coasts.
      try {
        self.postMessage({ type: 'pose', feet: [], timestampMs: msg.timestampMs })
      } catch {
        // The page went away mid-answer — nothing to do.
      }
    } finally {
      try {
        msg.bitmap?.close?.()
      } catch {
        // Already closed — harmless.
      }
    }
  }
}

/** Run the vendored foot ONNX model over a video frame bitmap. */
const ONNX_SIZE = 640
let onnxCanvas = null
async function detectOnnx(bitmap) {
  const ort = await import('onnxruntime-web')
  if (!onnxCanvas) {
    onnxCanvas = new OffscreenCanvas(ONNX_SIZE, ONNX_SIZE)
  }
  const ctx = onnxCanvas.getContext('2d')
  const bw = bitmap.width
  const bh = bitmap.height
  const scale = Math.max(ONNX_SIZE / bw, ONNX_SIZE / bh)
  const dw = bw * scale
  const dh = bh * scale
  ctx.fillStyle = '#808080'
  ctx.fillRect(0, 0, ONNX_SIZE, ONNX_SIZE)
  ctx.drawImage(bitmap, (ONNX_SIZE - dw) / 2, (ONNX_SIZE - dh) / 2, dw, dh)
  const img = ctx.getImageData(0, 0, ONNX_SIZE, ONNX_SIZE)
  const data = new Float32Array(3 * ONNX_SIZE * ONNX_SIZE)
  for (let i = 0; i < ONNX_SIZE * ONNX_SIZE; i++) {
    data[i] = img.data[i * 4] / 255
    data[ONNX_SIZE * ONNX_SIZE + i] = img.data[i * 4 + 1] / 255
    data[2 * ONNX_SIZE * ONNX_SIZE + i] = img.data[i * 4 + 2] / 255
  }
  const tensor = new ort.Tensor('float32', data, [1, 3, ONNX_SIZE, ONNX_SIZE])
  const out = await onnxSession.run({ images: tensor })
  const first = Object.values(out)[0]
  const rows = []
  // Ultralytics pose output: [1, 11, N] (cx,cy,w,h,heel..,toe..,conf).
  // Normalize box + keypoints back to 0–1 UV of the SOURCE frame by
  // inverting the letterbox above.
  const arr = first.data
  const dims = first.dims
  if (dims.length === 3 && dims[1] >= 11) {
    const n = dims[2]
    for (let i = 0; i < n; i++) {
      const cx = arr[0 * n + i] / ONNX_SIZE
      const cy = arr[1 * n + i] / ONNX_SIZE
      const w = arr[2 * n + i] / ONNX_SIZE
      const h = arr[3 * n + i] / ONNX_SIZE
      const toUV = (px, py) => {
        const lx = px * ONNX_SIZE
        const ly = py * ONNX_SIZE
        const sx = (lx - (ONNX_SIZE - dw) / 2) / scale / bw
        const sy = (ly - (ONNX_SIZE - dh) / 2) / scale / bh
        return [sx, sy]
      }
      const [hx, hy] = toUV(arr[4 * n + i] / ONNX_SIZE, arr[5 * n + i] / ONNX_SIZE)
      const [tx, ty] = toUV(arr[7 * n + i] / ONNX_SIZE, arr[8 * n + i] / ONNX_SIZE)
      rows.push([cx, cy, w, h, hx, hy, arr[6 * n + i], tx, ty, arr[9 * n + i], arr[10 * n + i]])
    }
  }
  return decodeOnnxProposals(rows)
}
