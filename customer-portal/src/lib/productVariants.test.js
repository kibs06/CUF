import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  UNCOLOURED,
  addColour,
  addSize,
  applyVariantSheet,
  colourOf,
  coloursFromVariants,
  findVariant,
  inventoryRowsFromVariants,
  blankSheetEntry,
  normaliseColour,
  removeColour,
  removeSize,
  renameColour,
  replaceColourRows,
  setVariantField,
  sheetEntriesForColour,
  sheetPreview,
  sheetProblems,
  sheetRows,
  sheetSaveLabel,
  sizesFromVariants,
  variantColumns,
  variantProblems,
  variantRowsForInsert,
  variantTotals,
  variantsFromProduct,
} from './productVariants.js'

/* The shape that reaches the form from `mapSellerProduct`. */
const COLOURED = [
  { id: 1, size: 'EU 42', color: 'Tan', stock: 2, additional_price: 0, sku: null },
  { id: 2, size: 'EU 42', color: 'Black', stock: 3, additional_price: 50, sku: 'B-42' },
  { id: 3, size: 'EU 41', color: 'Tan', stock: 1, additional_price: 0, sku: null },
  { id: 4, size: 'EU 41', color: 'Black', stock: 0, additional_price: 50, sku: 'B-41' },
]

/*
  What the portal wrote before it could express colours at all — and what
  `mapSellerProduct` still hands back for most products in the catalog: one row
  per size with `color: null` and nothing else.
*/
const PLAIN = [
  { size: 'EU 42', color: null, stock: 2, additional_price: 0, sku: null },
  { size: 'EU 41', color: null, stock: 1, additional_price: 0, sku: null },
]

test('normaliseColour: blank is UNCOLOURED, not an empty string', () => {
  assert.equal(normaliseColour('  Tan '), 'Tan')
  assert.equal(normaliseColour(''), UNCOLOURED)
  assert.equal(normaliseColour('   '), UNCOLOURED)
  assert.equal(normaliseColour(null), UNCOLOURED)
  assert.equal(normaliseColour(undefined), UNCOLOURED)
  assert.equal(colourOf({ color: ' Black ' }), 'Black')
  assert.equal(colourOf({}), UNCOLOURED)
})

test('variantColumns: no colours means the one uncoloured column', () => {
  assert.deepEqual(variantColumns(PLAIN, []), [UNCOLOURED])
  assert.deepEqual(variantColumns([], []), [UNCOLOURED])
  assert.deepEqual(variantColumns(COLOURED, ['Tan', 'Black']), ['Tan', 'Black'])
})

test('variantColumns keeps a colourless column that really has rows', () => {
  // The table can hold both shapes at once (the app's form cannot), and a form
  // that assumed one of them would drop the other's stock on the next save.
  const mixed = [...PLAIN, { size: 'EU 40', color: 'Tan', stock: 1 }]
  assert.deepEqual(variantColumns(mixed, ['Tan']), [UNCOLOURED, 'Tan'])
})

test('coloursFromVariants is first-appearance order, not alphabetical', () => {
  assert.deepEqual(coloursFromVariants(COLOURED), ['Tan', 'Black'])
  assert.deepEqual(coloursFromVariants([{ size: 'EU 41', color: 'Zebra' }, { color: 'Apple' }]), [
    'Zebra',
    'Apple',
  ])
  assert.deepEqual(coloursFromVariants(PLAIN), [])
})

test('sizesFromVariants sorts numerically, halves in the right place', () => {
  const sizes = sizesFromVariants([
    { size: 'EU 40' },
    { size: 'EU 39.5' },
    { size: 'EU 41' },
    { size: 'EU 9.5' },
    { size: 'EU 42' },
  ])
  // Numeric within the system, which is the whole point: a string sort puts
  // '9.5' after '42' and a lexicographic one puts it before '39.5' but also
  // puts '40' before '39.5'.
  assert.deepEqual(sizes, ['EU 9.5', 'EU 39.5', 'EU 40', 'EU 41', 'EU 42'])
  assert.deepEqual(sizesFromVariants([{ size: 'EU 42' }, { size: 'EU 42' }]), ['EU 42'])
  assert.deepEqual(sizesFromVariants([{ size: '  ' }, { size: null }]), [])
})

