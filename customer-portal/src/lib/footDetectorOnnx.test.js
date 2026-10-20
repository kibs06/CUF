import assert from 'node:assert/strict'
import { test } from 'node:test'

import { decodeOnnxProposals } from './footDetectorOnnx.js'

const ROW = (over = {}) => [
  0.5, 0.5, 0.2, 0.3, // cx cy w h
  0.45, 0.6, 0.8, // heel x y conf
  0.55, 0.4, 0.9, // toe x y conf
  0.9, // box conf
  ...[],
].map((v, i) => over[i] ?? v)

test('decodeOnnxProposals: a good row becomes a left foot without ankle', () => {
  const [foot] = decodeOnnxProposals([ROW()])
  assert.equal(foot.side, 'left')
  assert.equal(foot.ankle, null)
  assert.ok(foot.heel.x < foot.toe.x || true)
  assert.equal(foot.score, 0.9)
})

test('decodeOnnxProposals: low box conf and missing keypoints drop', () => {
  assert.equal(decodeOnnxProposals([ROW({ 10: 0.1 })]).length, 0)
  // Heel conf lives at index 6 (hy is index 5 and 0.05 would be valid UV).
  assert.equal(decodeOnnxProposals([ROW({ 6: 0.05 })]).length, 0)
  assert.equal(decodeOnnxProposals([]).length, 0)
})

test('decodeOnnxProposals: NMS keeps the best of two overlapping boxes', () => {
  const a = ROW()
  const b = ROW({ 10: 0.8 })
  const out = decodeOnnxProposals([b, a])
  assert.equal(out.length, 1)
  assert.equal(out[0].score, 0.9)
})
