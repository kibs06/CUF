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

// The Lite pose bundle — the smallest of the three variants, and the right
// first try: a foot is three sparse points, and Full/Heavy buy body detail
// this overlay never reads. Pinned to bundle version 1, not `latest`, so a
// model republish cannot move the tracking under a shipped page.
const MODEL_URL =
  'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.taskle'

// The wasm runtime matching the installed `@mediapipe/tasks-vision` —
// same version, so the loader and the bundle cannot disagree. The second
// `forVisionTasks` argument selects the ESM loader
// (`vision_wasm_module_internal.js`): this worker runs as `{ type: 'module' }`
// where `importScripts` does not exist, so the classic UMD loader can never
// install `self.ModuleFactory` and init fails with "ModuleFactory not set.".
const WASM_URL =
  'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.1.1/wasm'

let landmarker = null

async function createLandmarker(vision, delegate) {
  return PoseLandmarker.createFromOptions(vision, {
    baseOptions: { modelAssetPath: MODEL_URL, delegate },
    runningMode: 'VIDEO',
    numPoses: 2,
    minPoseDetectionConfidence: 0.5,
  })
}

self.onmessage = async (event) => {
  const msg = event.data
  if (!msg || typeof msg !== 'object') return

  if (msg.type === 'init') {
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
