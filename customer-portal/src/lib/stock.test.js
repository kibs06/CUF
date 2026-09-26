import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  availableSizes,
  isOutOfStock,
  purchasableProducts,
  stockForSize,
  totalStock,
} from './stock.js'

const withInventory = (inventory) => ({ id: 'p', inventory })

describe('totalStock', () => {
  it('sums every size', () => {
    assert.equal(
      totalStock(
        withInventory([
          { size: '7', stock: 2 },
          { size: '8', stock: 3 },
          { size: '9', stock: 0 },
        ]),
      ),
      5,
    )
  })

  it('reads the string numbers Supabase returns', () => {
    assert.equal(totalStock(withInventory([{ size: '8', stock: '4' }])), 4)
  })

  it('treats a missing stock value as zero rather than NaN', () => {
    // A NaN here would poison every downstream comparison: NaN <= 0 is false,
    // so the product would look IN stock and be unbuyable at checkout.
    assert.equal(
      totalStock(
        withInventory([{ size: '8', stock: null }, { size: '9', stock: 3 }]),
      ),
      3,
    )
  })

  it('is 0 for no rows, a non-array, or no product', () => {
    assert.equal(totalStock(withInventory([])), 0)
    assert.equal(totalStock({ inventory: null }), 0)
    assert.equal(totalStock({}), 0)
    assert.equal(totalStock(null), 0)
  })
})

describe('isOutOfStock', () => {
  it('is true at zero and below', () => {
    assert.equal(isOutOfStock(withInventory([{ size: '8', stock: 0 }])), true)
    assert.equal(isOutOfStock(withInventory([{ size: '8', stock: -3 }])), true)
  })

  it('is true for a product with no inventory rows at all', () => {
    // The app's "no match → out of stock" convention: legacy rows with no
    // inventory are unbuyable, not unlimited.
    assert.equal(isOutOfStock({ id: 'p' }), true)
  })

  it('is false as soon as ANY size has stock', () => {
    assert.equal(
      isOutOfStock(
        withInventory([
          { size: '8', stock: 0 },
          { size: '9', stock: 1 },
        ]),
      ),
      false,
    )
  })
})

describe('purchasableProducts', () => {
  it('hides exactly the unpurchasable ones', () => {
    const rows = [
      { id: 'a', inventory: [{ size: '8', stock: 0 }] },
      { id: 'b', inventory: [{ size: '8', stock: 2 }] },
      { id: 'c' }, // no inventory at all
      { id: 'd', inventory: [{ size: '8', stock: -1 }, { size: '9', stock: 0 }] },
    ]
    assert.deepEqual(
      purchasableProducts(rows).map((row) => row.id),
      ['b'],
    )
  })
})

describe('stockForSize', () => {
  it('is that size\u2019s stock', () => {
    const product = withInventory([
      { size: '8', stock: 4 },
      { size: '9', stock: 0 },
    ])
    assert.equal(stockForSize(product, '8'), 4)
    assert.equal(stockForSize(product, '9'), 0)
  })

  it('sums the rows that carry the size — one per colour', () => {
    // The cart sums them (its fallback stock is keyed `${productId}-${size}`),
    // so reading only the first row here struck a size through as sold out
    // while the cart would have accepted it (size plan §8 R4).
    const product = withInventory([
      { size: '8', stock: 2 },
      { size: '9', stock: 5 },
      { size: '8', stock: 3 },
    ])
    assert.equal(stockForSize(product, '8'), 5)
    assert.equal(stockForSize(product, '9'), 5)
  })

  it('is 0 for a size the product does not offer', () => {
    assert.equal(stockForSize(withInventory([{ size: '8', stock: 4 }]), '11'), 0)
    assert.equal(stockForSize({}, '8'), 0)
  })
})

describe('availableSizes', () => {
  it('lists each size once, in numeric order', () => {
    // Row order is whatever order the rows were written — the live catalog
    // hands back `40, 39, 40, 41.5`, so the grid used to read as a jumble. Two
    // rows for one size are two colours of it, not two choices.
    assert.deepEqual(
      availableSizes(
        withInventory([
          { size: '7' },
          { size: '8' },
          { size: '7' },
        ]),
      ),
      ['7', '8'],
    )
    assert.deepEqual(
      availableSizes(
        withInventory([
          { size: '42.5' },
          { size: '40' },
          { size: 'EU 41.5' },
          { size: '39' },
        ]),
      ),
      ['39', '40', 'EU 41.5', '42.5'],
    )
  })

  it('is empty without inventory', () => {
    assert.deepEqual(availableSizes({}), [])
    assert.deepEqual(availableSizes(null), [])
  })
})
