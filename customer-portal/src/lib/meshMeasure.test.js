import { describe, it } from 'node:test'
import assert from 'node:assert/strict'

import {
  euSizeFromLengthMm,
  measureFootMesh,
  measurementSummary,
} from './meshMeasure.js'

const goodBox = { size: { x: 0.095, y: 0.07, z: 0.265 } }
const goodEvidence = { coverageDeg: 360, frameCount: 50, residualMm: 1 }

describe('measureFootMesh', () => {
  it('reads mm off a plausible mesh with high confidence', () => {
    const m = measureFootMesh(goodBox, goodEvidence)
    assert.equal(m.lengthMm, 265)
    assert.equal(m.widthMm, 95)
    assert.equal(m.heightMm, 70)
    assert.equal(m.confidenceLevel, 'high')
    assert.equal(m.euSize, '43')
  })

  it('downgrades confidence on partial evidence', () => {
    const m = measureFootMesh(goodBox, { coverageDeg: 180, frameCount: 20, residualMm: 4 })
    assert.equal(m.confidenceLevel, 'low')
  })

  it('returns null on degenerate or implausible boxes', () => {
    assert.equal(measureFootMesh(null), null)
    assert.equal(measureFootMesh({ size: { x: 0, y: 0.07, z: 0.265 } }), null)
    // A 50cm "foot" is a misscaled reconstruction, not a size.
    assert.equal(measureFootMesh({ size: { x: 0.095, y: 0.07, z: 0.5 } }), null)
  })
})

describe('euSizeFromLengthMm', () => {
  it('maps the adult range and refuses the rest', () => {
    assert.equal(euSizeFromLengthMm(222), '35')
    assert.equal(euSizeFromLengthMm(265), '43')
    assert.equal(euSizeFromLengthMm(150), null)
    assert.equal(euSizeFromLengthMm(NaN), null)
  })
})

describe('measurementSummary', () => {
  it('states the number with its uncertainty', () => {
    const m = measureFootMesh(goodBox, goodEvidence)
    assert.match(measurementSummary(m), /265 mm.*95 mm.*EU 43.*high/)
  })

  it('handles no measurement', () => {
    assert.equal(measurementSummary(null), 'No measurement yet.')
  })
})
