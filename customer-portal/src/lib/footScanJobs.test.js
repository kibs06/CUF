import { describe, it } from 'node:test'
import assert from 'node:assert/strict'

import {
  FOOT_SCANS_BUCKET,
  frameObjectName,
  jobFramesPrefix,
  jobMeshPath,
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
