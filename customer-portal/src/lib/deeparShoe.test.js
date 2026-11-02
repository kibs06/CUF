import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  deepArEffectForProduct,
  deepArEffectForProductName,
  deepArSlugForName,
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

test('Luna mapping is unchanged', () => {
  assert.equal(
    deepArEffectForProduct('0aebaa64-4d9e-44f8-8876-6b3ee9855fae'),
    '/effects/luna_loafers.deepar',
  )
  assert.equal(deepArEffectForProduct('unknown-product'), null)
})
