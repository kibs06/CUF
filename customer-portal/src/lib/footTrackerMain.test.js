import { strict as assert } from 'node:assert'
import { describe, it } from 'node:test'

import {
  createMainThreadTracker,
  TRACKER_MODEL_URL,
  TRACKER_WASM_URL,
} from './footTrackerMain.js'

function fakeLandmarker(landmarks) {
  return {
    detectForVideo: () => ({ landmarks }),
    closeCalls: 0,
    close() {
      this.closeCalls += 1
    },
  }
}

// Landmarks with a visible heel (29) and toe (31) on the left foot.
function leftFootLandmarks() {
  const landmarks = Array.from({ length: 33 }, () => ({ x: 0, y: 0, visibility: 0 }))
  landmarks[29] = { x: 0.4, y: 0.7, visibility: 0.9 }
  landmarks[31] = { x: 0.4, y: 0.9, visibility: 0.8 }
  return [landmarks]
}

function depsWith({ landmarker, failFirst = false } = {}) {
  let calls = 0
  return {
    calls: () => calls,
    FilesetResolver: {
      forVisionTasks: async (url) => {
        assert.equal(url, TRACKER_WASM_URL)
        return { vision: true }
      },
    },
    PoseLandmarker: {
      createFromOptions: async (vision, options) => {
        calls += 1
        assert.deepEqual(vision, { vision: true })
        assert.equal(options.baseOptions.modelAssetPath, TRACKER_MODEL_URL)
        assert.equal(options.runningMode, 'VIDEO')
        if (failFirst && calls === 1) throw new Error('GPU unavailable')
        return landmarker
      },
    },
  }
}

describe('footTrackerMain', () => {
  it('detects feet on the first (GPU) delegate', async () => {
    const marker = fakeLandmarker(leftFootLandmarks())
    const deps = depsWith({ landmarker: marker })
    const tracker = await createMainThreadTracker({ visionDeps: deps })
    assert.equal(tracker.delegate, 'GPU')
    const feet = tracker.detect({}, 100)
    assert.equal(feet.length, 1)
    assert.equal(feet[0].side, 'left')
    tracker.close()
    assert.equal(marker.closeCalls, 1)
  })

  it('falls back to CPU when GPU creation fails', async () => {
    const marker = fakeLandmarker(leftFootLandmarks())
    const deps = depsWith({ landmarker: marker, failFirst: true })
    const tracker = await createMainThreadTracker({ visionDeps: deps })
    assert.equal(tracker.delegate, 'CPU')
    assert.equal(deps.calls(), 2)
    assert.equal(tracker.detect({}, 100).length, 1)
  })

  it('returns no feet when nothing is visible', async () => {
    const marker = fakeLandmarker([Array.from({ length: 33 }, () => ({ x: 0, y: 0, visibility: 0 }))])
    const deps = depsWith({ landmarker: marker })
    const tracker = await createMainThreadTracker({ visionDeps: deps })
    assert.deepEqual(tracker.detect({}, 100), [])
  })

  it('throws when every delegate fails', async () => {
    const deps = {
      FilesetResolver: { forVisionTasks: async () => ({}) },
      PoseLandmarker: {
        createFromOptions: async () => {
          throw new Error('no backend')
        },
      },
    }
    await assert.rejects(() => createMainThreadTracker({ visionDeps: deps }), /no backend/)
  })
})
