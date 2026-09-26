import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  MAX_COLOUR_IMAGES,
  addColourImage,
  colourImagePath,
  colourImagesFor,
  colourPhotoNotes,
  colourSheetProblems,
  colourSlug,
  colourSummaries,
  colourThumbnail,
  removeColourImageAt,
  removeColourImages,
  renameColourImages,
} from './productColourImages.js'

const ROWS = [
  { size: 'EU 42', color: 'Tan', stock: 2 },
  { size: 'EU 42', color: 'Black', stock: 3 },
  { size: 'EU 41', color: 'Tan', stock: 1 },
  { size: 'EU 41', color: null, stock: 4 },
]

const IMAGES = {
  Tan: [
    { id: 9, url: 'tan-2.jpg', displayOrder: 1 },
    { id: 8, url: 'tan-1.jpg', displayOrder: 0 },
  ],
  Black: [{ id: 10, url: null, file: { name: 'black.jpg' }, displayOrder: 0 }],
}

test('colourSlug: the app\u2019s own path rule, space included', () => {
  assert.equal(colourSlug('Burnished Clay'), 'Burnished_Clay')
  assert.equal(colourSlug('Off-white suede'), 'Off-white_suede')
  assert.equal(colourSlug('Black'), 'Black')
  // Nothing usable at all still has to be a path segment rather than an empty
  // directory name.
  assert.equal(colourSlug('  '), 'colour')
  assert.equal(colourSlug(''), 'colour')
})

test('colourImagePath: the app\u2019s layout, colours in their own folder', () => {
  assert.equal(
    colourImagePath({
      sellerId: 'seller-1',
      productId: 'prod-9',
      colourName: 'Burnished Clay',
      index: 2,
      ext: 'png',
      at: 1700000000000,
    }),
    'seller-1/prod-9/colors/Burnished_Clay/1700000000000_2.png',
  )
  // The first segment is the seller id, because the bucket's policy checks it.
  assert.equal(
    colourImagePath({ sellerId: 'a', productId: 'b', colourName: 'Tan' }).startsWith('a/b/colors/Tan/'),
    true,
  )
})

test('colourImagesFor: display order, not the order Postgres returns', () => {
  assert.deepEqual(
    colourImagesFor(IMAGES, 'Tan').map((image) => image.url),
    ['tan-1.jpg', 'tan-2.jpg'],
  )
  assert.deepEqual(colourImagesFor(IMAGES, 'Olive'), [])
  assert.deepEqual(colourImagesFor(undefined, 'Tan'), [])
})

test('colourThumbnail: the first STORED photo is the cover', () => {
  // The app marks index 0 "Main" and draws the first image that has a URL — a
  // pending file has none, so it cannot be a card's cover.
  assert.equal(colourThumbnail(IMAGES, 'Tan'), 'tan-1.jpg')
  assert.equal(colourThumbnail(IMAGES, 'Black'), null)
})

test('colourSummaries: photos, sizes and stock, from their three tables', () => {
  const summaries = colourSummaries({
    colours: ['Tan', 'Black', 'Olive'],
    variants: ROWS,
    colourImages: IMAGES,
  })

  assert.deepEqual(summaries[0], {
    name: 'Tan',
    photos: 2,
    pending: 0,
    sizes: 2,
    stock: 3,
    label: '2 photos · 2 sizes · 3 in stock',
  })
  // One pending upload counts as a photo: to the seller it is one.
  assert.equal(summaries[1].label, '1 photo · 1 size · 3 in stock')
  assert.equal(summaries[1].pending, 1)
  // A colour with neither is the state the product-level note is about.
  assert.equal(summaries[2].label, '0 photos · 0 sizes · 0 in stock')
})

test('colourSummaries: the uncoloured bucket is not a colour', () => {
  // `color: null` rows belong to the "No colour" card, which is the bucket the
  // app has no card for and this form has to keep.
  const [plain] = colourSummaries({ colours: ['', 'Tan'], variants: ROWS })
  assert.equal(plain.sizes, 1)
  assert.equal(plain.stock, 4)
})

test('colourSheetProblems: the app\u2019s own two conditions, and its cap', () => {
  assert.deepEqual(colourSheetProblems({ name: 'Tan', images: [{ url: 'a' }] }).errors, [])
  assert.deepEqual(colourSheetProblems({ name: 'Tan', images: [] }).errors, [
    'Add at least one photo — a customer picks a colour by its photo.',
  ])
  assert.deepEqual(colourSheetProblems({ name: '  ', images: [{ url: 'a' }] }).errors, [
    'Give the colour a name.',
  ])
  assert.equal(
    colourSheetProblems({
      name: 'Tan',
      images: Array.from({ length: MAX_COLOUR_IMAGES + 1 }, (_, at) => ({ url: `p${at}` })),
    }).errors.length,
    1,
  )
})

test('colourPhotoNotes: a colour with no photos is a prompt, never a block', () => {
  // Every coloured product in the catalog predates this table; refusing to save
  // one would be the portal refusing what the app accepts.
  const notes = colourPhotoNotes({ colours: ['Tan', 'Black', 'Olive'], colourImages: IMAGES })
  assert.deepEqual(notes, [
    'Olive has no photos yet — customers see the product\u2019s own photos for it.',
  ])
  assert.deepEqual(colourPhotoNotes({ colours: [], colourImages: IMAGES }), [])
})

test('addColourImage: appended, and the next display order', () => {
  const next = addColourImage([{ url: 'a', displayOrder: 0 }], { file: { name: 'b.jpg' } })
  assert.deepEqual(next, [
    { url: 'a', displayOrder: 0 },
    { file: { name: 'b.jpg' }, displayOrder: 1 },
  ])
  assert.deepEqual(addColourImage(undefined, { url: 'a' }), [{ url: 'a', displayOrder: 0 }])
})

test('removeColourImageAt: the next photo becomes the cover, renumbered', () => {
  const next = removeColourImageAt(colourImagesFor(IMAGES, 'Tan'), 0)
  assert.deepEqual(next, [{ id: 9, url: 'tan-2.jpg', displayOrder: 0 }])
  assert.equal(colourThumbnail({ Tan: next }, 'Tan'), 'tan-2.jpg')
})

test('renameColourImages: a rename takes the gallery with it', () => {
  // The name is the join key, so a gallery left under the old name is a colour
  // with photos nothing can find.
  const next = renameColourImages(IMAGES, 'Tan', 'Sand')
  assert.equal(next.Tan, undefined)
  assert.deepEqual(next.Sand.map((image) => image.url), ['tan-1.jpg', 'tan-2.jpg'])
  assert.equal(next.Sand[0].displayOrder, 0)
  assert.equal(colourThumbnail(next, 'Sand'), 'tan-1.jpg')
})

test('renameColourImages: renaming onto a colour that has photos keeps both', () => {
  const next = renameColourImages(IMAGES, 'Tan', 'Black')
  assert.equal(next.Tan, undefined)
  assert.equal(next.Black.length, 3)
  assert.deepEqual(next.Black.map((image) => image.url ?? image.file.name), [
    'black.jpg',
    'tan-1.jpg',
    'tan-2.jpg',
  ])
})

test('renameColourImages and removeColourImages leave the rest alone', () => {
  assert.deepEqual(Object.keys(renameColourImages(IMAGES, 'Tan', 'Tan')), ['Tan', 'Black'])
  assert.deepEqual(Object.keys(removeColourImages(IMAGES, 'Tan')), ['Black'])
  assert.deepEqual(removeColourImages(IMAGES, 'Olive'), IMAGES)
})
