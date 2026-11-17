import assert from 'node:assert/strict'
import { test } from 'node:test'

import { spaceArModes, shouldOfferSpaceView } from './arSpace.js'

test('spaceArModes: every platform mode, including generated Quick Look', () => {
  assert.equal(spaceArModes(), 'webxr scene-viewer quick-look')
  assert.equal(spaceArModes(false), 'webxr scene-viewer quick-look')
  assert.equal(
    spaceArModes('https://example.supabase.co/models/pair.usdz'),
    'webxr scene-viewer quick-look',
  )
})

test('shouldOfferSpaceView: only a started session counts', () => {
  assert.equal(shouldOfferSpaceView('session-started'), true)
  assert.equal(shouldOfferSpaceView('object-placed'), true)
  assert.equal(shouldOfferSpaceView('failed'), false)
  assert.equal(shouldOfferSpaceView('not-presenting'), false)
  assert.equal(shouldOfferSpaceView(undefined), false)
  assert.equal(shouldOfferSpaceView(null), false)
})
