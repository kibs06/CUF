import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  DEFAULT_FORWARD_AXIS,
  FORWARD_YAW,
  computeModelNormalization,
  normalizeForwardAxis,
  normalizeModelScale,
} from './modelNormalization.js'

// Post-yaw box of a +Z shoe: toe at high z (0..0.27), sole at min.y,
// centered x. For a −Z-authored shoe the viewer yaws it by PI first, so
// by measure time its box looks like this too (heel at min.z).
function unitShoeBox() {
  return {
    size: { x: 0.1, y: 0.07, z: 0.27 },
    center: { x: 0, y: -0.035, z: 0.135 },
    min: { x: -0.05, y: -0.07, z: 0 },
  }
}

test('normalizeForwardAxis: known axes pass, garbage becomes +z', () => {
  assert.equal(normalizeForwardAxis('+z'), '+z')
  assert.equal(normalizeForwardAxis('-z'), '-z')
  assert.equal(normalizeForwardAxis('+x'), '+x')
  assert.equal(normalizeForwardAxis('-x'), '-x')
  assert.equal(normalizeForwardAxis(null), DEFAULT_FORWARD_AXIS)
  assert.equal(normalizeForwardAxis(undefined), DEFAULT_FORWARD_AXIS)
  assert.equal(normalizeForwardAxis('+y'), DEFAULT_FORWARD_AXIS)
  assert.equal(normalizeForwardAxis(''), DEFAULT_FORWARD_AXIS)
})

test('normalizeModelScale: clamps garbage to the sane range', () => {
  assert.equal(normalizeModelScale(1.4), 1.4)
  assert.equal(normalizeModelScale(null), 1)
  assert.equal(normalizeModelScale('nope'), 1)
  assert.equal(normalizeModelScale(99), 3)
  assert.equal(normalizeModelScale(0.1), 0.5)
})

test('+z legacy: heel at origin, toe at +1, sole grounded', () => {
  const n = computeModelNormalization(unitShoeBox(), '+z', 1)
  assert.equal(n.yawRadians, 0)
  assert.equal(n.forwardAxis, '+z')
  assert.equal(n.length, 0.27)
  // Heel (min.z = 0) maps to 0; toe (0.27) maps to +1.
  assert.ok(Math.abs(n.offset.z - 0) < 1e-9)
  assert.ok(Math.abs(0.27 * n.uniformScale + n.offset.z - 1) < 1e-9)
  // Sole (min.y) at 0; x centered.
  assert.ok(Math.abs(-0.07 * n.uniformScale + n.offset.y) < 1e-9)
  assert.equal(n.offset.x, 0)
})

test('-z (JBC Crown): yaw PI, same unit contract after the yaw', () => {
  const n = computeModelNormalization(unitShoeBox(), '-z', 1)
  assert.equal(n.yawRadians, FORWARD_YAW['-z'])
  assert.equal(n.yawRadians, Math.PI)
  // The box is measured post-yaw, so the contract is identical to +z:
  // heel at min.z maps to 0, toe maps to +1.
  assert.ok(Math.abs(n.offset.z - 0) < 1e-9)
  assert.ok(Math.abs(0.27 * n.uniformScale + n.offset.z - 1) < 1e-9)
})

test('x-axis yaws follow the right-hand rule', () => {
  // Toe on +X needs −π/2 to land on +Z; toe on −X needs +π/2.
  assert.equal(FORWARD_YAW['+x'], -Math.PI / 2)
  assert.equal(FORWARD_YAW['-x'], Math.PI / 2)
  const nx = computeModelNormalization(unitShoeBox(), '-x', 1)
  assert.equal(nx.yawRadians, Math.PI / 2)
  assert.equal(nx.forwardAxis, '-x')
  // Post-yaw contract is axis-independent.
  assert.ok(Math.abs(0.27 * nx.uniformScale + nx.offset.z - 1) < 1e-9)
})

test('unknown axis renders exactly as legacy +z', () => {
  const legacy = computeModelNormalization(unitShoeBox(), '+z', 1)
  const unknown = computeModelNormalization(unitShoeBox(), 'sideways', 1)
  assert.deepEqual(unknown, { ...legacy, forwardAxis: '+z' })
})

test('offset centers and wide boxes do not confuse it', () => {
  const wide = {
    size: { x: 0.16, y: 0.07, z: 0.27 },
    center: { x: 0.02, y: -0.035, z: 0.135 },
    min: { x: -0.06, y: -0.07, z: 0 },
  }
  const n = computeModelNormalization(wide, '+z', 1)
  assert.equal(n.length, 0.27)
  assert.ok(Math.abs(n.offset.z - 0) < 1e-9)
  assert.ok(Math.abs(0.27 * n.uniformScale + n.offset.z - 1) < 1e-9)
  assert.ok(Math.abs(0.02 * n.uniformScale + n.offset.x) < 1e-9)
})

test('defaultScale multiplies on top of the unit fit', () => {
  const one = computeModelNormalization(unitShoeBox(), '+z', 1)
  const big = computeModelNormalization(unitShoeBox(), '+z', 1.5)
  assert.ok(Math.abs(big.uniformScale - one.uniformScale * 1.5) < 1e-12)
  // The trim baseline (100%) already carries the per-model correction.
  assert.ok(Math.abs(0.27 * big.uniformScale + big.offset.z - 1.5) < 1e-9)
})

test('degenerate boxes return null instead of NaN scales', () => {
  const zero = {
    size: { x: 0, y: 0, z: 0 },
    center: { x: 0, y: 0, z: 0 },
    min: { x: 0, y: 0, z: 0 },
  }
  assert.equal(computeModelNormalization(zero, '+z', 1), null)
  assert.equal(computeModelNormalization(null), null)
  assert.equal(computeModelNormalization(undefined, '-z'), null)
  assert.equal(
    computeModelNormalization(
      { size: { x: 0.1, y: 0.07, z: NaN }, center: { x: 0, y: 0, z: 0 }, min: { x: 0, y: 0, z: 0 } },
      '+z',
      1,
    ),
    null,
  )
})
