import assert from 'node:assert/strict'
import { test } from 'node:test'

import { PRODUCT_CATEGORIES } from './constants.js'
import { FOOT_SIZE_CATEGORIES } from './footRules.js'
import {
  MAX_BARCODE_LENGTH,
  blankToNull,
  emptyProductDraft,
  productColumnsFromDraft,
  productDraftFrom,
  productProblems,
} from './productDraft.js'
import { PRODUCT_TAG_GROUPS } from './productTags.js'

/** A stored `products` row, as `mapSellerProduct` hands it over. */
const STORED = {
  id: 'p1',
  name: 'Barong slip-on',
  description: 'Vegetable-tanned.',
  price: 1450,
  category: 'Casual',
  collection: 'Heritage',
  sku: 'BS-01',
  barcode: '4801234567890',
  tags: ['handmade', 'custom:material:Teal'],
  audience: 'men',
  is_published: true,
  is_featured: false,
  sale_price: 1200,
  sale_starts_at: '2026-09-01T00:00:00+00:00',
  sale_ends_at: '2026-09-30T00:00:00+00:00',
}

test('blankToNull: blank is NULL, and only blank', () => {
  assert.equal(blankToNull('  '), null)
  assert.equal(blankToNull(''), null)
  assert.equal(blankToNull(null), null)
  assert.equal(blankToNull(undefined), null)
  assert.equal(blankToNull('  Heritage '), 'Heritage')
  /*
    `0` is the text `'0'`, not blank — which is the right answer for the columns
    this is used on (a barcode of zeros is a barcode, and none of them is a
    number). The value is stringified rather than type-checked so a caller that
    read a numeric-ish field out of local state cannot crash the form.
  */
  assert.equal(blankToNull(0), '0')
})

test('emptyProductDraft starts published, unfeatured and without a sale', () => {
  const draft = emptyProductDraft()
  assert.equal(draft.is_published, true)
  assert.equal(draft.is_featured, false)
  assert.equal(draft.audience, null)
  assert.equal(draft.sale_price, '')
  assert.equal(draft.sale_starts_at, '')
  assert.equal(draft.category, PRODUCT_CATEGORIES[0])
  assert.deepEqual(draft.tags, [])
})

test('productDraftFrom parses the three encoded columns', () => {
  const draft = productDraftFrom(STORED)

  // Tags come back as entries the picker can draw...
  assert.deepEqual(draft.tags, [
    { group: 'type', value: 'handmade', custom: false },
    { group: 'material', value: 'Teal', custom: true },
  ])
  // ...the dates as the date part alone, which is what a date input speaks...
  assert.equal(draft.sale_starts_at, '2026-09-01')
  assert.equal(draft.sale_ends_at, '2026-09-30')
  // ...and the price as the text an input holds, so `1450` does not render as
  // `1450.0` or lose a trailing zero.
  assert.equal(draft.price, '1450')
  assert.equal(draft.sale_price, '1200')
})

test('productDraftFrom reads what is absent as blank or unset', () => {
  const draft = productDraftFrom({ id: 'p2', name: 'Bare', price: 0 })
  assert.equal(draft.category, PRODUCT_CATEGORIES[0])
  assert.equal(draft.description, '')
  assert.equal(draft.sku, '')
  assert.equal(draft.collection, '')
  assert.equal(draft.barcode, '')
  assert.equal(draft.sale_price, '')
  assert.equal(draft.sale_starts_at, '')
  assert.equal(draft.audience, null)
  // A NULL `is_published` reads as published — the column defaults to true, and
  // treating a missing value as "hidden" would take a product out of the shop.
  assert.equal(draft.is_published, true)
  assert.equal(draft.is_featured, false)
})

test('productDraftFrom refuses an audience outside the vocabulary', () => {
  // The column's CHECK would reject 'Men' — and so would the form, silently,
  // by not selecting a chip. It must not be carried through to the save.
  assert.equal(productDraftFrom({ audience: 'Men' }).audience, null)
  assert.equal(productDraftFrom({ audience: 'women' }).audience, 'women')
  assert.equal(
    productDraftFrom({ audience: FOOT_SIZE_CATEGORIES[2].value }).audience,
    'kids',
  )
})