test('variantsFromProduct orders the grid: sizes down, colours across', () => {
  const rows = variantsFromProduct([
    { size: 'EU 42', color: 'Black', stock: 3 },
    { size: 'EU 41', color: 'Tan', stock: 1 },
    { size: 'EU 42', color: 'Tan', stock: 2 },
    { size: 'EU 41', color: 'Black', stock: 0 },
  ])
  // Size-major, and within a size the colours in first-appearance order — the
  // order the rows were written in, which is the order the editor drew them.
  assert.deepEqual(
    rows.map((row) => `${row.size}/${row.color ?? '—'}`),
    ['EU 41/Black', 'EU 41/Tan', 'EU 42/Black', 'EU 42/Tan'],
  )
})

test('variantsFromProduct coerces what Postgres returns', () => {
  const [row] = variantsFromProduct([
    { size: 'EU 42', color: null, stock: '3', additional_price: '25.5', sku: ' A-1 ' },
  ])
  assert.deepEqual(row, {
    size: 'EU 42',
    color: null,
    stock: 3,
    additional_price: 25.5,
    sku: 'A-1',
  })

  // And what it cannot read becomes a number, never NaN: a NaN stock is a
  // `<input value={NaN}>` React warns about and a CHECK constraint would reject.
  const [odd] = variantsFromProduct([{ size: 'EU 42', stock: 'many' }])
  assert.equal(odd.stock, 0)
  assert.equal(odd.additional_price, 0)
  assert.equal(odd.sku, '')
})

test('findVariant matches on trimmed size and colour, exactly', () => {
  assert.equal(findVariant(COLOURED, 'EU 42', 'Tan')?.id, 1)
  assert.equal(findVariant(COLOURED, 'EU 42', ' Tan ')?.id, 1)
  assert.equal(findVariant(PLAIN, 'EU 42', null)?.size, 'EU 42')
  assert.equal(findVariant(COLOURED, 'EU 43', 'Tan'), undefined)
  /*
    Case is not folded, and it does not need to be: `renameColour` refuses a
    name that differs only in case, so 'Tan' and 'tan' are never two colours —
    and the editor looks up cells by a name it took from this same list.
  */
  assert.equal(findVariant(COLOURED, 'EU 42', 'tan'), undefined)
})

test('setVariantField touches one cell and clamps its numbers', () => {
  const next = setVariantField(COLOURED, 'EU 42', 'Tan', 'stock', '-4')
  assert.equal(findVariant(next, 'EU 42', 'Tan').stock, 0)
  // Every other cell is untouched, identity included.
  assert.equal(findVariant(next, 'EU 42', 'Black').stock, 3)

  const priced = setVariantField(next, 'EU 42', 'Tan', 'additional_price', '99.5')
  assert.equal(findVariant(priced, 'EU 42', 'Tan').additional_price, 99.5)
  assert.equal(findVariant(priced, 'EU 42', 'Tan').stock, 0)

  const blank = setVariantField(priced, 'EU 42', 'Tan', 'additional_price', '')
  assert.equal(findVariant(blank, 'EU 42', 'Tan').additional_price, 0)
})

test('addSize adds the size in every column at zero', () => {
  const next = addSize(COLOURED, ['Tan', 'Black'], 'EU 40')
  assert.deepEqual(
    next
      .filter((row) => row.size === 'EU 40')
      .map((row) => [row.color, row.stock]),
    [
      ['Tan', 0],
      ['Black', 0],
    ],
  )
  // Idempotent: turning the size on twice does not double its rows.
  assert.equal(addSize(next, ['Tan', 'Black'], 'EU 40').length, next.length)
})

