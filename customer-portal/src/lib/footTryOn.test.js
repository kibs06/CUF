import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  COAST_MS,
  FOOT_SHANK_RATIO,
  MAX_DISAGREE_RATIO,
  blendFootLength,
  estimateFootLengthFromLeg,
  extractFeet,
  extractKnees,
  isPlausiblePlacement,
  pickFoot,
  placementFromFoot,
  poseFromLandmarks,
  shouldDrawShoe,
  smoothAngle,
  smoothPoint,
  toPixels,
} from './footTryOn.js'

function landmarks(overrides = {}) {
  const base = Array.from({ length: 33 }, () => ({ x: 0.5, y: 0.5, visibility: 0 }))
  // Left foot: heel → toe pointing right.
  base[27] = { x: 0.4, y: 0.6, visibility: 0.9 }
  base[29] = { x: 0.4, y: 0.7, visibility: 0.9 }
  base[31] = { x: 0.6, y: 0.7, visibility: 0.9 }
  return Object.assign(base, overrides)
}

test('extractFeet: one entry per visible foot, and only with heel + toe', () => {
  const feet = extractFeet(landmarks())
  assert.equal(feet.length, 1)
  assert.equal(feet[0].side, 'left')

  // Toe hidden → no foot (an axis needs two points).
  const blind = landmarks({ 31: { x: 0.6, y: 0.7, visibility: 0.1 } })
  assert.equal(extractFeet(blind).length, 0)

  // Nothing visible → nothing worn.
  assert.equal(extractFeet([]).length, 0)
})

test('pickFoot: best score wins, with a stick to the previous foot', () => {
  const a = { side: 'left', score: 0.9 }
  const b = { side: 'right', score: 0.95 }
  assert.equal(pickFoot([], 'left'), null)
  assert.equal(pickFoot([a], 'right').side, 'left')
  // Close scores keep the previous foot; a clear winner takes it.
  assert.equal(pickFoot([a, b], 'left').side, 'left')
  assert.equal(
    pickFoot([{ ...a, score: 0.6 }, b], 'left').side,
    'right',
  )
})

test('placementFromFoot: extended heel/toe, pixel length', () => {
  const foot = {
    side: 'left',
    score: 0.9,
    heel: { x: 0.4, y: 0.7 },
    toe: { x: 0.6, y: 0.7 },
  }
  const place = placementFromFoot(foot, 1000, 500)
  // Raw axis is 200px; extended by HEEL_BACK 0.16 + TOE 0.28 → 288px.
  assert.equal(place.lengthPx, 288)
  // Heel pulled back, toe pushed forward along +x.
  assert.ok(place.heel.x < 400)
  assert.ok(place.toe.x > 600)
  assert.equal(place.heel.y, 350)
  assert.ok(Math.abs(place.angleRad) < 1e-9)

  // A zero-length axis is not a placement.
  const same = { ...foot, toe: { ...foot.heel } }
  assert.equal(placementFromFoot(same, 1000, 500), null)
})

test('isPlausiblePlacement: rejects the tiny shin axis, keeps feet', () => {
  const foot = {
    side: 'left',
    score: 0.9,
    heel: { x: 0.4, y: 0.7 },
    toe: { x: 0.6, y: 0.7 },
  }
  assert.equal(isPlausiblePlacement(placementFromFoot(foot, 1000, 500), 1000, 500), true)
  // Collapsed 20px axis on a 1000px frame → shin false positive.
  const tiny = {
    side: 'left',
    score: 0.9,
    heel: { x: 0.5, y: 0.3 },
    toe: { x: 0.51, y: 0.32 },
  }
  assert.equal(isPlausiblePlacement(placementFromFoot(tiny, 1000, 800), 1000, 800), false)
  assert.equal(isPlausiblePlacement(null, 1000, 800), false)
})

test('toPixels: normalized UV into video pixels', () => {
  assert.deepEqual(toPixels({ x: 0.25, y: 0.5 }, 800, 600), { x: 200, y: 300 })
})

test('smoothPoint and smoothAngle: ease toward the new reading', () => {
  assert.deepEqual(smoothPoint(null, { x: 1, y: 2 }), { x: 1, y: 2 })
  assert.deepEqual(smoothPoint({ x: 0, y: 0 }, { x: 10, y: 0 }, 0.5), {
    x: 5,
    y: 0,
  })
  assert.equal(smoothAngle(null, 1), 1)
  // Across the ±π seam it turns the short way.
  const wrapped = smoothAngle(Math.PI - 0.1, -Math.PI + 0.1, 1)
  assert.ok(Math.abs(wrapped - (Math.PI + 0.1)) < 0.2 || Math.abs(wrapped + Math.PI - 0.1) < 0.2)
})