test('the draft round-trips: open a product, save it unchanged, nothing moves', () => {
  const draft = productDraftFrom(STORED)
  const columns = productColumnsFromDraft(draft)

  assert.equal(columns.name, STORED.name)
  assert.equal(columns.description, STORED.description)
  assert.equal(columns.price, STORED.price)
  assert.equal(columns.category, STORED.category)
  assert.equal(columns.collection, STORED.collection)
  assert.equal(columns.sku, STORED.sku)
  assert.equal(columns.barcode, STORED.barcode)
  assert.deepEqual(columns.tags, STORED.tags)
  assert.equal(columns.audience, STORED.audience)
  assert.equal(columns.sale_price, STORED.sale_price)
  // The instant is the same one the app would write for this date: a date-only
  // timestamp with no zone, read by Postgres in the column's own timezone.
  assert.equal(columns.sale_starts_at, '2026-09-01T00:00:00')
  assert.equal(columns.sale_ends_at, '2026-09-30T00:00:00')
})

test('productColumnsFromDraft clears what was cleared', () => {
  const columns = productColumnsFromDraft(
    emptyProductDraft({
      name: 'Bare',
      price: '0',
      category: '',
      description: '   ',
      audience: 'nonsense',
      tags: [],
      sale_price: '',
      sale_starts_at: '',
    }),
  )

  assert.equal(columns.description, null)
  assert.equal(columns.collection, null)
  assert.equal(columns.sku, null)
  assert.equal(columns.barcode, null)
  assert.deepEqual(columns.tags, [])
  assert.equal(columns.audience, null, 'an unrecognised audience clears the column')
  assert.equal(columns.sale_price, null)
  assert.equal(columns.sale_starts_at, null)
  // A blank category is not allowed to blank the column: it has a default and
  // the storefront's filter reads it.
  assert.equal(columns.category, PRODUCT_CATEGORIES[0])
  assert.equal(columns.price, 0)
})

test('productColumnsFromDraft writes the tag array in the picker’s order', () => {
  const columns = productColumnsFromDraft(
    emptyProductDraft({
      name: 'Tagged',
      tags: [
        { group: 'sustainability', value: 'eco_friendly', custom: false },
        { group: 'type', value: 'handmade', custom: false },
        { group: 'type', value: 'Bespoke', custom: true },
      ],
    }),
  )
  assert.deepEqual(columns.tags, [
    'handmade',
    'custom:type:Bespoke',
    'eco_friendly',
  ])
})

test('a zero sale price is written as NULL, not as 0', () => {
  // `isOnSale` ignores a 0 anyway, so this changes nothing either client shows —
  // it stops the column holding a number no reader should treat as a price.
  for (const value of ['', '0', 0, 'free', null, -5]) {
    assert.equal(
      productColumnsFromDraft(emptyProductDraft({ sale_price: value })).sale_price,
      null,
      `${String(value)} should not become a sale price`,
    )
  }
  assert.equal(
    productColumnsFromDraft(emptyProductDraft({ sale_price: '899.50' })).sale_price,
    899.5,
  )
})

test('productProblems blocks a save for the app’s own refusals', () => {
  const { errors } = productProblems({
    draft: emptyProductDraft({ name: '  ', price: '' }),
  })
  assert.deepEqual(errors, ['Give the product a name.', 'Enter a price.'])

  assert.deepEqual(
    productProblems({ draft: emptyProductDraft({ name: 'A', price: 'abc' }) }).errors,
    ['Enter a price of 0 or more.'],
  )
  assert.deepEqual(
    productProblems({ draft: emptyProductDraft({ name: 'A', price: '-1' }) }).errors,
    ['Enter a price of 0 or more.'],
  )
})

test('productProblems: a sale price that is not a discount blocks the save', () => {
  const { errors } = productProblems({
    draft: emptyProductDraft({ name: 'A', price: '1000', sale_price: '1000' }),
  })
  assert.deepEqual(errors, ['Sale price must be lower than the base price.'])
  assert.deepEqual(
    productProblems({
      draft: emptyProductDraft({ name: 'A', price: '1000', sale_price: '900' }),
    }).errors,
    [],
  )
})

test('productProblems: a barcode past the app’s limit blocks the save', () => {
  assert.deepEqual(
    productProblems({
      draft: emptyProductDraft({
        name: 'A',
        price: '1',
        barcode: '9'.repeat(MAX_BARCODE_LENGTH),
      }),
    }).errors,
    [],
  )
  assert.deepEqual(
    productProblems({
      draft: emptyProductDraft({
        name: 'A',
        price: '1',
        barcode: '9'.repeat(MAX_BARCODE_LENGTH + 1),
      }),
    }).errors,
    ['Barcode must be under 50 characters.'],
  )
})

