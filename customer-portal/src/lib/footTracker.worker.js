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
// Single source of truth for the model + wasm URLs — the main-thread
// fallback (`footTrackerMain.js`) owns them so the two paths can never
// download different builds.
import { TRACKER_MODEL_URL as MODEL_URL, TRACKER_WASM_URL as WASM_URL } from './footTrackerMain.js'

let landmarker = null

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
