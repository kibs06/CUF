import test from 'node:test'
import assert from 'node:assert/strict'

import {
  EU_ADULT_SIZES,
  EU_KIDS_SIZES,
  FOOT_PROFILE_SOURCE,
  emptyFootDraft,
  euSizesFor,
  footDraftErrors,
  footDraftFromProfile,
  footProfileError,
  footProfilePayload,
  footProfileSkippedPayload,
  footProfileSummary,
  footSizeCategoryLabel,
  formatFootSize,
  hasFootSize,
  isFootDraftComplete,
} from './footRules.js'

test('the size lists match the app: adult 35–48, kids 22–35, half steps', () => {
  assert.equal(EU_ADULT_SIZES[0], '35')
  assert.equal(EU_ADULT_SIZES.at(-1), '48')
  assert.equal(EU_KIDS_SIZES[0], '22')
  assert.equal(EU_KIDS_SIZES.at(-1), '35')
  assert.equal(EU_ADULT_SIZES.length, 27)
  assert.equal(EU_KIDS_SIZES.length, 27)
  // Kids' hands 36+ to the men's/women's bands, so it must NOT contain them.
  assert.equal(EU_KIDS_SIZES.includes('36'), false)
})

test('euSizesFor picks the band, and an unpicked scale is the adult band', () => {
  assert.equal(euSizesFor('kids'), EU_KIDS_SIZES)
  assert.equal(euSizesFor('men'), EU_ADULT_SIZES)
  assert.equal(euSizesFor('women'), EU_ADULT_SIZES)
  assert.equal(euSizesFor(null), EU_ADULT_SIZES)
})

test('scale labels are the app wording, and unknown values are null', () => {
  assert.equal(footSizeCategoryLabel('men'), "Men's")
  assert.equal(footSizeCategoryLabel('women'), "Women's")
  assert.equal(footSizeCategoryLabel('kids'), "Kids'")
  for (const value of [null, undefined, '', 'Men', 'unisex']) {
    assert.equal(footSizeCategoryLabel(value), null)
  }
})

test('a stored size never renders with a trailing zero', () => {
  assert.equal(formatFootSize(40), '40')
  assert.equal(formatFootSize('40'), '40')
  assert.equal(formatFootSize('40.0'), '40')
  assert.equal(formatFootSize(40.5), '40.5')
  assert.equal(formatFootSize('40.50'), '40.5')
  // A non-numeric value is passed through rather than becoming NaN.
  assert.equal(formatFootSize('EU 40'), 'EU 40')
  assert.equal(formatFootSize(null), '')
  assert.equal(formatFootSize(''), '')
})

test('either marker counts as having a size; skipped does not', () => {
  assert.equal(hasFootSize({ foot_profile_source: 'manual', foot_size_ph: 40 }), true)
  // Source only — the snapshot write is best-effort in the app, so it can be
  // the only thing that survived.
  assert.equal(hasFootSize({ foot_profile_source: 'ar_scan' }), true)
  // Size only — a build that predates the source column.
  assert.equal(hasFootSize({ foot_size_ph: 42 }), true)
  assert.equal(hasFootSize({ foot_size_ph: '  ' }), false)

  // `skipped` must NOT count: "skip" cannot mean "never ask again silently".
  assert.equal(hasFootSize({ foot_profile_source: 'skipped' }), false)
  assert.equal(
    hasFootSize({ foot_profile_source: 'skipped', foot_size_ph: 41 }),
    true,
    'a skip does not erase a size that is on file',
  )

  assert.equal(hasFootSize(null), false)
  assert.equal(hasFootSize({}), false)
})

