import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  checkDeepArConventionExists,
  deepArConventionEffectForName,
  deepArEffectForProduct,
  deepArEffectForProductName,
  deepArSlugForName,
  deepArSnakeForName,
} from './deeparShoe.js'

test('Luxe resolves by row id and slug, any row id by name', () => {
  assert.equal(
    deepArEffectForProduct('77b8c0a3-0f09-41a6-aa70-fc1db04e4cc1'),
    '/effects/luxe_cross_strap_sandals.deepar',
  )
  assert.equal(deepArEffectForProduct('luxe-cross-strap-sandals'), '/effects/luxe_cross_strap_sandals.deepar')
  assert.equal(
    deepArEffectForProductName('Luxe Cross-Strap Sandals'),
    '/effects/luxe_cross_strap_sandals.deepar',
  )
  assert.equal(deepArEffectForProduct('some-uuid-that-names-luxe'), null)
  assert.equal(deepArSlugForName('Luxe Cross-Strap Sandals'), 'luxe-cross-strap-sandals')
})

test('JBC resolves by slug, any row id by name', () => {
  assert.equal(deepArEffectForProduct('jbc-crown-leather-sandals'), '/effects/jbc_crown_leather_sandals.deepar')
  assert.equal(
    deepArEffectForProductName('JBC Crown Leather Sandals'),
    '/effects/jbc_crown_leather_sandals.deepar',
  )
  assert.equal(deepArSlugForName('JBC Crown Leather Sandals'), 'jbc-crown-leather-sandals')
})

test('convention URL needs no map edit', async () => {
  assert.equal(deepArSnakeForName('JBC Crown Leather Sandals'), 'jbc_crown_leather_sandals')
  assert.equal(deepArConventionEffectForName('Some Future Shoe'), '/effects/some_future_shoe.deepar')
  assert.equal(deepArConventionEffectForName('  '), null)
  // Unreachable host never throws — hidden stays hidden.
  assert.equal(await checkDeepArConventionExists('http://127.0.0.1:1/nope.deepar'), false)
})

test('Luna mapping is unchanged', () => {
  assert.equal(
    deepArEffectForProduct('0aebaa64-4d9e-44f8-8876-6b3ee9855fae'),
    '/effects/luna_loafers.deepar',
  )
  assert.equal(deepArEffectForProduct('unknown-product'), null)
})
