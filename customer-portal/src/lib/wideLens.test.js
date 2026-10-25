import { describe, it } from 'node:test'
import assert from 'node:assert/strict'

import {
  getZoomRange,
  openWidestLensStream,
  pickWidestRearLens,
  pinMinZoom,
} from './wideLens.js'

const DEVICES = [
  { deviceId: 'tele', label: 'Back Tele Camera', kind: 'videoinput' },
  { deviceId: 'ultra', label: 'Back Ultra Wide Camera', kind: 'videoinput' },
  { deviceId: 'front', label: 'Front Camera', kind: 'videoinput' },
]

function fakeStream(deviceId = 'main') {
  const stopped = []
  return {
    stopped,
    getVideoTracks: () => [{ getSettings: () => ({ deviceId }) }],
    getTracks: () => [{ stop: () => stopped.push(1) }],
  }
}

describe('pickWidestRearLens', () => {
  it('prefers the ultrawide rear lens', () => {
    assert.equal(pickWidestRearLens(DEVICES), 'ultra')
  })

  it('matches 0.5x and wide-angle label shapes', () => {
    assert.equal(
      pickWidestRearLens([{ deviceId: 'w', label: '0.5x', kind: 'videoinput' }]),
      'w',
    )
    assert.equal(
      pickWidestRearLens([{ deviceId: 'w', label: 'Wide Angle', kind: 'videoinput' }]),
      'w',
    )
  })

  it('falls back to first rear, never front unless forced', () => {
    assert.equal(
      pickWidestRearLens([
        { deviceId: 'm', label: 'Back Camera', kind: 'videoinput' },
        { deviceId: 'f', label: 'Front Camera', kind: 'videoinput' },
      ]),
      'm',
    )
    assert.equal(
      pickWidestRearLens([{ deviceId: 'f', label: 'Front', kind: 'videoinput' }]),
      'f',
    )
  })

  it('returns null with no usable camera', () => {
    assert.equal(pickWidestRearLens([]), null)
    assert.equal(pickWidestRearLens(null), null)
    assert.equal(pickWidestRearLens([{ deviceId: '', label: 'x', kind: 'videoinput' }]), null)
  })
})

describe('getZoomRange', () => {
  it('reads min/max off capabilities', () => {
    assert.deepEqual(
      getZoomRange({ getCapabilities: () => ({ zoom: { min: 1, max: 4 } }) }),
      { min: 1, max: 4 },
    )
  })

  it('defaults a missing max to min and rejects garbage', () => {
    assert.deepEqual(
      getZoomRange({ getCapabilities: () => ({ zoom: { min: 2 } }) }),
      { min: 2, max: 2 },
    )
    assert.equal(getZoomRange({ getCapabilities: () => ({}) }), null)
    assert.equal(getZoomRange({ getCapabilities: () => { throw new Error('nope') } }), null)
    assert.equal(getZoomRange(null), null)
  })
})

describe('openWidestLensStream', () => {
  it('switches to the ultrawide and stops the old stream', async () => {
    const base = fakeStream('tele')
    const opened = []
    const result = await openWidestLensStream({
      open: async (c) => {
        opened.push(c)
        return fakeStream('ultra')
      },
      enumerate: async () => DEVICES,
      stream: base,
    })
    assert.deepEqual(opened[0].deviceId, { exact: 'ultra' })
    assert.equal(base.stopped.length, 1)
  })

  it('keeps the base stream when already widest', async () => {
    const base = fakeStream('ultra')
    let opened = 0
    const result = await openWidestLensStream({
      open: async () => { opened += 1; return fakeStream('ultra') },
      enumerate: async () => DEVICES,
      stream: base,
    })
    assert.equal(result, base)
    assert.equal(opened, 0)
  })

  it('throws when the lens refuses so the caller keeps its stream', async () => {
    await assert.rejects(
      openWidestLensStream({
        open: async () => { throw new Error('refused') },
        enumerate: async () => DEVICES,
        stream: fakeStream('tele'),
      }),
      /refused/,
    )
  })
})

describe('pinMinZoom', () => {
  it('applies the minimum zoom and reports success', async () => {
    let applied = null
    const ok = await pinMinZoom({
      getCapabilities: () => ({ zoom: { min: 1, max: 4 } }),
      applyConstraints: async (c) => { applied = c },
    })
    assert.equal(ok, true)
    assert.deepEqual(applied, { advanced: [{ zoom: 1 }] })
  })

  it('reports false without throwing on refusal or no control', async () => {
    assert.equal(
      await pinMinZoom({
        getCapabilities: () => ({ zoom: { min: 1, max: 4 } }),
        applyConstraints: async () => { throw new Error('denied') },
      }),
      false,
    )
    assert.equal(await pinMinZoom({ getCapabilities: () => ({}) }), false)
    assert.equal(await pinMinZoom(null), false)
  })
})
