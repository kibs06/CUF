import assert from 'node:assert/strict'
import test from 'node:test'

import {
  applyColourSheet,
  colourClash,
  hasRowsFor,
  removeColourEverywhere,
  rowSummary,
  rowsForColour,
} from './colourSheet.js'

/** Two colours, three sizes, one photograph each. */
function product() {
  return {
    variants: [
      { size: 'EU 40', color: 'Black', stock: 2, additional_price: 0, sku: '' },
      { size: 'EU 41', color: 'Black', stock: 3, additional_price: 0, sku: 'B-41' },
      { size: 'EU 40', color: 'Tan', stock: 1, additional_price: 0, sku: '' },
    ],
    colours: ['Black', 'Tan'],
    colourImages: {
      Black: [{ id: 'i1', url: 'black-1.jpg', displayOrder: 0 }],
      Tan: [{ id: 'i2', url: 'tan-1.jpg', displayOrder: 0 }],
    },
  }
}

const photo = { file: { name: 'tan-2.jpg' }, displayOrder: 0 }

test('rowsForColour takes one colour out, in the set’s own order', () => {
  const { variants } = product()
  assert.deepEqual(
    rowsForColour(variants, 'Black').map((row) => row.size),
    ['EU 40', 'EU 41'],
  )
  assert.deepEqual(rowsForColour(variants, 'Tan').map((row) => row.size), ['EU 40'])
  // A colour nothing names, and the uncoloured case, are both empty rather than
  // "everything" — the sheet edits one colour, not the product.
  assert.deepEqual(rowsForColour(variants, 'Navy'), [])
  assert.deepEqual(rowsForColour(variants, null), [])
})

test('colourClash is case-insensitive and ignores the colour being edited', () => {
  assert.match(colourClash(['Black', 'Tan'], 'black'), /already a colour/)
  assert.equal(colourClash(['Black', 'Tan'], 'Tan', 'Tan'), null)
  assert.equal(colourClash(['Black'], 'Tan', 'Tan'), null)
  assert.equal(colourClash(['Black'], 'Navy'), null)
  // A blank name is not a clash — it is a name, and `colourSheetProblems` says so.
  assert.equal(colourClash(['Black'], '   '), null)
})

test('rowSummary draws the raw count, and the extra price only when there is one', () => {
  assert.deepEqual(rowSummary({ size: 'EU 42', stock: '4', additional_price: '0' }), {
    size: 'EU 42',
    stock: 4,
    extra: 0,
    label: 'Stock: 4',
    extraLabel: null,
  })
  assert.equal(
    rowSummary({ size: 'EU 42', stock: 4, additional_price: 25.5 }).extraLabel,
    '+₱25.50',
  )
  // Nothing counted is drawn as zero rather than as `Stock: undefined`.
  assert.equal(rowSummary({ size: 'EU 40' }).label, 'Stock: 0')
})

test('a new colour joins the list with its photos and its rows', () => {
  const { variants, colours, colourImages } = product()
  const result = applyColourSheet({
    variants,
    colours,
    colourImages,
    previous: null,
    name: 'Navy',
    images: [photo],
    rows: [{ size: 'EU 40', color: 'Navy', stock: 5 }],
  })

  assert.equal(result.error, null)
  assert.deepEqual(result.colours, ['Black', 'Tan', 'Navy'])
  assert.deepEqual(result.colourImages.Navy, [photo])
  assert.equal(result.variants.filter((v) => v.color === 'Navy').length, 1)
  // The colours that were already there are untouched.
  assert.equal(result.variants.filter((v) => v.color === 'Black').length, 2)
})

