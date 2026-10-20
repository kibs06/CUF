import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  COAST_MS,
  FOOT_SHANK_RATIO,
  HANDOFF_MS,
  MAX_DISAGREE_RATIO,
  STEPIN_MAX_VELOCITY_PX_S,
  STEPIN_OVERLAP_RATIO,
  STEPIN_SUSTAIN_FRAMES,
  axisOverlapRatio,
  blendFootLength,
  estimateFootLengthFromLeg,
  extractFeet,
  extractKnees,
  handoffPose,
  isPlausiblePlacement,
  isStagedDrawable,
  pickFoot,
  placementFromFoot,
  poseFromLandmarks,
  shouldDrawShoe,
  smoothAngle,
  smoothPoint,
  stepInGate,
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

test('axisOverlapRatio: coincident axes read 1, far axes read 0', () => {
  const heel = { x: 410, y: 700 }
  const toe = { x: 584, y: 700 }
  assert.equal(axisOverlapRatio(heel, toe, heel, toe), 1)
  const far = axisOverlapRatio(heel, toe, { x: 410, y: 100 }, { x: 584, y: 100 })
  assert.equal(far, 0)
  // Tolerance scales with stage size: the same pixel offset overlaps a
  // big stage and misses a small one.
  const offset = { x: 470, y: 790 }
  const toeOff = { x: 644, y: 790 }
  assert.ok(axisOverlapRatio(offset, toeOff, heel, toe) < STEPIN_OVERLAP_RATIO)
  // Bad input never claims overlap.
  assert.equal(axisOverlapRatio(null, toe, heel, toe), 0)
  assert.equal(axisOverlapRatio(heel, toe, heel, heel), 0)
})

test('stepInGate: dwells to armed, resets on leave or speed', () => {
  const staged = {
    footHeel: { x: 410, y: 700 },
    footToe: { x: 584, y: 700 },
    stageHeel: { x: 410, y: 700 },
    stageToe: { x: 584, y: 700 },
    footVelocityPxPerSec: 0,
  }
  // A brush-past (one overlapping frame) must not attach.
  let g = stepInGate(staged)
  assert.equal(g.armed, false)
  assert.equal(g.overlapFrames, 1)
  assert.equal(g.overlapRatio, 1)
  // Dwelling sustains to armed exactly at the threshold.
  for (let i = 1; i < STEPIN_SUSTAIN_FRAMES; i += 1) {
    g = stepInGate({ ...staged, overlapFrames: g.overlapFrames })
    assert.equal(g.armed, i + 1 >= STEPIN_SUSTAIN_FRAMES)
  }
  // A fast sweep past the shoe never arms, however overlapped.
  g = stepInGate({ ...staged, footVelocityPxPerSec: STEPIN_MAX_VELOCITY_PX_S + 1 })
  assert.equal(g.armed, false)
  assert.equal(g.overlapFrames, 0)
  // Leaving resets the dwell counter.
  g = stepInGate({
    ...staged,
    overlapFrames: STEPIN_SUSTAIN_FRAMES - 1,
    footHeel: { x: 0, y: 0 },
    footToe: { x: 10, y: 0 },
  })
  assert.equal(g.armed, false)
  assert.equal(g.overlapFrames, 0)
  // Blind input stays shut.
  g = stepInGate({ ...staged, footHeel: null })
  assert.equal(g.armed, false)
  g = stepInGate({ ...staged, footVelocityPxPerSec: NaN })
  assert.equal(g.armed, false)
})

