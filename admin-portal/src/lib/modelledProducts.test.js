import { test } from 'node:test'
import assert from 'node:assert/strict'

import { pickModelledProducts } from './modelledProducts.js'

const product = (id, name = `Shoe ${id}`) => ({
  id,
  name,
  product_images: [{ image_url: `https://img/${id}.jpg`, is_primary: true, display_order: 0 }],
})

const row = (productId, version, extra = {}) => ({
  id: version,
  product_id: productId,
  status: 'active',
  version,
  authored_length_mm: 270,
  authored_size_eu: 42,
  storage_path: `store/${productId}/v${version}.glb`,
  products: product(productId),
  ...extra,
})

test('one entry per product, newest version wins', () => {
  const entries = pickModelledProducts([row('p1', 1), row('p1', 3), row('p1', 2), row('p2', 1)])

  assert.equal(entries.length, 2)
  assert.equal(entries.find((e) => e.productId === 'p1').model.version, 3)
  assert.equal(entries.find((e) => e.productId === 'p2').model.version, 1)
})

test('rows with no product or no file are dropped, never ghosts', () => {
  const entries = pickModelledProducts([
    row('p1', 1),
    row('p2', 1, { products: null }),
    row('p3', 1, { storage_path: '' }),
    row('p4', 1, { storage_path: null }),
  ])

  assert.deepEqual(
    entries.map((e) => e.productId),
    ['p1'],
  )
})

test('empty and missing input is an empty shelf, not a crash', () => {
  assert.deepEqual(pickModelledProducts([]), [])
  assert.deepEqual(pickModelledProducts(null), [])
  assert.deepEqual(pickModelledProducts(undefined), [])
})
