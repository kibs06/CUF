import { describe, it } from 'node:test'
import assert from 'node:assert/strict'

import {
  CAPTURE_INTERVAL_MS,
  HEADING_DEADBAND_DEG,
  MIN_COVERAGE_DEG,
  MIN_FRAME_COUNT,
  TARGET_FRAME_COUNT,
  angleCoverageDeg,
  compassHeadingFrom,
  createOrbitTracker,
  isFrameUsable,
  isSweepUsable,
  lumaStats,
  orbitAngleFor,
  pickWidestRearLens,
  sweepFailureMessage,
  unwrapDelta,
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

describe('compassHeadingFrom', () => {
  it('prefers the iOS compass heading and normalizes it', () => {
    assert.equal(compassHeadingFrom({ webkitCompassHeading: 370 }), 10)
    assert.equal(
      compassHeadingFrom({ webkitCompassHeading: 90, alpha: 270, absolute: true }),
      90,
    )
  })

  it('mirrors absolute Android alpha, rejects relative alphas', () => {
    assert.equal(compassHeadingFrom({ alpha: 90, absolute: true }), 270)
    assert.equal(compassHeadingFrom({ alpha: 90, absolute: false }), null)
    assert.equal(compassHeadingFrom({}), null)
  })
})

describe('unwrapDelta', () => {
  it('takes the short way across north', () => {
    assert.equal(unwrapDelta(350, 10), 20)
    assert.equal(unwrapDelta(10, 350), -20)
    assert.equal(unwrapDelta(90, 180), 90)
  })

  it('treats garbage as no motion', () => {
    assert.equal(unwrapDelta(NaN, 10), 0)
    assert.equal(unwrapDelta(10, null), 0)
  })
})

describe('createOrbitTracker', () => {
  it('degrades to the time prior when the compass is absent', () => {
    const tracker = createOrbitTracker({ sweepDurationMs: 20000 })
    const tags = [0, 5000, 10000, 20000].map((t) =>
      tracker.push({ elapsedMs: t, headingDeg: null }),
    )
    assert.deepEqual(tags.map((r) => r.angle), [0, 90, 180, 360 % 360])
    assert.ok(tags.every((r) => r.source === 'time'))
    assert.equal(tracker.headingShare(), 0)
  })

  it('tags uneven pace truthfully where time tags lie', () => {
    // Realistic 400 ms ticks. Fast first quarter (180° of travel in 5 s),
    // slow remainder — the walker the time prior mislabels.
    const headingAt = (t) => (t <= 5000 ? 180 * (t / 5000) : 180 + 180 * ((t - 5000) / 15000))
    const tracker = createOrbitTracker({ sweepDurationMs: 20000 })
    const tagged = []
    for (let t = 0; t <= 20000; t += CAPTURE_INTERVAL_MS) {
      tagged.push(tracker.push({ elapsedMs: t, headingDeg: headingAt(t) }).angle)
    }
    // Mid-sprint the feet are at ~86° while the clock would claim ~43°.
    const sprintTick = tagged[Math.round(2400 / CAPTURE_INTERVAL_MS)]
    assert.ok(Math.abs(sprintTick - 86) <= 3, `got ${sprintTick}`)
    assert.ok(Math.abs(orbitAngleFor(2400, 20000) - headingAt(2400)) > 35)
    // Full circle travelled at capture density → the 300° gate passes.
    assert.ok(angleCoverageDeg(tagged) >= MIN_COVERAGE_DEG, `coverage ${angleCoverageDeg(tagged)}`)
    assert.equal(tracker.headingShare(), 1)
  })

  it('fills compass gaps with time and re-anchors without double counting', () => {
    const tracker = createOrbitTracker({ sweepDurationMs: 20000 })
    tracker.push({ elapsedMs: 0, headingDeg: 0 })
    tracker.push({ elapsedMs: 1000, headingDeg: 18 })
    // Compass drops for 1 s: the clock advances ~18° at the prior rate,
    // then the heading re-anchors — counted once, never doubled.
    tracker.push({ elapsedMs: 2000, headingDeg: null })
    const resumed = tracker.push({ elapsedMs: 3000, headingDeg: 54 })
    assert.ok(Math.abs(resumed.angle - 36) <= 1, `got ${resumed.angle}`)
    assert.equal(resumed.source, 'heading')
    assert.ok(tracker.headingShare() < 1 && tracker.headingShare() > 0)
  })

  it('wraps across north and ignores sub-deadband jitter', () => {
    const tracker = createOrbitTracker({ sweepDurationMs: 20000 })
    tracker.push({ elapsedMs: 0, headingDeg: 350 })
    const crossed = tracker.push({ elapsedMs: 400, headingDeg: 10 })
    assert.equal(crossed.angle, 20)
    const still = tracker.push({ elapsedMs: 800, headingDeg: 10 + HEADING_DEADBAND_DEG / 2 })
    assert.equal(still.angle, 20)
  })
})

describe('pickWidestRearLens', () => {
  it('prefers the ultrawide rear lens', () => {
    const devices = [
      { deviceId: 'tele', label: 'Back Tele Camera', kind: 'videoinput' },
      { deviceId: 'ultra', label: 'Back Ultra Wide Camera', kind: 'videoinput' },
      { deviceId: 'front', label: 'Front Camera', kind: 'videoinput' },
      { deviceId: 'mic', label: '', kind: 'audioinput' },
    ]
    assert.equal(pickWidestRearLens(devices), 'ultra')
  })

  it('falls back to the first rear lens, never front unless forced', () => {
    const devices = [
      { deviceId: 'main', label: 'Back Camera', kind: 'videoinput' },
      { deviceId: 'front', label: 'Front Camera', kind: 'videoinput' },
    ]
    assert.equal(pickWidestRearLens(devices), 'main')
    assert.equal(
      pickWidestRearLens([{ deviceId: 'f', label: 'Front', kind: 'videoinput' }]),
      'f',
    )
  })

  it('returns null with no usable camera', () => {
    assert.equal(pickWidestRearLens([]), null)
    assert.equal(pickWidestRearLens([{ deviceId: '', label: 'x', kind: 'videoinput' }]), null)
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