test('addSize on a plain product adds the one uncoloured row', () => {
  const next = addSize(PLAIN, [UNCOLOURED], 'EU 40')
  const added = next.filter((row) => row.size === 'EU 40')
  assert.equal(added.length, 1)
  assert.equal(added[0].color, null)

  // And with an empty column list it still adds one, because the columns of a
  // colourless product are the one uncoloured column.
  assert.equal(addSize(PLAIN, [], 'EU 40').length, 3)
})

test('removeSize takes the size out of every colour', () => {
  const next = removeSize(COLOURED, 'EU 42')
  assert.deepEqual(
    next.map((row) => row.size),
    ['EU 41', 'EU 41'],
  )
  assert.equal(removeSize(COLOURED, 'EU 43').length, COLOURED.length)
})

test('addColour adds the NAME only, and refuses blanks and repeats', () => {
  /*
    A colour's sizes come from its own sheet, so a new colour starts at "0 sizes"
    — seeding a row per existing size would invent sizes nobody chose, which is
    what this used to do back when the grid was the only editor.
  */
  const { variants, colours } = addColour(PLAIN, [], 'Tan')
  assert.deepEqual(colours, ['Tan'])
  assert.deepEqual(variants, PLAIN)

  // A blank or repeated name changes nothing.
  assert.deepEqual(addColour(PLAIN, [], '  '), { variants: PLAIN, colours: [] })
  const again = addColour(variants, colours, 'Tan')
  assert.deepEqual(again, { variants: PLAIN, colours: ['Tan'] })
})

test('removeColour takes its rows with it', () => {
  const { variants, colours } = removeColour(COLOURED, ['Tan', 'Black'], 'Tan')
  assert.deepEqual(colours, ['Black'])
  assert.deepEqual(
    variants.map((row) => row.color),
    ['Black', 'Black'],
  )
})

test('renameColour rewrites the rows, and refuses a clash', () => {
  const renamed = renameColour(COLOURED, ['Tan', 'Black'], 'Tan', 'Chestnut')
  assert.equal(renamed.error, null)
  assert.deepEqual(renamed.colours, ['Chestnut', 'Black'])
  assert.deepEqual(coloursFromVariants(renamed.variants), ['Chestnut', 'Black'])
  assert.equal(
    renamed.variants.filter((row) => row.color === 'Chestnut').length,
    2,
  )

  // Two columns under one name is a colour selector showing the same colour
  // twice, and merging their stock is a decision about pairs nobody made.
  const clash = renameColour(COLOURED, ['Tan', 'Black'], 'Tan', 'black')
  assert.equal(clash.error, 'You already have a colour called black.')
  assert.deepEqual(clash.variants, COLOURED)

  assert.equal(renameColour(COLOURED, ['Tan'], 'Tan', '   ').error, 'A colour needs a name.')
  assert.equal(renameColour(COLOURED, ['Tan'], 'Tan', 'Tan').error, null)
})

test('variantRowsForInsert writes the column shape, blank SKU as NULL', () => {
  const rows = variantRowsForInsert([
    { size: ' EU 42 ', color: ' Tan ', stock: 2, additional_price: 0, sku: '  ' },
    { size: 'EU 41', color: null, stock: -3, additional_price: '10', sku: 'A-1' },
    { size: '   ', color: 'Tan', stock: 9 },
  ])
  assert.deepEqual(rows, [
    {
      size: 'EU 42',
      color: 'Tan',
      stock: 2,
      additional_price: 0,
      sku: null,
    },
    { size: 'EU 41', color: null, stock: 0, additional_price: 10, sku: 'A-1' },
  ])
})

test('inventoryRowsFromVariants sums the colours, one row per size', () => {
  assert.deepEqual(inventoryRowsFromVariants(COLOURED), [
    { size: 'EU 41', stock: 1 },
    { size: 'EU 42', stock: 5 },
  ])
  // A sold-out size is kept: the row is what makes the size offered, and the
  // storefront draws it as sold out rather than dropping it from the product.
  assert.deepEqual(inventoryRowsFromVariants([{ size: 'EU 41', stock: 0 }]), [
    { size: 'EU 41', stock: 0 },
  ])
  assert.deepEqual(inventoryRowsFromVariants([]), [])
})

