import { describe, it } from 'node:test'
import assert from 'node:assert/strict'

import {
  FOOT_SCANS_BUCKET,
  bytesProgress,
  frameObjectName,
  jobFramesPrefix,
  jobMeshPath,
  retryable,
  uploadedFrameSizes,
} from './footScanJobs.js'

describe('foot scan storage contract', () => {
  it('uses the private foot-scans bucket', () => {
    assert.equal(FOOT_SCANS_BUCKET, 'foot-scans')
  })

  it('scopes frames under the owner and job', () => {
    assert.equal(jobFramesPrefix('uid-1', 'job-9'), 'uid-1/job-9/frames')
  })

  it('puts the mesh beside the frames', () => {
    assert.equal(jobMeshPath('uid-1', 'job-9'), 'uid-1/job-9/mesh/foot.glb')
  })

  it('parses remote listing into index sizes, ignoring strangers', () => {
    const sizes = uploadedFrameSizes([
      { name: 'frame-002-a012.jpg', size: 8000 },
      { name: 'frame-010-a072.jpg', size: 9000 },
      { name: 'thumb.png', size: 100 },
      { name: 'frame-2-a12.jpg', size: 50 },
    ])
    assert.equal(sizes.size, 2)
    assert.equal(sizes.get(2), 8000)
    assert.equal(sizes.get(10), 9000)
  })

  it('clamps byte progress to 0–1', () => {
    assert.equal(bytesProgress(50, 100), 0.5)
    assert.equal(bytesProgress(0, 100), 0)
    assert.equal(bytesProgress(200, 100), 1)
    assert.equal(bytesProgress(10, 0), 0)
  })

  it('retries a flaky upload then succeeds', async () => {
    let calls = 0
    const result = await retryable(
      async () => {
        calls += 1
        if (calls < 3) throw new Error('drop')
        return 'ok'
      },
      { attempts: 3, sleep: async () => {} },
    )
    assert.equal(result, 'ok')
    assert.equal(calls, 3)
  })

  it('gives up after the attempt budget', async () => {
    let calls = 0
    await assert.rejects(
      retryable(
        async () => {
          calls += 1
          throw new Error(`drop ${calls}`)
        },
        { attempts: 2, sleep: async () => {} },
      ),
      /drop 2/,
    )
    assert.equal(calls, 2)
  })

  it('names frames so they sort in capture order', () => {
    const names = [
      frameObjectName(2, 12),
      frameObjectName(10, 72),
      frameObjectName(1, 6),
    ]
    assert.deepEqual([...names].sort(), [
      'frame-001-a006.jpg',
      'frame-002-a012.jpg',
      'frame-010-a072.jpg',
    ])
  })
})
