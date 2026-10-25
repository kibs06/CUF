import { describe, it } from 'node:test'
import assert from 'node:assert/strict'

import {
  CAPTURE_INTERVAL_MS,
  MIN_COVERAGE_DEG,
  MIN_FRAME_COUNT,
  TARGET_FRAME_COUNT,
  angleCoverageDeg,
  isFrameUsable,
  isSweepUsable,
  lumaStats,
  orbitAngleFor,
  sweepFailureMessage,
} from './footScanCapture.js'

describe('orbitAngleFor', () => {
  it('maps elapsed time linearly to 0–360', () => {
    assert.equal(orbitAngleFor(0), 0)
    assert.equal(orbitAngleFor(10000, 20000), 180)
    assert.equal(orbitAngleFor(20000, 20000), 360)
  })

  it('clamps past the sweep end and rejects garbage', () => {
    assert.equal(orbitAngleFor(99999, 20000), 360)
    assert.equal(orbitAngleFor(-5, 20000), 0)
    assert.equal(orbitAngleFor(NaN, 20000), 0)
  })
})

describe('angleCoverageDeg', () => {
  it('reports near-full coverage for an even ring', () => {
    // Discrete samples: 12 frames at 30° leave one 30° interval
    // unaccounted — 330, and a 50-frame sweep reads ~353. The 300°
    // gate sits well below either.
    const angles = Array.from({ length: 12 }, (_, i) => i * 30)
    assert.equal(angleCoverageDeg(angles), 330)
  })

  it('subtracts the largest gap (0–180 arc → 180)', () => {
    assert.equal(angleCoverageDeg([0, 90, 180]), 180)
  })

  it('needs at least two angles', () => {
    assert.equal(angleCoverageDeg([]), 0)
    assert.equal(angleCoverageDeg([45]), 0)
  })

  it('wraps angles into 0–360', () => {
    // 350° and 370°(=10°) are 20° apart — a 20° arc, not the rest.
    assert.equal(angleCoverageDeg([350, 370]), 20)
  })
})

describe('isFrameUsable', () => {
  it('accepts a normal frame', () => {
    assert.equal(isFrameUsable({ sharpness: 0.5, brightness: 0.5 }), true)
  })

  it('rejects blurry, dark, blown-out, or missing signals', () => {
    assert.equal(isFrameUsable({ sharpness: 0.05, brightness: 0.5 }), false)
    assert.equal(isFrameUsable({ sharpness: 0.5, brightness: 0.05 }), false)
    assert.equal(isFrameUsable({ sharpness: 0.5, brightness: 0.99 }), false)
    assert.equal(isFrameUsable({}), false)
  })
})

describe('isSweepUsable', () => {
  it('passes at exactly the minimums', () => {
    assert.equal(
      isSweepUsable({ frameCount: MIN_FRAME_COUNT, coverageDeg: MIN_COVERAGE_DEG }),
      true,
    )
  })

  it('fails when either gate misses', () => {
    assert.equal(
      isSweepUsable({ frameCount: MIN_FRAME_COUNT - 1, coverageDeg: 360 }),
      false,
    )
    assert.equal(
      isSweepUsable({ frameCount: TARGET_FRAME_COUNT, coverageDeg: 120 }),
      false,
    )
  })

  it('capture interval matches the frame budget', () => {
    assert.equal(CAPTURE_INTERVAL_MS * TARGET_FRAME_COUNT <= 20000, true)
  })
})

describe('lumaStats', () => {
  it('reads brightness from a flat field', () => {
    const pixels = new Array(16 * 4).fill(128)
    const { brightness, sharpness } = lumaStats(pixels)
    assert.ok(Math.abs(brightness - 128 / 255) < 0.01)
    assert.equal(sharpness, 0)
  })

  it('reads sharpness from a split field', () => {
    const pixels = []
    for (let i = 0; i < 64; i++) {
      const v = i < 32 ? 40 : 220
      pixels.push(v, v, v, 255)
    }
    const { sharpness } = lumaStats(pixels)
    assert.ok(sharpness > 0.15)
  })

  it('rejects tiny buffers', () => {
    assert.deepEqual(lumaStats([]), { brightness: 0, sharpness: 0 })
  })
})

describe('sweepFailureMessage', () => {
  it('names the shortfall in plain words', () => {
    assert.match(sweepFailureMessage({ frameCount: 5, coverageDeg: 360 }), /steadier/i)
    assert.match(
      sweepFailureMessage({ frameCount: 45, coverageDeg: 120 }),
      /all the way around/i,
    )
  })
})