test('inventoryRowsFromVariants matches the app’s own grouping', () => {
  // `_syncInventoryFromVariants` groups by size and ignores colour entirely;
  // this is that arithmetic, so the customer's size grid reads what the seller
  // typed on either surface.
  const rows = inventoryRowsFromVariants([
    { size: 'EU 42', color: 'Tan', stock: 2 },
    { size: 'EU 42', color: 'Black', stock: 3 },
    { size: 'EU 41', color: 'Tan', stock: 1 },
    { size: 'EU 41', color: 'Black', stock: 0 },
    { size: 'EU 41.5', color: 'Black', stock: 4 },
  ])
  assert.deepEqual(rows, [
    { size: 'EU 41', stock: 1 },
    { size: 'EU 41.5', stock: 4 },
    { size: 'EU 42', stock: 5 },
  ])
})

test('variantTotals counts sizes, colours, cells and pairs', () => {
  assert.deepEqual(variantTotals(COLOURED, ['Tan', 'Black']), {
    sizes: 2,
    colours: 2,
    rows: 4,
    pairs: 6,
  })
  assert.deepEqual(variantTotals(PLAIN, []), {
    sizes: 2,
    colours: 0,
    rows: 2,
    pairs: 3,
  })
})

test('variantProblems: an unnamed colour blocks the save', () => {
  const { errors } = variantProblems({ variants: COLOURED, colours: ['Tan', ''] })
  assert.deepEqual(errors, [
    'Every colour needs a name — give it one, or remove the column.',
  ])
})

test('variantProblems: two colours with one name block the save', () => {
  const { errors } = variantProblems({
    variants: COLOURED,
    colours: ['Tan', 'black', 'Black'],
  })
  assert.deepEqual(errors, ['Two colours are both named Black.'])
})

test('variantProblems: a colour with no sizes is a note, not an error', () => {
  // It saves exactly as drawn — the colour simply is not stored, because nothing
  // in the schema records a colour except the rows that name it. Blocking would
  // be a rule the app's own form does not have.
  const { errors, notes } = variantProblems({
    variants: COLOURED,
    colours: ['Tan', 'Black', 'Olive'],
  })
  assert.deepEqual(errors, [])
  assert.deepEqual(notes, [
    'Olive has no sizes yet, so nothing is stored for that colour.',
  ])
})

test('variantProblems says nothing about a product it cannot fault', () => {
  assert.deepEqual(variantProblems({ variants: COLOURED, colours: ['Tan', 'Black'] }), {
    errors: [],
    notes: [],
  })
  assert.deepEqual(variantProblems({ variants: PLAIN, colours: [] }), {
    errors: [],
    notes: [],
  })
})

test('variantProblems: one cell named twice blocks the save', () => {
  /*
    The grid draws a box per cell, so two rows for one cell draw ONE box — and the
    storefront's `resolveVariant` takes the first match while `saveProductVariants`
    writes both. Only the sheet can produce it, and it is refused there first, but
    the state can also arrive from Postgres.
  */
  const doubled = [...COLOURED, { size: 'EU 42', color: 'Black', stock: 1 }]
  assert.deepEqual(variantProblems({ variants: doubled, colours: ['Tan', 'Black'] }), {
    errors: ['Two variants are both Black in EU 42 — keep one.'],
    notes: [],
  })

  const colourless = [...PLAIN, { size: 'EU 42', color: null, stock: 4 }]
  assert.deepEqual(variantProblems({ variants: colourless, colours: [] }), {
    errors: ['Two variants are both EU 42 with no colour — keep one.'],
    notes: [],
  })
})

test('variantProblems: one cell per size and colour is fine, colour included', () => {
  // The check is per (size, colour) and not per size: `EU 41` and `EU 42` both
  // having a Black row is a two-size product, not a fault.
  assert.deepEqual(variantProblems({ variants: COLOURED, colours: ['Tan', 'Black'] }).errors, [])
})

