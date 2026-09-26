import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  allItemsSelected,
  cartItemKey,
  cartItemKeys,
  selectedDeliveryFee,
  selectedItems,
  selectedSubtotal,
  selectedTotal,
  selectedUnitCount,
  storeSelection,
  toggleAllSelection,
  toggleItemSelection,
  toggleStoreSelection,
} from './cartRules.js'

const FEE = 100

/** The cart's own line shape, trimmed to what selection reads. */
const line = (over = {}) => ({
  id: 'row-1',
  productId: 'p1',
  size: 'EU 39',
  color: null,
  quantity: 1,
  unitPrice: 100,
  storeId: 's1',
  storeName: 'Janella',
  ...over,
})

const CART = [
  line({ productId: 'p1', size: 'EU 39', quantity: 2, unitPrice: 100, storeId: 's1' }),
  line({ id: 'row-2', productId: 'p2', size: 'EU 41', quantity: 1, unitPrice: 150, storeId: 's1' }),
  line({ id: 'row-3', productId: 'p3', size: '8', quantity: 1, unitPrice: 300, storeId: 's2' }),
]

const keysOf = (cart) => new Set(cartItemKeys(cart))

describe('cartItemKey', () => {
  it('is the app’s own key: productId-size-color', () => {
    // `'$productId-$size-${color ?? 'none'}'` in CartProvider.addToCart. The
    // cart row's id is deliberately NOT used: a line that has not reached the
    // server yet has none, and a selection must survive a quantity change.
    assert.equal(cartItemKey(line()), 'p1-EU 39-none')
    assert.equal(cartItemKey(line({ color: 'Black' })), 'p1-EU 39-Black')
  })

  it('distinguishes sizes and colours of the same product', () => {
    const a = cartItemKey(line({ size: 'EU 39' }))
    const b = cartItemKey(line({ size: 'EU 40' }))
    const c = cartItemKey(line({ color: 'Tan' }))
    assert.equal(new Set([a, b, c]).size, 3)
  })

  it('does not collide with a product id that contains a dash', () => {
    // Real ids are UUIDs; the composite is only ever compared to another
    // composite built the same way, so a dash inside a field is harmless.
    assert.equal(cartItemKey(line({ productId: 'a-b' })), 'a-b-EU 39-none')
  })
})

describe('what the selection totals', () => {
  it('counts units, not lines — the button must agree with the badge', () => {
    const two = new Set([cartItemKey(CART[0])])
    assert.equal(selectedUnitCount(CART, two), 2)
    assert.equal(selectedUnitCount(CART, keysOf(CART)), 4)
  })

  it('totals only the selected lines', () => {
    assert.equal(selectedSubtotal(CART, new Set([cartItemKey(CART[0])])), 200)
    assert.equal(selectedSubtotal(CART, new Set([cartItemKey(CART[2])])), 300)
    assert.equal(selectedSubtotal(CART, keysOf(CART)), 650)
    assert.equal(selectedSubtotal(CART, new Set()), 0)
  })

  it('charges the delivery fee ONCE, not per maker', () => {
    // The app's `selectedDeliveryFee => selectedSubtotal > 0 ? 100.0 : 0.0`.
    // A two-maker selection is still one fee, because checkout creates one
    // order for one maker — this is what used to make the cart quote ₱651 and
    // the payment then take ₱551.
    const bothMakers = new Set([cartItemKey(CART[0]), cartItemKey(CART[2])])
    assert.equal(selectedDeliveryFee(CART, bothMakers, FEE), 100)
    // ₱200 (two pairs) + ₱300 (one pair) + ONE ₱100 fee — not ₱200 of fees.
    assert.equal(selectedTotal(CART, bothMakers, FEE), 600)
  })

  it('charges nothing when nothing is selected', () => {
    assert.equal(selectedDeliveryFee(CART, new Set(), FEE), 0)
    assert.equal(selectedTotal(CART, new Set(), FEE), 0)
  })

  it('returns the selected lines themselves, in cart order', () => {
    assert.deepEqual(
      selectedItems(CART, keysOf(CART)).map((item) => item.id),
      ['row-1', 'row-2', 'row-3'],
    )
    assert.deepEqual(
      selectedItems(CART, new Set([cartItemKey(CART[2]), cartItemKey(CART[0])])).map(
        (item) => item.id,
      ),
      ['row-1', 'row-3'],
    )
  })

  it('survives an empty cart and a missing selection', () => {
    assert.equal(selectedSubtotal([], new Set()), 0)
    assert.equal(selectedSubtotal(null, null), 0)
    assert.deepEqual(selectedItems(undefined, undefined), [])
    assert.equal(allItemsSelected([], new Set()), false)
  })
})