test('shouldDrawShoe: now, or recently — never long-lost', () => {
  assert.equal(shouldDrawShoe({ seenNow: true, lastSeenMs: 0, nowMs: 99999 }), true)
  assert.equal(
    shouldDrawShoe({ seenNow: false, lastSeenMs: 1000, nowMs: 1000 + COAST_MS }),
    true,
  )
  assert.equal(
    shouldDrawShoe({ seenNow: false, lastSeenMs: 1000, nowMs: 1000 + COAST_MS + 1 }),
    false,
  )
  assert.equal(
    shouldDrawShoe({ seenNow: false, lastSeenMs: NaN, nowMs: 2000 }),
    false,
  )
})

test('extractKnees: knees gated at 0.5, null per missing side', () => {
  const knees = extractKnees(landmarks())
  // The shared fixture helper sets no knee landmarks: both null, never thrown.
  assert.equal(knees.left, null)
  assert.equal(knees.right, null)

  const bent = landmarks({
    25: { x: 0.5, y: 0.2, visibility: 0.9 },
    26: { x: 0.55, y: 0.25, visibility: 0.4 },
  })
  assert.deepEqual(extractKnees(bent).left, { x: 0.5, y: 0.2, score: 0.9 })
  // 0.4 is above the foot gate (0.3) but below the stricter knee gate.
  assert.equal(extractKnees(bent).right, null)
})

test('estimateFootLengthFromLeg: 400px shank reads 250.4px', () => {
  const prior = estimateFootLengthFromLeg({
    knee: { x: 0.5, y: 0.2, score: 0.9 },
    ankle: { x: 0.5, y: 0.6, score: 0.7 },
    videoW: 1000,
    videoH: 1000,
  })
  // hypot() lands within float dust of 400.
  assert.ok(Math.abs(prior.shankPx - 400) < 1e-9)
  // The module scales the measured shank (400 up to hypot dust).
  assert.ok(Math.abs(prior.lengthPx - 250.4) < 1e-9)
  // Confidence is the weaker of the two ends.
  assert.equal(prior.confidence, 0.7)
})

test('estimateFootLengthFromLeg: null without both ends', () => {
  const ankle = { x: 0.5, y: 0.6, score: 0.9 }
  assert.equal(
    estimateFootLengthFromLeg({ knee: null, ankle, videoW: 1000, videoH: 1000 }),
    null,
  )
  assert.equal(
    estimateFootLengthFromLeg({
      knee: { x: 0.5, y: 0.2, score: 0.9 },
      ankle,
      videoW: 0,
      videoH: 1000,
    }),
    null,
  )
})

test('blendFootLength: no prior passes the axis through untouched', () => {
  assert.deepEqual(
    blendFootLength({ axisLengthPx: 150, legPriorPx: null, legConfidence: 0 }),
    { lengthPx: 150, source: 'axis', disagree: false },
  )
  assert.deepEqual(
    blendFootLength({ axisLengthPx: 150, legPriorPx: 250, legConfidence: 0 }),
    { lengthPx: 150, source: 'axis', disagree: false },
  )
  assert.equal(blendFootLength({ axisLengthPx: 0, legPriorPx: 250, legConfidence: 0.8 }), null)
})

test('blendFootLength: agreeing estimates blend by confidence', () => {
  // 150 vs 200: ratio 1.33 < 1.8, weights 0.5/0.5 -> midpoint.
  const out = blendFootLength({
    axisLengthPx: 150,
    axisConfidence: 0.5,
    legPriorPx: 200,
    legConfidence: 0.5,
  })
  assert.equal(out.source, 'blend')
  assert.equal(out.disagree, false)
  assert.equal(out.lengthPx, 175)
})

test('blendFootLength: collapsed axis loses to the leg with a flag', () => {
  // Fixture-shaped collapse: smoothed axis 119px against a 250px leg prior.
  const out = blendFootLength({
    axisLengthPx: 119,
    axisConfidence: 0.4,
    legPriorPx: 250.4,
    legConfidence: 0.7,
  })
  assert.equal(out.source, 'leg-override')
  assert.equal(out.disagree, true)
  assert.equal(out.lengthPx, 250.4)
})

test('blendFootLength: ratio exactly 1.8 still blends, above overrides', () => {
  const atEdge = blendFootLength({
    axisLengthPx: 100,
    axisConfidence: 0.5,
    legPriorPx: 100 * MAX_DISAGREE_RATIO,
    legConfidence: 0.5,
  })
  assert.equal(atEdge.source, 'blend')

  const overEdge = blendFootLength({
    axisLengthPx: 100,
    axisConfidence: 0.9,
    legPriorPx: 100 * MAX_DISAGREE_RATIO + 0.01,
    legConfidence: 0.1,
  })
  // Even a confident axis loses past the edge: collapse is the known failure.
  assert.equal(overEdge.source, 'leg-override')
  assert.equal(overEdge.disagree, true)
})