test('sheetEntriesForColour: a size this colour has opens with its own row', () => {
  assert.deepEqual(sheetEntriesForColour(COLOURED, 'Tan', 'EU 42'), [
    { stock: '2', additional_price: '', sku: '' },
  ])
  assert.deepEqual(sheetEntriesForColour(COLOURED, 'Black', 'EU 42'), [
    { stock: '3', additional_price: '50', sku: 'B-42' },
  ])
  // Sold out is `'0'` and never counted is `''` — two different things, and the
  // dialog draws them differently.
  assert.deepEqual(sheetEntriesForColour(COLOURED, 'Black', 'EU 41'), [
    { stock: '0', additional_price: '50', sku: 'B-41' },
  ])
})

test('sheetEntriesForColour: a size this colour does not have opens empty', () => {
  // Not the other colours' rows: the sheet is editing ONE colour, so a size it
  // does not stock is a size being added.
  assert.deepEqual(sheetEntriesForColour(COLOURED, 'Tan', 'EU 43'), [blankSheetEntry()])
  assert.deepEqual(blankSheetEntry(), { stock: '', additional_price: '', sku: '' })
})

test('sheetEntriesForColour: re-opening a size and saving it changes nothing', () => {
  // The property that makes the sheet safe as an editor: seed → apply is a no-op
  // for a size nobody touched.
  const next = applyVariantSheet(COLOURED, {
    colour: 'Tan',
    sizes: ['EU 42'],
    entries: { 'EU 42': sheetEntriesForColour(COLOURED, 'Tan', 'EU 42') },
  })

  assert.deepEqual(
    variantRowsForInsert(next),
    variantRowsForInsert(variantsFromProduct(COLOURED)),
  )
})

test('sheetRows: the sheet’s colour is every row’s colour', () => {
  const rows = sheetRows({
    colour: 'Tan',
    sizes: ['EU 42', 'EU 41'],
    entries: {
      'EU 42': [
        { stock: '2', additional_price: '', sku: ' T-42 ' },
        { stock: '3', additional_price: '50', sku: '' },
      ],
    },
  })

  assert.deepEqual(rows, [
    { size: 'EU 42', color: 'Tan', stock: 2, additional_price: 0, sku: 'T-42' },
    { size: 'EU 42', color: 'Tan', stock: 3, additional_price: 50, sku: '' },
    // EU 41 was picked and never given an entry — one row at zero, which is what
    // "I make this size and have not counted it yet" is.
    { size: 'EU 41', color: 'Tan', stock: 0, additional_price: 0, sku: '' },
  ])
})

test('sheetRows: a colourless sheet writes colourless rows', () => {
  // The "No colour" card's sheet — the bucket the app has no card for and this
  // form keeps for the products already in the catalog.
  assert.deepEqual(sheetRows({ colour: '', sizes: ['EU 42'], entries: {} }), [
    { size: 'EU 42', color: UNCOLOURED, stock: 0, additional_price: 0, sku: '' },
  ])
  assert.equal(sheetRows({ sizes: ['EU 42'], entries: {} })[0].color ?? null, null)
})

test('sheetRows: a size with no name is dropped, not written blank', () => {
  assert.deepEqual(sheetRows({ colour: 'Tan', sizes: ['  ', 'EU 42'], entries: {} }), [
    { size: 'EU 42', color: 'Tan', stock: 0, additional_price: 0, sku: '' },
  ])
  assert.deepEqual(sheetRows({}), [])
  assert.deepEqual(sheetRows(undefined), [])
})

test('sheetProblems: no sizes picked is the one way to get nowhere', () => {
  assert.deepEqual(sheetProblems({ sizes: [], entries: {} }).errors, [
    'Pick at least one size first.',
  ])
  assert.deepEqual(sheetProblems({ sizes: ['EU 42'], entries: {} }).errors, [])
})

test('sheetProblems: one size, twice', () => {
  // An entry carries no colour of its own any more — the sheet's colour is the
  // rows' colour — so two entries for one size are two rows for one cell, which
  // is the shape `variantProblems` cannot express.
  const { errors } = sheetProblems({
    colour: 'Tan',
    sizes: ['EU 42'],
    entries: { 'EU 42': [blankSheetEntry(), blankSheetEntry()] },
  })
  assert.deepEqual(errors, ['You have two Tan rows for EU 42 — keep one.'])
})