describe('the three checkbox states', () => {
  it('is all, some or none per store', () => {
    assert.equal(storeSelection(CART, new Set(), 's1'), 'none')
    assert.equal(storeSelection(CART, new Set([cartItemKey(CART[0])]), 's1'), 'some')
    assert.equal(storeSelection(CART, keysOf(CART), 's1'), 'all')
  })

  it('is none for a store that is not in the cart', () => {
    assert.equal(storeSelection(CART, keysOf(CART), 'nope'), 'none')
    assert.equal(storeSelection(CART, keysOf(CART), null), 'none')
  })

  it('knows when everything is selected', () => {
    assert.equal(allItemsSelected(CART, keysOf(CART)), true)
    assert.equal(allItemsSelected(CART, new Set([cartItemKey(CART[0])])), false)
  })
})

describe('toggling', () => {
  it('adds a line, then removes it', () => {
    const once = toggleItemSelection(new Set(), CART[0])
    assert.equal(once.has(cartItemKey(CART[0])), true)
    assert.equal(toggleItemSelection(once, CART[0]).has(cartItemKey(CART[0])), false)
  })

  it('never mutates the set it was given', () => {
    // React state: mutating the Set in place would not re-render.
    const original = new Set()
    toggleItemSelection(original, CART[0])
    assert.equal(original.size, 0)
  })

  it('selects a whole store, and clears a fully selected one', () => {
    const all = toggleStoreSelection(new Set(), CART, 's1')
    assert.deepEqual([...all].sort(), [cartItemKey(CART[0]), cartItemKey(CART[1])].sort())
    assert.equal(all.has(cartItemKey(CART[2])), false)
    assert.equal(toggleStoreSelection(all, CART, 's1').size, 0)
  })

  it('completes a partly selected store rather than clearing it', () => {
    // The indeterminate middle state has to behave like "select all of these",
    // or half-selected is a coin toss.
    const partial = new Set([cartItemKey(CART[0])])
    const completed = toggleStoreSelection(partial, CART, 's1')
    assert.equal(completed.has(cartItemKey(CART[0])), true)
    assert.equal(completed.has(cartItemKey(CART[1])), true)
  })

  it('toggles everything, both ways', () => {
    assert.equal(toggleAllSelection(new Set(), CART).size, 3)
    assert.equal(toggleAllSelection(keysOf(CART), CART).size, 0)
  })
})

describe('the selection and the cart stay in step', () => {
  it('ignores an id that is no longer in the cart', () => {
    // Removing a line must not leave a ghost in the totals.
    const stale = new Set([cartItemKey(CART[0]), 'p9-EU 40-none'])
    assert.equal(selectedUnitCount(CART, stale), 2)
    assert.equal(selectedSubtotal(CART, stale), 200)
  })

  it('keeps the selection through a quantity change', () => {
    const keys = new Set([cartItemKey(CART[0])])
    const bigger = [{ ...CART[0], quantity: 3 }, CART[1], CART[2]]
    assert.equal(selectedUnitCount(bigger, keys), 3)
    assert.equal(selectedSubtotal(bigger, keys), 300)
  })
})
