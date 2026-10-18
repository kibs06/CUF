/**
 * Main-thread foot tracker — the fallback when the Web Worker cannot start.
 *
 * The worker (`footTracker.worker.js`) is the fast path: Pose Landmarker's
 * video call is synchronous and blocks its thread. But the worker's wasm
 * bootstrap depends on loader behavior that varies by browser (module
 * workers cannot use `importScripts`, and the script-tag fallback needs a
 * `document` that workers do not have), so on some phones init fails with
 * "ModuleFactory not set." Here on the main thread `document` exists, and
 * the classic loader path works everywhere — at the cost of running each
 * detection on the UI thread. The Lite bundle at ~10fps costs tens of
 * milliseconds per call, acceptable for a beta overlay, and the viewer's
 * frame-skipping absorbs it the same way it absorbs a slow worker.
 *
 * `visionDeps` is injectable so tests can pass fakes without a browser.
 */
import { FilesetResolver, PoseLandmarker } from '@mediapipe/tasks-vision'

import { extractFeet } from './footTryOn.js'

// The Lite pose bundle — the smallest of the three variants, and the right
// first try: a foot is three sparse points, and Full/Heavy buy body detail
// this overlay never reads. Self-hosted under `public/vendor/mediapipe`
// (see `scripts/vendor-trackers.mjs`): same-origin, cached immutably, and
// pinned to bundle version 1, not `latest`, so a model republish cannot
// move the tracking under a shipped page.
export const TRACKER_MODEL_URL = '/vendor/mediapipe/pose_landmarker_lite.task'

// The wasm runtime, vendored from the installed `@mediapipe/tasks-vision`
// package at build time — same version, so the loader and the bundle
// cannot disagree, and no third-party CDN sits in the critical path.
export const TRACKER_WASM_URL = '/vendor/mediapipe'

/**
 * Create a tracker bound to the calling thread. Tries the GPU delegate
 * first, then CPU — a phone without WebGL-backed inference still gets a
 * tracker, just a slower one.
 *
 * Returns `{ delegate, detect(image, timestampMs) -> feet[], close() }`.
 * `image` is anything `detectForVideo` accepts (the viewer passes the
 * `<video>` element directly — no bitmap copy needed on this path).
 */
export async function createMainThreadTracker({
  visionDeps = { FilesetResolver, PoseLandmarker },
  delegateFirst = 'GPU',
} = {}) {
  const vision = await visionDeps.FilesetResolver.forVisionTasks(TRACKER_WASM_URL)
  const delegates = delegateFirst === 'GPU' ? ['GPU', 'CPU'] : ['CPU', 'GPU']
  let lastErr = null
  for (const delegate of delegates) {
    try {
      const landmarker = await visionDeps.PoseLandmarker.createFromOptions(vision, {
        baseOptions: { modelAssetPath: TRACKER_MODEL_URL, delegate },
        runningMode: 'VIDEO',
        numPoses: 2,
        minPoseDetectionConfidence: 0.5,
      })
      return {
        delegate,
        detect(image, timestampMs) {
          const result = landmarker.detectForVideo(image, timestampMs)
          const feet = []
          for (const landmarks of result.landmarks ?? []) {
            for (const foot of extractFeet(landmarks)) feet.push(foot)
          }
          return feet
        },
        close() {
          try {
            landmarker.close()
          } catch {
            // Already closed — harmless.
          }
        },
      }
    } catch (err) {
      lastErr = err
    }
  }
  throw lastErr ?? new Error('tracker init failed')
}
