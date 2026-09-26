import assert from 'node:assert/strict'
import { test } from 'node:test'

import { SWATCH_BROWN, SWATCH_FALLBACKS, swatchColour } from './swatchRules.js'

test('swatchColour: every preset draws a dot, and the distinct ones differ', () => {
  const presets = [
    'Black',
    'Brown',
    'Carob',
    'Cream',
    'Burgundy',
    'Gold',
    'Olive',
    'Navy',
    'Grey',
    'White',
    'Beige',
  ]
  for (const name of presets) {
    assert.match(swatchColour(name), /^#[0-9a-f]{6}$/, `${name} must be a hex`)
  }

  /*
    The light family is deliberately ONE dot — White, Cream and Beige are the same
    pair as far as a swatch is concerned — so the buckets, not the names, are what
    have to be distinct. Nine buckets over eleven names.
  */
  const buckets = new Set(presets.map(swatchColour))
  assert.equal(buckets.size, 9)
  const light = ['Cream', 'White', 'Beige'].map(swatchColour)
  assert.equal(new Set(light).size, 1, 'the light family is one bucket')
})

test('swatchColour: the app\u2019s own answers, name for name', () => {
  // Ported values from `variant_swatch_color.dart`, checked as literals: this is
  // the one thing in the portal that has to agree with the phone pixel for pixel.
  assert.equal(swatchColour('Black'), '#26221e')
  assert.equal(swatchColour('carob'), '#3e2723')
  assert.equal(swatchColour('Cream'), '#f1e8dc')
  assert.equal(swatchColour('White'), '#f1e8dc')
  assert.equal(swatchColour('Beige'), '#f1e8dc')
  assert.equal(swatchColour('Off-white suede'), '#f1e8dc')
  assert.equal(swatchColour('Gold'), '#b8860b')
  assert.equal(swatchColour('Burgundy'), '#9b3b2e')
  assert.equal(swatchColour('Olive'), '#5d6b45')
  assert.equal(swatchColour('Navy'), '#3f4a63')
  assert.equal(swatchColour('Grey'), '#9e948a')
  assert.equal(swatchColour('Gray'), '#9e948a')
  assert.equal(swatchColour('Brown'), SWATCH_BROWN)
})

test('swatchColour: the brown branch is the app\u2019s, including its two shades', () => {
  for (const name of ['Brown', 'Tan', 'Camel', 'Cognac', 'Burnished Clay', 'Leather']) {
    assert.equal(swatchColour(name), SWATCH_BROWN, name)
  }
  assert.equal(swatchColour('Dark Brown'), '#4e342e')
  assert.equal(swatchColour('Light Brown'), '#a1887f')
  // `dark` is tested first, so a name carrying both words is the dark one —
  // which is the app's order and not an accident of the two `if`s.
  assert.equal(swatchColour('Dark Light Brown'), '#4e342e')
})

test('swatchColour: order is precedence, and Carob is the case it decides', () => {
  /*
    The bare preset is its own dark brown, and the same word inside a name that
    also says "brown" is not — the brown branch runs first. Kept because the app's
    does, which is the only reason this file exists.
  */
  assert.equal(swatchColour('Carob'), '#3e2723')
  assert.equal(swatchColour('Carob Brown'), SWATCH_BROWN)
  assert.equal(swatchColour('Charcoal'), '#26221e')

  // The other two the order decides: a colour word first wins over a later one.
  assert.equal(swatchColour('Tan suede'), SWATCH_BROWN)
  assert.equal(swatchColour('Suede'), '#f1e8dc')
})

test('swatchColour: the words neither the presets nor the branches name', () => {
  assert.equal(swatchColour('Mustard'), '#b8860b')
  assert.equal(swatchColour('Maroon'), '#9b3b2e')
  assert.equal(swatchColour('Green'), '#5d6b45')
  assert.equal(swatchColour('Blue'), '#3f4a63')
  assert.equal(swatchColour('Yellow Salt'), '#b8860b')
})

test('swatchColour: a name written after the colour still matches', () => {
  // `contains`, not `startsWith` — the app's own rule, and the reason
  // `Burnished Clay` above is brown.
  assert.equal(swatchColour('Sole in olive'), '#5d6b45')
  assert.equal(swatchColour('Strap: navy'), '#3f4a63')
})

test('swatchColour: an unknown name is stable, and never blank', () => {
  const first = swatchColour('Argyle')
  assert.equal(first, swatchColour('Argyle'))
  assert.equal(first, swatchColour('argyle'))
  assert.equal(SWATCH_FALLBACKS.includes(first), true)

  // The two properties the fallback exists for: the same name never moves, and
  // different names rarely collide. Over 200 invented names a six-entry palette
  // cannot be spread evenly, but every entry should be used.
  const used = new Set()
  for (let index = 0; index < 200; index += 1) {
    const name = `shade ${index}`
    assert.equal(swatchColour(name), swatchColour(name))
    used.add(swatchColour(name))
  }
  assert.equal(used.size, SWATCH_FALLBACKS.length)
})

test('swatchColour: a name that is not a string is still a dot', () => {
  // The dialog's colour box is empty until the seller types, and an empty box
  // must draw the same dot every time rather than throw.
  assert.match(swatchColour(''), /^#[0-9a-f]{6}$/)
  assert.equal(swatchColour(''), swatchColour(null))
  assert.equal(swatchColour(''), swatchColour(undefined))
  assert.match(swatchColour('   '), /^#[0-9a-f]{6}$/)
})
