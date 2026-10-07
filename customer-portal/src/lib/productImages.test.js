import assert from 'node:assert/strict'
import { test } from 'node:test'

import { dropIndexForPoint, imageOrderRows, moveImage } from './productImages.js'

/* A three-column grid of 100×100 tiles with a 10px gutter, the shape the Photos
   card draws — rows at y 0 / 110 / 220. */
const rects = [
  { left: 0, top: 0, width: 100, height: 100 }, // 0
  { left: 110, top: 0, width: 100, height: 100 }, // 1
  { left: 220, top: 0, width: 100, height: 100 }, // 2
  { left: 0, top: 110, width: 100, height: 100 }, // 3
  { left: 110, top: 110, width: 100, height: 100 }, // 4
  { left: 220, top: 110, width: 100, height: 100 }, // 5
  { left: 0, top: 220, width: 100, height: 100 }, // 6
  { left: 110, top: 220, width: 100, height: 100 }, // 7
]

test('a pointer inside a tile lands on that tile', () => {
  assert.equal(dropIndexForPoint(rects, { x: 50, y: 50 }), 0)
  assert.equal(dropIndexForPoint(rects, { x: 160, y: 160 }), 4)
  assert.equal(dropIndexForPoint(rects, { x: 160, y: 270 }), 7)
})

test('a pointer in the gutter between tiles still lands on the nearest one', () => {
  // Between tiles 1 and 2, and clearly nearer 1 than 2: a drop that landed
  // nowhere would read as the drag being broken.
  assert.equal(dropIndexForPoint(rects, { x: 205, y: 50 }), 1)
  assert.equal(dropIndexForPoint(rects, { x: 225, y: 50 }), 2)
  // Between the first and second rows, nearer the first.
  assert.equal(dropIndexForPoint(rects, { x: 50, y: 100 }), 0)
  assert.equal(dropIndexForPoint(rects, { x: 50, y: 111 }), 3)
})

test('a point exactly between two tiles goes to the earlier one', () => {
  /*
    Ties happen — (215, 50) is 55px from tile 1's centre and 55px from tile 2's —
    and a tie has to resolve the same way every time or the same drag lands in two
    different places on two identical grids. The first candidate wins, because the
    list is in the order the seller sees.
  */
  assert.equal(dropIndexForPoint(rects, { x: 215, y: 50 }), 1)
  assert.equal(dropIndexForPoint(rects, { x: 50, y: 105 }), 0)
})

test('hovering back over the dragged tile is a no-op, not a shuffle', () => {
  /*
    The rects include the dragged tile on purpose: if they did not, letting go over
    your own slot would resolve to an adjacent tile and move the photo one place
    every time the seller changed their mind.
  */
  const from = 4
  const point = { x: 160, y: 160 }
  assert.equal(dropIndexForPoint(rects, point), from)
  assert.deepEqual(moveImage(['a', 'b', 'c', 'd', 'e', 'f'], from, from), [
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
  ])
})

test('nothing measurable is null, never index 0', () => {
  // A detached grid would otherwise drop every photo at the front.
  assert.equal(dropIndexForPoint([null, null], { x: 0, y: 0 }), null)
  assert.equal(dropIndexForPoint([], { x: 0, y: 0 }), null)
  assert.equal(dropIndexForPoint(rects, null), null)
})

test('a move pushes the others along rather than trading places', () => {
  const list = ['a', 'b', 'c', 'd']
  assert.deepEqual(moveImage(list, 3, 0), ['d', 'a', 'b', 'c'])
  assert.deepEqual(moveImage(list, 0, 3), ['b', 'c', 'd', 'a'])
  assert.deepEqual(moveImage(list, 1, 2), ['a', 'c', 'b', 'd'])
  // The caller's list is untouched: the drop is applied to React state, and a
  // mutation in place would reorder the array the render is reading from.
  assert.deepEqual(list, ['a', 'b', 'c', 'd'])
})

test('a move that is out of range lands at the nearest real position', () => {
  const list = ['a', 'b', 'c']
  assert.deepEqual(moveImage(list, 5, 0), list)
  assert.deepEqual(moveImage(list, -1, 2), list)
  assert.deepEqual(moveImage(list, 0, 99), ['b', 'c', 'a'])
  assert.deepEqual(moveImage(list, 2, NaN), list)
})

test('the rows renumber from zero and mark the first as primary', () => {
  const rows = imageOrderRows({
    productId: 'product-1',
    images: [
      { id: 'img-3', url: 'https://bucket/three.jpg' },
      { id: 'img-1', url: 'https://bucket/one.jpg' },
    ],
  })

  assert.deepEqual(rows, [
    {
      id: 'img-3',
      product_id: 'product-1',
      image_url: 'https://bucket/three.jpg',
      display_order: 0,
      is_primary: true,
    },
    {
      id: 'img-1',
      product_id: 'product-1',
      image_url: 'https://bucket/one.jpg',
      display_order: 1,
      is_primary: false,
    },
  ])
})

test('a row without an id is dropped, because upsert would insert it', () => {
  // `upsert` conflicts on the primary key: a row with no id is not an update of
  // anything, it is a second row for the same photo.
  const rows = imageOrderRows({
    productId: 'product-1',
    images: [
      { id: 'img-1', url: 'https://bucket/one.jpg' },
      { id: null, url: 'https://bucket/two.jpg' },
      { id: 'img-3', url: null },
    ],
  })

  assert.equal(rows.length, 1)
  assert.equal(rows[0].id, 'img-1')
  assert.equal(rows[0].display_order, 0)
})