test('sheetProblems: two colourless rows for one size are the same fault', () => {
  const { errors } = sheetProblems({
    colour: '',
    sizes: ['EU 42'],
    entries: { 'EU 42': [blankSheetEntry(), blankSheetEntry()] },
  })
  assert.deepEqual(errors, ['You have two rows with no colour for EU 42 — keep one.'])
})

test('sheetProblems: one row per size in two sizes is not a fault', () => {
  const { errors } = sheetProblems({
    colour: 'Black',
    sizes: ['EU 41', 'EU 42'],
    entries: { 'EU 41': [blankSheetEntry()], 'EU 42': [blankSheetEntry()] },
  })
  assert.deepEqual(errors, [])
})

test('applyVariantSheet: adds this colour’s size and leaves the others alone', () => {
  const next = applyVariantSheet(COLOURED, {
    colour: 'Tan',
    sizes: ['EU 43'],
    entries: {},
  })

  assert.equal(next.length, 5)
  for (const before of COLOURED) {
    const after = findVariant(next, before.size, before.color)
    assert.equal(after.stock, before.stock, `${before.size}/${before.color}`)
    assert.equal(after.additional_price, before.additional_price)
  }
  assert.equal(findVariant(next, 'EU 43', 'Tan').stock, 0)
  // The size was added to ONE colour: no Black row was invented for it.
  assert.equal(findVariant(next, 'EU 43', 'Black'), undefined)
})

test('applyVariantSheet: rows come back in size order', () => {
  const next = applyVariantSheet([], {
    colour: 'Tan',
    sizes: ['EU 43', 'EU 40', 'EU 41'],
    entries: {},
  })
  assert.deepEqual(next.map((row) => row.size), ['EU 40', 'EU 41', 'EU 43'])
})

test('applyVariantSheet: the picked sizes are REPLACED for this colour', () => {
  const next = applyVariantSheet(COLOURED, {
    colour: 'Tan',
    sizes: ['EU 42'],
    entries: { 'EU 42': [{ stock: '9' }] },
  })

  // Tan's EU 42 is now 9 with nothing extra...
  assert.deepEqual(findVariant(next, 'EU 42', 'Tan'), {
    size: 'EU 42',
    color: 'Tan',
    stock: 9,
    additional_price: 0,
    sku: '',
  })
  /*
    ...and Black's EU 42 is exactly as it was. This is the whole reason the sheet
    carries a colour: without the scope these four lines are where a seller loses
    a colour's stock by editing another one's.
  */
  assert.deepEqual(findVariant(next, 'EU 42', 'Black'), {
    size: 'EU 42',
    color: 'Black',
    stock: 3,
    additional_price: 50,
    sku: 'B-42',
  })
  assert.equal(findVariant(next, 'EU 41', 'Tan').stock, 1)
})

test('applyVariantSheet: this colour keeps its rows the sheet did not mention', () => {
  /*
    The other half of the scope, and the easier half to get wrong: EU 42 is being
    edited, and Tan's EU 41 — which the sheet never mentioned — has to still be
    there afterwards.
  */
  const next = applyVariantSheet(COLOURED, {
    colour: 'Tan',
    sizes: ['EU 42'],
    entries: { 'EU 42': [{ stock: '9' }] },
  })
  assert.equal(findVariant(next, 'EU 41', 'Tan').stock, 1)
})

test('applyVariantSheet: a new colour is appended to the columns', () => {
  // `indexOf` on a colour that is not in the order yet is -1, which would sort a
  // brand new colour in front of every existing one.
  const next = applyVariantSheet(COLOURED, {
    colour: 'Gold',
    sizes: ['EU 42'],
    entries: {},
  })
  assert.deepEqual(
    [...new Set(next.map((row) => row.color))],
    ['Tan', 'Black', 'Gold'],
  )
})

