import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  isStockDraftDirty,
  sizeStockChips,
  stockDraftFrom,
  stockDraftTotals,
} from './sizeSystems.js'

describe('stockDraftFrom', () => {
  it('sorts the sizes and clamps the counts to whole pairs', () => {
    // `inventory` comes back in insertion order, so an unsorted editor shows
    // `40, 41, 39` — and this draft is what gets written back to the database.
    assert.deepEqual(
      stockDraftFrom([
        { size: 'EU 41', stock: 4 },
        { size: 'EU 39', stock: -3 },
        { size: 'EU 40', stock: 2.7 },
      ]),
      [
        { size: 'EU 39', stock: 0 },
        { size: 'EU 40', stock: 2 },
        { size: 'EU 41', stock: 4 },
      ],
    )
  })

  it('is empty for the shapes a query can hand it', () => {
    assert.deepEqual(stockDraftFrom(null), [])
    assert.deepEqual(stockDraftFrom([{ size: '  ', stock: 3 }]), [])
  })
})

describe('isStockDraftDirty', () => {
  const saved = [
    { size: 'EU 40', stock: 2 },
    { size: 'EU 41', stock: 0 },
  ]

  it('is false for the same numbers, even out of order', () => {
    assert.equal(
      isStockDraftDirty(
        [
          { size: 'EU 41', stock: 0 },
          { size: 'EU 40', stock: 2 },
        ],
        saved,
      ),
      false,
    )
  })

  it('is true when a count moves, either way', () => {
    assert.equal(
      isStockDraftDirty(
        [
          { size: 'EU 40', stock: 3 },
          { size: 'EU 41', stock: 0 },
        ],
        saved,
      ),
      true,
    )
    assert.equal(
      isStockDraftDirty(
        [
          { size: 'EU 40', stock: 2 },
          { size: 'EU 41', stock: 1 },
        ],
        saved,
      ),
      true,
    )
  })

  it('is true when a size appears or disappears, because the write replaces the set', () => {
    assert.equal(isStockDraftDirty([{ size: 'EU 40', stock: 2 }], saved), true)
    assert.equal(
      isStockDraftDirty([...saved, { size: 'EU 42', stock: 0 }], saved),
      true,
    )
  })

  it('is false against an empty product with an empty draft', () => {
    assert.equal(isStockDraftDirty([], null), false)
  })
})

describe('stockDraftTotals', () => {
  it('counts sizes and pairs', () => {
    assert.deepEqual(
      stockDraftTotals([
        { size: 'EU 40', stock: 2 },
        { size: 'EU 41', stock: 3 },
      ]),
      { sizes: 2, pairs: 5 },
    )
  })

  it('is zeroes rather than NaN for anything else', () => {
    assert.deepEqual(stockDraftTotals(null), { sizes: 0, pairs: 0 })
    assert.deepEqual(stockDraftTotals([{ size: 'EU 40', stock: 'x' }]), {
      sizes: 1,
      pairs: 0,
    })
  })
})


describe('sizeStockChips', () => {
  it('reads a product back in size order, halves included', () => {
    // The order is `groupSizes`', which is the editor's and the storefront's:
    // a string sort would put `EU 41.5` after `EU 42`.
    const { groups } = sizeStockChips([
      { size: 'EU 42', stock: 4 },
      { size: 'EU 41.5', stock: 4 },
      { size: 'EU 40', stock: 4 },
      { size: 'EU 41', stock: 4 },
    ])

    assert.deepEqual(groups.map((group) => group.system), ['EU'])
    assert.deepEqual(
      groups[0].chips.map((chip) => chip.value),
      ['40', '41', '41.5', '42'],
    )
  })

  it('decides each chip the way the dashboard counts stock', () => {
    // The same three states and the same threshold as `stockState`, which is
    // what the dashboard's "Running out" figure is built from: a chip that
    // disagreed with that number would be a second answer to one question.
    const { groups } = sizeStockChips([
      { size: 'EU 35', stock: 0 },
      { size: 'EU 36', stock: 1 },
      { size: 'EU 37', stock: 5 },
      { size: 'EU 38', stock: 6 },
    ])

    assert.deepEqual(
      groups[0].chips.map((chip) => `${chip.value}:${chip.state}`),
      ['35:out', '36:low', '37:low', '38:in'],
    )
  })

  it('caps the TOTAL, and says how many it left out', () => {
    const inventory = Array.from({ length: 22 }, (_, index) => ({
      size: `EU ${40 + index}`,
      stock: 2,
    }))

    const chips = sizeStockChips(inventory, { limit: 8 })
    assert.equal(chips.shown, 8)
    assert.equal(chips.total, 22)
    assert.equal(chips.hidden, 14)
    assert.equal(chips.groups[0].chips.length, 8)
  })

  it('keeps more than one sizing system apart', () => {
    // A product can hold a size this form does not offer at all — `Other` is a
    // real answer, and re-labelling one as EU would change what is being sold.
    const { groups } = sizeStockChips([
      { size: 'EU 40', stock: 3 },
      { size: 'US 9', stock: 3 },
      { size: 'JP 25', stock: 3 },
    ])

    assert.deepEqual(
      groups.map((group) => group.system),
      ['US', 'EU', 'Other'],
    )
    assert.deepEqual(
      groups.map((group) => group.chips.map((chip) => chip.value).join(',')),
      ['9', '40', 'JP 25'],
    )
  })

  it('survives the shapes a query can hand it', () => {
    assert.deepEqual(sizeStockChips(null), {
      groups: [],
      total: 0,
      shown: 0,
      hidden: 0,
    })
    assert.deepEqual(sizeStockChips(undefined).groups, [])
    assert.deepEqual(sizeStockChips([{ size: '  ', stock: 4 }]).total, 0)
    assert.deepEqual(sizeStockChips([{ size: 'EU 40' }]).groups[0].chips, [
      { size: 'EU 40', value: '40', stock: 0, state: 'out' },
    ])
    assert.deepEqual(
      sizeStockChips([{ size: 'EU 40', stock: null }]).groups[0].chips[0].stock,
      0,
    )
  })

  it('returns no groups at all for a zero limit, rather than an empty chip', () => {
    const chips = sizeStockChips([{ size: 'EU 40', stock: 2 }], { limit: 0 })
    assert.deepEqual(chips.groups, [])
    assert.equal(chips.total, 1)
    assert.equal(chips.hidden, 1)
  })
})