test('a rename moves the rows, the photos and the list together', () => {
  const { variants, colours, colourImages } = product()
  const rows = rowsForColour(variants, 'Tan').map((row) => ({ ...row, stock: 9 }))
  const result = applyColourSheet({
    variants,
    colours,
    colourImages,
    previous: 'Tan',
    name: 'Carob',
    images: [...colourImages.Tan, photo],
    rows,
  })

  assert.equal(result.error, null)
  assert.deepEqual(result.colours, ['Black', 'Carob'])
  assert.equal(result.colourImages.Tan, undefined)
  assert.deepEqual(
    result.colourImages.Carob.map((image) => image.url ?? image.file.name),
    ['tan-1.jpg', 'tan-2.jpg'],
  )
  const carob = result.variants.filter((v) => v.color === 'Carob')
  assert.equal(carob.length, 1)
  assert.equal(carob[0].stock, 9)
  // Nothing still names the old colour — that is what makes the rename safe.
  assert.equal(result.variants.some((v) => v.color === 'Tan'), false)
})

test('a rename onto a colour that exists is refused, change and all', () => {
  const { variants, colours, colourImages } = product()
  const result = applyColourSheet({
    variants,
    colours,
    colourImages,
    previous: 'Tan',
    name: 'black',
    images: [],
    rows: [],
  })

  assert.match(result.error, /already a colour/)
  assert.equal(result.variants, variants)
  assert.deepEqual(result.colours, ['Black', 'Tan'])
})

test('a colour with no name is refused', () => {
  const { variants, colours, colourImages } = product()
  const result = applyColourSheet({
    variants,
    colours,
    colourImages,
    previous: null,
    name: '   ',
    images: [photo],
    rows: [],
  })
  assert.match(result.error, /name/)
  assert.deepEqual(result.colours, ['Black', 'Tan'])
})

test('saving a colour replaces its whole row set — a dropped size stays dropped', () => {
  const { variants, colours, colourImages } = product()
  const result = applyColourSheet({
    variants,
    colours,
    colourImages,
    previous: 'Black',
    name: 'Black',
    images: colourImages.Black,
    // EU 41 was taken off this colour, EU 43 added.
    rows: [
      { size: 'EU 40', color: 'Black', stock: 7, additional_price: 0, sku: '' },
      { size: 'EU 43', color: 'Black', stock: 1, additional_price: 0, sku: '' },
    ],
  })

  assert.equal(result.error, null)
  assert.deepEqual(
    result.variants.filter((v) => v.color === 'Black').map((v) => v.size),
    ['EU 40', 'EU 43'],
  )
  // Another colour's rows for the same sizes are not this sheet's to remove.
  assert.equal(result.variants.filter((v) => v.color === 'Tan').length, 1)
  assert.deepEqual(result.colours, ['Black', 'Tan'])
})

test('rows are stored under the name they are saved with, not the one they came in as', () => {
  const { variants, colours, colourImages } = product()
  const result = applyColourSheet({
    variants,
    colours,
    colourImages,
    previous: null,
    name: 'Carob',
    images: [photo],
    // Collected while the colour was still called something else — the phone's
    // rename-after-adding-sizes bug, which must not survive this merge.
    rows: [{ size: 'EU 44', color: '', stock: 3 }],
  })

  assert.equal(result.error, null)
  assert.deepEqual(
    result.variants.filter((v) => v.color === 'Carob').map((v) => v.size),
    ['EU 44'],
  )
  assert.equal(result.variants.some((v) => v.color === null), false)
})

test('a colour is removed from the rows, the list and the photos at once', () => {
  const { variants, colours, colourImages } = product()
  const result = removeColourEverywhere({ variants, colours, colourImages, name: 'Black' })

  assert.deepEqual(result.colours, ['Tan'])
  assert.deepEqual(result.colourImages.Black, undefined)
  assert.equal(result.variants.some((v) => v.color === 'Black'), false)
  assert.equal(result.variants.filter((v) => v.color === 'Tan').length, 1)
})

test('hasRowsFor answers the sheet’s "No sizes added yet"', () => {
  const { variants } = product()
  assert.equal(hasRowsFor(variants, 'Black'), true)
  assert.equal(hasRowsFor(variants, 'Navy'), false)
})
