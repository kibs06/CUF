import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  distinctColorNames,
  guessPaintHex,
  isPaintHex,
  paintFactors,
  paintRow,
} from './paintGuess.js'

// The guess fills the picker; the human stores. So the guess tests pin the
// buckets the app's mapper defines (drift here means the prefill disagrees
// with the product page's own swatches), while the store tests pin the one
// rule that protects the catalogue: only a web hex is storable.

test('guess buckets match the app mapper', () => {
  assert.equal(guessPaintHex('Black'), '#26221E')
  assert.equal(guessPaintHex('Midnight Brown'), '#8B5A2B')
  assert.equal(guessPaintHex('Dark Brown'), '#4E342E')
  assert.equal(guessPaintHex('Off-White'), '#F1E8DC')
  assert.equal(guessPaintHex('Burgundy'), '#9B3B2E')
  assert.equal(guessPaintHex('Navy'), '#3F4A63')
})

test('guess is deterministic for unknown names (and a guess, not truth)', () => {
  const first = guessPaintHex('Carob Suede Special')
  assert.equal(guessPaintHex('Carob Suede Special'), first)
  assert.match(first, /^#[0-9A-Fa-f]{6}$/)
})

test('only a web hex is storable', () => {
  assert.equal(isPaintHex('#5C3A21'), true)
  assert.equal(isPaintHex('#5c3a21'), true)
  assert.equal(isPaintHex('red'), false)
  assert.equal(isPaintHex('5C3A21'), false)
  assert.equal(isPaintHex('#FFF'), false)
  assert.equal(isPaintHex(null), false)
})

test('paint factors feed a live 3D tint, or nothing when not a paint', () => {
  const factors = paintFactors('#3f4a63')
  assert.deepEqual(
    factors.map((f) => Math.round(f * 255)),
    [0x3f, 0x4a, 0x63],
  )
  // Case is tint-irrelevant: the stored lowercase and the guessed uppercase
  // converge to the same factors.
  assert.deepEqual(paintFactors('#3F4A63'), factors)
  assert.equal(paintFactors('red'), null)
  assert.equal(paintFactors(null), null)
})

test('paint rows carry the product, the colour and the confirmed hex', () => {
  assert.deepEqual(paintRow('p1', ' Brown ', ' #5C3A21 '), {
    product_id: 'p1',
    color_name: 'Brown',
    // Lowercased at the write boundary: the live hex CHECK is lowercase-only.
    paint_hex: '#5c3a21',
  })
})

test('colour list unions variants and photo rows, sorted and deduped', () => {
  assert.deepEqual(
    distinctColorNames({
      variants: [{ color: 'Brown' }, { color: 'Black' }, { color: 'Brown' }, {}],
      colorImages: [{ color_name: 'Tan' }, { color_name: 'Brown' }, {}],
    }),
    ['Black', 'Brown', 'Tan'],
  )
  assert.deepEqual(distinctColorNames(), [])
})