test('handoffPose: stage at t=0, foot at t=1, between with no pop', () => {
  const from = { heel: { x: 500, y: 820 }, toe: { x: 500, y: 480 }, angle: -Math.PI / 2, length: 489.6 }
  const to = { heel: { x: 410, y: 700 }, toe: { x: 584, y: 700 }, angle: 0, length: 250.56 }
  const start = handoffPose({ from, to, t: 0 })
  assert.deepEqual(start.heel, from.heel)
  assert.deepEqual(start.toe, from.toe)
  assert.equal(start.length, from.length)
  const end = handoffPose({ from, to, t: 1 })
  assert.deepEqual(end.heel, to.heel)
  assert.equal(end.length, to.length)
  // Smoothstep midpoint eases (0.5 -> 0.5 exactly at the middle, and the
  // quarter point lags linear: no jump, no overshoot past either end).
  const mid = handoffPose({ from, to, t: 0.5 })
  assert.ok(mid.heel.x < from.heel.x && mid.heel.x > to.heel.x)
  assert.ok(mid.length > to.length && mid.length < from.length)
  const q = handoffPose({ from, to, t: 0.25 })
  assert.ok(q.length > mid.length)
  assert.ok(Number.isFinite(q.length) && q.length > 0)
  // Out-of-range progress clamps instead of extrapolating.
  assert.deepEqual(handoffPose({ from, to, t: -2 }).heel, from.heel)
  assert.deepEqual(handoffPose({ from, to, t: 5 }).heel, to.heel)
  // Garbage in draws the target, never NaN on screen.
  const bad = handoffPose({ from: { heel: null }, to, t: 0.5 })
  assert.deepEqual(bad.heel, to.heel)
  // The handoff window is a real, short duration.
  assert.ok(HANDOFF_MS >= 200 && HANDOFF_MS <= 500)
})

test('isStagedDrawable: staged waits visibly, worn follows tracking', () => {
  // The regression this guards: auto-stage draws the shoe, then the first
  // empty pose message (lastSeen still NaN) hid it again because only the
  // coast check fed `seenNow`. Staged must draw regardless of coast state.
  assert.equal(isStagedDrawable({ manual: true }), true)
  assert.equal(isStagedDrawable({ manual: false }), false)
  assert.equal(isStagedDrawable({}), false)
  assert.equal(isStagedDrawable(), false)
})

test('step-in sequence: slide in, dwell, arm, leave, reset', () => {
  // Detector-rate frames (~100ms) through the real gate entry, with
  // velocity from midpoint displacement exactly as the viewer computes it.
  const stage = { heel: { x: 500, y: 820 }, toe: { x: 500, y: 480 } }
  const axisAt = (cx, cy) => ({
    heel: { x: cx - 87, y: cy },
    toe: { x: cx + 87, y: cy },
  })
  let frames = 0
  let prev = null
  const step = (cx, cy) => {
    const a = axisAt(cx, cy)
    const vel = prev ? Math.hypot(cx - prev[0], cy - prev[1]) / 100 * 1000 : 0
    prev = [cx, cy]
    const g = stepInGate({
      footHeel: a.heel,
      footToe: a.toe,
      stageHeel: stage.heel,
      stageToe: stage.toe,
      footVelocityPxPerSec: vel,
      overlapFrames: frames,
    })
    frames = g.overlapFrames
    return g
  }
  // Far away: no overlap, counter stays zero.
  assert.equal(step(200, 700).overlapFrames, 0)
  // Fast jump into the shoe: overlapped but too fast, counter resets.
  let g = step(470, 700)
  assert.equal(g.armed, false)
  assert.equal(g.overlapFrames, 0)
  // Slow settle (<=12px per 100ms frame stays under the velocity cap):
  // dwell accumulates and arms exactly at the sustain threshold.
  const settle = [[478, 700], [486, 700], [494, 700], [500, 700], [500, 700], [500, 700]]
  settle.forEach(([x, y], i) => {
    g = step(x, y)
    assert.equal(g.armed, i + 1 >= STEPIN_SUSTAIN_FRAMES)
  })
  // Leaving resets the dwell so a later pass must qualify again.
  g = step(200, 700)
  assert.equal(g.armed, false)
  assert.equal(g.overlapFrames, 0)
})
