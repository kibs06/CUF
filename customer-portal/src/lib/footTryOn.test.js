import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  COAST_MS,
  extractFeet,
  pickFoot,
  placementFromFoot,
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

test('placementFromFoot: heel anchor, toe direction, pixel length', () => {
  const foot = {
    side: 'left',
    score: 0.9,
    heel: { x: 0.4, y: 0.7 },
    toe: { x: 0.6, y: 0.7 },
  }
  const place = placementFromFoot(foot, 1000, 500)
  assert.deepEqual(place.heel, { x: 400, y: 350 })
  assert.equal(place.lengthPx, 200)
  assert.ok(Math.abs(place.angleRad) < 1e-9)

  // A zero-length axis is not a placement.
  const same = { ...foot, toe: { ...foot.heel } }
  assert.equal(placementFromFoot(same, 1000, 500), null)
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
