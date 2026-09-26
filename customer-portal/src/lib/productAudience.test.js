import assert from 'node:assert/strict'
import { test } from 'node:test'

import { PRODUCT_AUDIENCES } from './constants.js'
import { EU_KIDS_SIZES, FOOT_SIZE_CATEGORIES } from './footRules.js'
import {
  KIDS_AUDIENCE,
  PRODUCT_AUDIENCE_OPTIONS,
  PRODUCT_RAIL_AUDIENCES,
  UNISEX_AUDIENCE,
  audienceSizeMismatch,
  productAudienceFrom,
  productAudienceLabel,
} from './productAudience.js'

test('the three shopper scales are spread in, not re-spelled', () => {
  // The same objects: if the size picker's vocabulary changes, this list is what
  // changes with it, and no product can end up with an audience a shopper's own
  // profile cannot hold.
  assert.deepEqual(PRODUCT_AUDIENCE_OPTIONS.slice(0, 3), FOOT_SIZE_CATEGORIES)
  assert.deepEqual(
    PRODUCT_AUDIENCE_OPTIONS.map((option) => option.value),
    ['men', 'women', 'kids', 'unisex'],
  )
})

test('unisex is the only addition, and it is last', () => {
  const extra = PRODUCT_AUDIENCE_OPTIONS.filter(
    (option) => !FOOT_SIZE_CATEGORIES.includes(option),
  )
  assert.deepEqual(extra, [{ value: UNISEX_AUDIENCE, label: 'Unisex' }])
})

test('the labels agree with the portal’s existing audience list', () => {
  // `constants.PRODUCT_AUDIENCES` is what sign-up and the storefront already
  // spell out; the app has the same guard test. Drift here would show a customer
  // "Women's" on one screen and a different spelling on another.
  assert.deepEqual(
    PRODUCT_AUDIENCE_OPTIONS.map((option) => option.label),
    PRODUCT_AUDIENCES,
  )
})

test('the rails are the three scales, and never unisex', () => {
  assert.deepEqual(PRODUCT_RAIL_AUDIENCES, ['men', 'women', 'kids'])
  assert.equal(PRODUCT_RAIL_AUDIENCES.includes(UNISEX_AUDIENCE), false)
  for (const value of PRODUCT_RAIL_AUDIENCES) {
    assert.equal(productAudienceFrom(value), value)
  }
})

test('productAudienceFrom is an exact match — no trimming, no case folding', () => {
  assert.equal(productAudienceFrom('men'), 'men')
  assert.equal(productAudienceFrom('unisex'), 'unisex')
  // Each of these is a value the column's CHECK constraint would reject, so
  // normalising one would be inventing a meaning the database does not hold.
  assert.equal(productAudienceFrom('Men'), null)
  assert.equal(productAudienceFrom('unisex '), null)
  assert.equal(productAudienceFrom('MEN'), null)
  assert.equal(productAudienceFrom(''), null)
  assert.equal(productAudienceFrom(null), null)
  assert.equal(productAudienceFrom(undefined), null)
  assert.equal(productAudienceFrom(42), null)
})

test('productAudienceLabel pairs a value with its label, and nothing else', () => {
  assert.equal(productAudienceLabel('men'), "Men's")
  assert.equal(productAudienceLabel(KIDS_AUDIENCE), "Kids'")
  assert.equal(productAudienceLabel(UNISEX_AUDIENCE), 'Unisex')
  // Null for null and for unknown values: a caller with a label has an audience.
  assert.equal(productAudienceLabel(null), null)
  assert.equal(productAudienceLabel(undefined), null)
  assert.equal(productAudienceLabel('Men'), null)
  assert.equal(productAudienceLabel('edition'), null)
})

test('audienceSizeMismatch only ever fires for Kids', () => {
  const adultSizes = ['EU 42', 'EU 43']
  assert.equal(audienceSizeMismatch({ audience: 'men', sizes: adultSizes }), false)
  assert.equal(
    audienceSizeMismatch({ audience: UNISEX_AUDIENCE, sizes: adultSizes }),
    false,
  )
  assert.equal(audienceSizeMismatch({ audience: null, sizes: adultSizes }), false)
  assert.equal(audienceSizeMismatch({ audience: 'kids', sizes: adultSizes }), true)
})

test('audienceSizeMismatch: one kids size confirms the audience', () => {
  // The band overlaps the adult scale at the top, so EU 35 counts — and a single
  // size inside the band is enough to stop claiming anything.
  assert.equal(
    audienceSizeMismatch({ audience: 'kids', sizes: ['EU 42', 'EU 28'] }),
    false,
  )
  assert.equal(audienceSizeMismatch({ audience: 'kids', sizes: ['EU 35'] }), false)
  assert.equal(audienceSizeMismatch({ audience: 'kids', sizes: ['28'] }), false)
})

test('audienceSizeMismatch claims nothing it cannot read', () => {
  // No sizes yet: nothing is stocked, so nothing is contradicted.
  assert.equal(audienceSizeMismatch({ audience: 'kids', sizes: [] }), false)
  assert.equal(audienceSizeMismatch({ audience: 'kids' }), false)
  // One unreadable size means we do not know what this product stocks at all.
  assert.equal(
    audienceSizeMismatch({ audience: 'kids', sizes: ['EU 42', 'One size'] }),
    false,
  )
  assert.equal(
    audienceSizeMismatch({ audience: 'kids', sizes: [null, 'EU 42'] }),
    false,
  )
})

test('the kids band is the size picker’s own list, ends included', () => {
  const first = EU_KIDS_SIZES[0]
  const last = EU_KIDS_SIZES[EU_KIDS_SIZES.length - 1]
  assert.equal(audienceSizeMismatch({ audience: 'kids', sizes: [`EU ${first}`] }), false)
  assert.equal(audienceSizeMismatch({ audience: 'kids', sizes: [`EU ${last}`] }), false)
  // Just past the top of the band, and nothing inside it: adult sizing.
  assert.equal(
    audienceSizeMismatch({ audience: 'kids', sizes: [`EU ${Number(last) + 1}`] }),
    true,
  )
})