test('poseFromLandmarks: feet plus per-side knees, nulls when missing', () => {
  // One pose per list entry (the worker passes `result.landmarks`).
  const { feet, knees } = poseFromLandmarks([landmarks()])
  assert.equal(feet.length, 1)
  assert.equal(knees.left, null)
  assert.equal(knees.right, null)

  const withKnee = landmarks({ 25: { x: 0.5, y: 0.2, visibility: 0.9 } })
  const out = poseFromLandmarks([withKnee])
  assert.deepEqual(out.knees.left, { x: 0.5, y: 0.2, score: 0.9 })
  assert.equal(out.knees.right, null)
  assert.deepEqual(poseFromLandmarks([]), { feet: [], knees: { left: null, right: null } })
})

test('blendFootLength: no-knee passthrough is the identical double (viewer byte-identical)', () => {
  // An awkward non-round double must flow through with zero arithmetic so
  // the viewer lerp computes bit-for-bit what the old code computed.
  const axis = 150.123456789
  const out = blendFootLength({ axisLengthPx: axis, axisConfidence: 0.4, legPriorPx: null, legConfidence: 0 })
  assert.equal(out.lengthPx, axis)
  assert.equal(out.source, 'axis')
})

test('viewer pipeline: knee-visible frame blends, collapsed axis overrides, no knee passes through', () => {
  // The exact call sequence from FootTryOnViewer.jsx on each pose message,
  // fed with leg-consistent synthetic landmarks (1000x1000 frame). This is
  // the blend path firing from detector-shaped output — the closest the
  // unit suite can come to a live knee-visible frame.
  const vw = 1000
  const vh = 1000
  function runFrame(lm) {
    const { feet, knees } = poseFromLandmarks([lm])
    const foot = pickFoot(feet, null)
    assert.ok(foot, 'expected a worn foot')
    const place = placementFromFoot(foot, vw, vh)
    assert.ok(place && isPlausiblePlacement(place, vw, vh), 'expected a drawable placement')
    const knee = knees[foot.side] ?? null
    const prior = estimateFootLengthFromLeg({
      knee,
      ankle: foot.ankle,
      videoW: vw,
      videoH: vh,
    })
    const blended = blendFootLength({
      axisLengthPx: place.lengthPx,
      axisConfidence: foot.score ?? 0.5,
      legPriorPx: prior?.lengthPx ?? null,
      legConfidence: prior?.confidence ?? 0,
    })
    return { place, blended }
  }

  // Agreeing estimators: 400px shank -> 250.4px prior against a 174px raw
  // axis -> 250.56px extended. Ratio ~1.001, so confidence weights decide.
  const agree = landmarks({
    25: { x: 0.5, y: 0.2, visibility: 0.9 },
    27: { x: 0.5, y: 0.6, visibility: 0.8 },
    29: { x: 0.41, y: 0.7, visibility: 0.9 },
    31: { x: 0.584, y: 0.7, visibility: 0.9 },
  })
  const { blended: blendOut } = runFrame(agree)
  assert.equal(blendOut.source, 'blend')
  assert.equal(blendOut.disagree, false)
  assert.ok(blendOut.lengthPx > 250.4 && blendOut.lengthPx < 250.56)

  // Collapsed axis that still clears the plausibility gate: 90px raw ->
  // 129.6px extended against the same 250.4px prior (ratio ~1.93), so the
  // leg wins and the disagree flag is set for the debug overlay.
  const collapsed = landmarks({
    25: { x: 0.5, y: 0.2, visibility: 0.9 },
    27: { x: 0.5, y: 0.6, visibility: 0.8 },
    29: { x: 0.45, y: 0.7, visibility: 0.9 },
    31: { x: 0.54, y: 0.7, visibility: 0.9 },
  })
  const { blended: overOut } = runFrame(collapsed)
  assert.equal(overOut.source, 'leg-override')
  assert.equal(overOut.disagree, true)
  assert.ok(Math.abs(overOut.lengthPx - 400 * FOOT_SHANK_RATIO) < 1e-9)

  // Same agreeing frame with the knee hidden: the prior is null and the
  // axis double flows through untouched, exactly as pre-Phase-3 code drew.
  const noKnee = landmarks({
    27: { x: 0.5, y: 0.6, visibility: 0.8 },
    29: { x: 0.41, y: 0.7, visibility: 0.9 },
    31: { x: 0.584, y: 0.7, visibility: 0.9 },
  })
  const { place, blended: axisOut } = runFrame(noKnee)
  assert.equal(axisOut.source, 'axis')
  assert.equal(axisOut.lengthPx, place.lengthPx)
})
