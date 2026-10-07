import assert from 'node:assert/strict'
import { test } from 'node:test'

import { productSavePlan } from './productSavePlan.js'

test('a form with no row at all creates one', () => {
  const plan = productSavePlan({ productId: null, createdId: null })
  assert.equal(plan.id, null)
  assert.equal(plan.row, 'create')
})

test('an edit route updates, and never creates a second product', () => {
  // The rule the whole form rests on: `/seller/products/:id` is an edit, whatever
  // else is true of the form.
  const plan = productSavePlan({ productId: 'product-1' })
  assert.equal(plan.id, 'product-1')
  assert.equal(plan.row, 'update')
})

test('a retry after a failed create updates the row that create made', () => {
  /*
    The case that is easy to get wrong, and was: the route is still `/new`, so a
    rule written as "create while the route is new" inserts a SECOND product on the
    second press of Save. Keeping the created id is what makes the retry finish the
    product instead.
  */
  const plan = productSavePlan({ productId: null, createdId: 'product-9' })
  assert.equal(plan.id, 'product-9')
  assert.equal(plan.row, 'update')
})

test('the photos a save sends are the batch, counted from what already landed', () => {
  const files = ['a.jpg', 'b.jpg']
  const plan = productSavePlan({ photos: files, photosStored: 3 })

  assert.deepEqual(plan.photos, files)
  // Behind the three already stored, so the cover stays where it is: order 0 is
  // written with `is_primary`, and only when nothing has landed yet.
  assert.equal(plan.photoStartOrder, 3)
  assert.equal(plan.photoCount, 5)
})

test('a create with photos counts them from zero, and owns the cover', () => {
  const plan = productSavePlan({ photos: ['a.jpg'] })
  assert.equal(plan.photoStartOrder, 0)
  assert.equal(plan.photoCount, 1)
})

test('a save with nothing pending sends no upload and still counts the photos', () => {
  const plan = productSavePlan({ createdId: 'product-9', photos: [], photosStored: 2 })
  assert.deepEqual(plan.photos, [])
  assert.equal(plan.photoCount, 2)
})

test('a nonsense stored count cannot move the batch or the cover', () => {
  // The count is arithmetic over a save that may have failed part-way; `NaN` in
  // `display_order` would be a row the storefront cannot order.
  for (const photosStored of [undefined, null, 'nonsense', NaN, -4]) {
    const plan = productSavePlan({ photos: ['a.jpg'], photosStored })
    assert.equal(plan.photoStartOrder, 0)
    assert.equal(plan.photoCount, 1)
  }
})

test('the photos list is copied, so a caller cannot mutate the plan into a retry', () => {
  const files = ['a.jpg']
  const plan = productSavePlan({ photos: files })
  plan.photos.push('b.jpg')
  assert.deepEqual(files, ['a.jpg'])
})