test('replaceColourRows: the whole colour is swapped, nothing else moves', () => {
  const next = replaceColourRows(COLOURED, 'Tan', [
    { size: 'EU 44', color: 'Tan', stock: 5 },
  ])
  // A set, not a patch: the sizes this colour is not in any more are gone.
  assert.equal(findVariant(next, 'EU 42', 'Tan'), undefined)
  assert.equal(findVariant(next, 'EU 41', 'Tan'), undefined)
  assert.equal(findVariant(next, 'EU 44', 'Tan').stock, 5)
  // And Black — which the colour sheet was not editing — is exactly as it was.
  assert.equal(findVariant(next, 'EU 42', 'Black').stock, 3)
  assert.equal(findVariant(next, 'EU 41', 'Black').additional_price, 50)
})

test('replaceColourRows: a brand new colour keeps the others first', () => {
  const next = replaceColourRows(COLOURED, 'Gold', [
    { size: 'EU 42', color: 'Gold', stock: 1 },
  ])
  assert.deepEqual(
    [...new Set(next.map((row) => row.color))],
    ['Tan', 'Black', 'Gold'],
  )
})

test('applyVariantSheet: a colourless sheet does not touch the coloured rows', () => {
  const both = [...COLOURED, { size: 'EU 42', color: null, stock: 7 }]
  const next = applyVariantSheet(both, { colour: '', sizes: ['EU 42'], entries: {} })
  assert.equal(findVariant(next, 'EU 42', UNCOLOURED).stock, 0)
  assert.equal(findVariant(next, 'EU 42', 'Tan').stock, 2)
  assert.equal(findVariant(next, 'EU 42', 'Black').stock, 3)
})

test('applyVariantSheet: the result is what would be written, not a draft', () => {
  // The same rows `saveProductVariants` inserts, so "shown" and "written" cannot
  // drift: stock and price coerced, blank SKUs left blank, sizes grouped.
  const next = applyVariantSheet([], {
    colour: 'Tan',
    sizes: ['EU 41'],
    entries: { 'EU 41': [{ stock: '-4', additional_price: 'x' }] },
  })
  assert.deepEqual(variantRowsForInsert(next), [
    { size: 'EU 41', color: 'Tan', stock: 0, additional_price: 0, sku: null },
  ])
})

test('sheetPreview: counts rows, and says when it is an update', () => {
  const adding = sheetPreview(COLOURED, { colour: 'Tan', sizes: ['EU 43'], entries: {} })
  assert.deepEqual(adding, { count: 1, updating: false })

  const updating = sheetPreview(COLOURED, { colour: 'Tan', sizes: ['EU 42'], entries: {} })
  assert.deepEqual(updating, { count: 1, updating: true })

  // A size another colour stocks is still an INSERT for this one: a button that
  // said "Update" would be describing the wrong kind of write.
  const other = sheetPreview(COLOURED, { colour: 'Gold', sizes: ['EU 42'], entries: {} })
  assert.deepEqual(other, { count: 1, updating: false })
})

test('sheetPreview: the count is rows, not sizes', () => {
  // Two entries for each of three sizes is six rows written, which is the number
  // the button has to say.
  const preview = sheetPreview([], {
    colour: 'Tan',
    sizes: ['EU 40', 'EU 41', 'EU 42'],
    entries: {
      'EU 40': [blankSheetEntry(), blankSheetEntry()],
      'EU 41': [blankSheetEntry(), blankSheetEntry()],
      'EU 42': [blankSheetEntry(), blankSheetEntry()],
    },
  })
  assert.deepEqual(preview, { count: 6, updating: false })
})

test('sheetSaveLabel: the app\'s own words', () => {
  assert.equal(sheetSaveLabel(0, false), 'Add variant')
  assert.equal(sheetSaveLabel(1, false), 'Add variant')
  assert.equal(sheetSaveLabel(3, false), 'Add 3 variants')
  assert.equal(sheetSaveLabel(1, true), 'Update variant')
  assert.equal(sheetSaveLabel(3, true), 'Update 3 variants')
})