test('productProblems: a sale window that can never open is only a note', () => {
  const { errors, notes } = productProblems({
    draft: emptyProductDraft({
      name: 'A',
      price: '1000',
      sale_price: '900',
      sale_starts_at: '2026-09-30',
      sale_ends_at: '2026-09-01',
    }),
  })
  assert.deepEqual(errors, [])
  assert.deepEqual(notes, [
    'The sale ends before it starts, so it will never be active.',
  ])
})

test('productProblems: a Kids’ audience with adult sizes is only a note', () => {
  const { errors, notes } = productProblems({
    draft: emptyProductDraft({ name: 'A', price: '1', audience: 'kids' }),
    variants: [{ size: 'EU 42', color: null, stock: 3 }],
  })
  assert.deepEqual(errors, [])
  assert.deepEqual(notes, [
    'These sizes look like adult sizing — check the audience is right.',
  ])

  // The same product marked Kids' with a kids' size says nothing.
  assert.deepEqual(
    productProblems({
      draft: emptyProductDraft({ name: 'A', price: '1', audience: 'kids' }),
      variants: [{ size: 'EU 28', color: null, stock: 1 }],
    }).notes,
    [],
  )
})

test('productProblems carries the variant rules, errors and notes apart', () => {
  const blocked = productProblems({
    draft: emptyProductDraft({ name: 'A', price: '1' }),
    variants: [],
    colours: ['Black', 'black'],
  })
  assert.deepEqual(blocked.errors, ['Two colours are both named black.'])

  const warned = productProblems({
    draft: emptyProductDraft({ name: 'A', price: '1' }),
    variants: [{ size: 'EU 42', color: 'Black', stock: 0 }],
    colours: ['Black', 'Olive'],
    // Black has a photo and Olive does not, which is the whole of the photo rule:
    // a NOTE and never an error, because every coloured product in the catalog
    // predates per-colour galleries and the migration left them as-is.
    colourImages: { Black: [{ url: 'black-1.jpg', displayOrder: 0 }] },
  })
  assert.deepEqual(warned.errors, [])
  assert.deepEqual(warned.notes, [
    'Olive has no sizes yet, so nothing is stored for that colour.',
    'Olive has no photos yet — customers see the product\u2019s own photos for it.',
    'Every size is at zero, so this product will be marked unavailable until something is restocked.',
  ])
})

test('productProblems names the option it is complaining about', () => {
  const { errors, notes } = productProblems({
    draft: emptyProductDraft({ name: 'A', price: '1' }),
    customizations: [
      { option_name: 'Sole colour', option_type: '', options: [] },
      { option_name: '  ', option_type: 'text', options: [] },
      { option_name: 'Engraving', option_type: 'color', options: [] },
    ],
  })

  assert.deepEqual(errors, [
    'Sole colour: Choose a kind of option.',
    'Option 2: Give the option a name.',
  ])
  assert.deepEqual(notes, [
    'Engraving: Engraving has no choices yet, so the list a customer picks from would be empty.',
  ])
})

test('a clean draft has nothing to say about itself', () => {
  const product = {
    ...STORED,
    sale_price: null,
    sale_starts_at: null,
    sale_ends_at: null,
  }
  assert.deepEqual(
    productProblems({
      draft: productDraftFrom(product),
      variants: [
        { size: 'EU 42', color: null, stock: 3 },
        { size: 'EU 41', color: null, stock: 1 },
      ],
      colours: [],
      customizations: [
        { option_name: 'Engraving', option_type: 'text', options: [] },
      ],
    }),
    { errors: [], notes: [] },
  )
})

test('the draft knows the tag vocabulary the picker draws from', () => {
  // A guard rather than a behaviour: the draft parses and serialises with the
  // product groups, so a tag the picker cannot draw would be silently dropped.
  const ids = PRODUCT_TAG_GROUPS.flatMap((group) =>
    group.presets.map((preset) => preset.id),
  )
  for (const id of ids) {
    const draft = productDraftFrom({ tags: [id] })
    assert.deepEqual(productColumnsFromDraft(draft).tags, [id])
  }
})