test('the summary names the size, the scale and where it came from', () => {
  assert.equal(footProfileSummary(null), 'Not set yet')
  assert.equal(footProfileSummary({}), 'Not set yet')
  assert.equal(
    footProfileSummary({ foot_profile_source: 'skipped' }),
    'Not set yet',
  )

  assert.equal(
    footProfileSummary({
      foot_size_ph: 40,
      foot_size_category: 'men',
      foot_profile_source: 'manual',
    }),
    'EU 40 · Men\'s · set manually',
  )
  assert.equal(
    footProfileSummary({
      foot_size_ph: '42.5',
      foot_size_category: 'women',
      foot_profile_source: 'ar_scan',
    }),
    'EU 42.5 · Women\'s · from your AR scan',
  )
  // A size with no scale on file says so rather than guessing one.
  assert.equal(
    footProfileSummary({ foot_size_ph: 38, foot_profile_source: 'manual' }),
    'EU 38 · set manually',
  )
})

test('a draft round-trips a profile', () => {
  assert.deepEqual(footDraftFromProfile(null), emptyFootDraft())
  assert.deepEqual(
    footDraftFromProfile({
      foot_size_ph: '41.0',
      foot_size_category: 'men',
      foot_width: 'Wide',
      foot_profile_source: 'manual',
    }),
    { category: 'men', size: '41', width: 'Wide' },
  )
  // An unrecognised stored scale is dropped rather than re-submitted.
  assert.deepEqual(
    footDraftFromProfile({
      foot_size_ph: 40,
      foot_size_category: 'unisex',
      foot_profile_source: 'manual',
    }),
    { category: '', size: '40', width: '' },
  )
})

test('a draft needs a scale, and a size that scale actually offers', () => {
  assert.deepEqual(footDraftErrors(emptyFootDraft()), {
    category: 'Pick the scale you shop in',
    size: 'Pick your size',
  })

  assert.deepEqual(footDraftErrors({ category: 'men', size: '42' }), {})
  assert.ok(isFootDraftComplete({ category: 'men', size: '42' }))
  assert.ok(isFootDraftComplete({ category: 'kids', size: '22.5', width: 'Narrow' }))

  // EU 45 is not a children's size, and storing it would leave the chart with a
  // value it cannot place.
  const kids = footDraftErrors({ category: 'kids', size: '45' })
  assert.equal(kids.size, "That is not a size in the Kids' range")

  // An unpicked scale still validates against the adult band, so the order the
  // customer fills the form in does not produce a false error.
  assert.equal(footDraftErrors({ category: '', size: '42' }).size, undefined)

  assert.equal(
    footDraftErrors({ category: 'men', size: '42', width: 'Extra wide' }).width,
    'Pick one of the listed widths',
  )
})

test('the payload carries the manual provenance and a real number', () => {
  const payload = footProfilePayload(
    { category: 'men', size: '42.5', width: 'Wide' },
    new Date('2026-09-25T10:00:00.000Z'),
  )

  assert.deepEqual(payload, {
    foot_size_ph: 42.5,
    foot_width: 'Wide',
    foot_size_category: 'men',
    foot_profile_source: FOOT_PROFILE_SOURCE.manual,
    foot_profile_updated_at: '2026-09-25T10:00:00.000Z',
  })
  // A number, not a string: the column is NUMERIC and the app compares it.
  assert.equal(typeof payload.foot_size_ph, 'number')

  // No width chosen writes null rather than '' — a width nobody picked.
  assert.equal(footProfilePayload({ category: 'men', size: '40' }).foot_width, null)
})

test('skipping records the skip WITHOUT erasing the size on file', () => {
  const payload = footProfileSkippedPayload(new Date('2026-09-25T10:00:00.000Z'))
  assert.deepEqual(payload, {
    foot_profile_source: FOOT_PROFILE_SOURCE.skipped,
    foot_profile_updated_at: '2026-09-25T10:00:00.000Z',
  })
  assert.equal('foot_size_ph' in payload, false)
  assert.equal('foot_size_category' in payload, false)
})

test('errors map to sentences a customer can act on', () => {
  assert.match(
    footProfileError({ code: '23514', message: 'violates check constraint' }),
    /pick from the list/i,
  )
  assert.match(
    footProfileError({ code: '42501', message: 'permission denied' }),
    /sign in again/i,
  )
  assert.equal(
    footProfileError({ code: 'P0001', message: 'Foot size out of range' }),
    'Foot size out of range',
  )
  assert.match(footProfileError(null), /could not save/i)
})
