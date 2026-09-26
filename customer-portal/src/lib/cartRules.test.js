import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  cartCount,
  cartSubtotal,
  groupByStore,
  lineTotal,
  mapCartItem,
  normalizeSize,
  resolveInventoryStock,
  resolveVariant,
  unavailableReason,
} from './cartRules.js'

const PAST = '2020-01-01T00:00:00.000Z'
const FUTURE = '2099-01-01T00:00:00.000Z'

/** A `cart_items` row as PostgREST returns it, with just what the mapper reads. */
const row = (overrides = {}) => ({
  id: 'cart-1',
  user_id: 'user-1',
  product_id: 'prod-1',
  variant_id: null,
  quantity: 1,
  size: null,
  customizations: null,
  created_at: PAST,
  updated_at: PAST,
  products: {
    name: 'Heritage Cap-Toe Oxford',
    is_active: true,
    price: 1000,
    sale_price: null,
    sale_starts_at: null,
    sale_ends_at: null,
    store_id: 'store-1',
    product_images: [
      { image_url: 'second.jpg', display_order: 2 },
      { image_url: 'first.jpg', display_order: 0 },
    ],
  },
  product_variants: null,
  ...overrides,
})

describe('normalizeSize', () => {
  it('strips an alpha prefix', () => {
    assert.equal(normalizeSize('EU40'), '40')
    assert.equal(normalizeSize('US9'), '9')
  })

  it('strips letters but keeps other characters', () => {
    // Faithful to the app's `replaceAll(RegExp(r'[A-Za-z]+'), '')`. The space
    // in "US 9" survives, so "US 9" normalizes to " 9" and not "9". A trim()
    // here would look like a cleanup and would make this client disagree with
    // the app about whether a size is in stock — so the quirk is kept.
    assert.equal(normalizeSize('US 9'), ' 9')
    assert.equal(normalizeSize('40.5'), '40.5')
    assert.equal(normalizeSize(''), '')
  })
})

describe('resolveInventoryStock', () => {
  const rows = [
    { size: '8', stock: 0 },
    { size: '40', stock: 5 },
  ]

  it('prefers an exact match', () => {
    assert.equal(
      resolveInventoryStock({ inventoryRows: rows, cartSize: '8' }),
      0,
    )
    assert.equal(
      resolveInventoryStock({ inventoryRows: rows, cartSize: '40' }),
      5,
    )
  })

  it('falls back to a normalized match', () => {
    assert.equal(
      resolveInventoryStock({ inventoryRows: rows, cartSize: 'EU40' }),
      5,
    )
  })

  it('returns 0 — not -1 — for a size that exists with no stock', () => {
    // The distinction matters: -1 is "we could not find this size", 0 is "this
    // size is genuinely empty". Both block the sale, but only one is a data
    // problem worth surfacing.
    assert.equal(
      resolveInventoryStock({ inventoryRows: rows, cartSize: '8' }),
      0,
    )
  })

  it('returns -1 when nothing matches, rather than guessing', () => {
    assert.equal(
      resolveInventoryStock({ inventoryRows: rows, cartSize: '12' }),
      -1,
    )
    assert.equal(resolveInventoryStock({ inventoryRows: [], cartSize: '8' }), -1)
    assert.equal(resolveInventoryStock({ inventoryRows: rows, cartSize: '' }), -1)
  })

  it('keeps whitespace-consistent matches working', () => {
    assert.equal(
      resolveInventoryStock({
        inventoryRows: [{ size: 'EU 40', stock: 3 }],
        cartSize: 'US 40',
      }),
      3,
    )
  })
})

describe('resolveVariant', () => {
  const variants = [
    { id: 'v-brown-8', size: '8', color: 'Brown', stock: 2, additional_price: 0 },
    { id: 'v-black-8', size: '8', color: 'Black', stock: 3, additional_price: 50 },
    { id: 'v-8-nocolor', size: '9', color: null, stock: 1, additional_price: 0 },
  ]

  it('prefers the exact colour', () => {
    assert.deepEqual(
      resolveVariant({ variants, size: '8', color: 'Black' }),
      { variantId: 'v-black-8', additionalPrice: 50 },
    )
  })

  it('accepts any variant for the size when the colour differs', () => {
    const resolved = resolveVariant({ variants, size: '8', color: 'Green' })
    assert.ok(resolved.variantId === 'v-brown-8' || resolved.variantId === 'v-black-8')
  })

  it('carries the variant surcharge', () => {
    assert.equal(
      resolveVariant({ variants, size: '8', color: 'Black' }).additionalPrice,
      50,
    )
  })

  it('resolves a variant that has no colour at all', () => {
    assert.deepEqual(
      resolveVariant({ variants, size: '9', color: undefined }),
      { variantId: 'v-8-nocolor', additionalPrice: 0 },
    )
  })

  it('is null when no size matches — the cart row then stores no variant', () => {
    assert.deepEqual(resolveVariant({ variants, size: '11' }), {
      variantId: null,
      additionalPrice: 0,
    })
    assert.deepEqual(resolveVariant({ variants: [], size: '8' }), {
      variantId: null,
      additionalPrice: 0,
    })
  })
})

describe('mapCartItem', () => {
  it('recomputes the price from the product, not from a snapshot', () => {
    // cart_items persists NO price, so a live sale is picked up on the next
    // read even for a line added before the sale started.
    const item = mapCartItem(
      row({
        products: {
          ...row().products,
          price: 1000,
          sale_price: 700,
          sale_starts_at: PAST,
          sale_ends_at: FUTURE,
        },
      }),
    )
    assert.equal(item.basePrice, 700)
    assert.equal(item.unitPrice, 700)
  })

  it('adds the variant surcharge to the unit price', () => {
    const item = mapCartItem(
      row({
        size: '8',
        product_variants: { id: 'v1', size: '8', color: 'Black', stock: 3, additional_price: 50 },
      }),
    )
    assert.equal(item.basePrice, 1000)
    assert.equal(item.additionalPrice, 50)
    assert.equal(item.unitPrice, 1050)
  })

  it('takes the size from the CART first, then the variant, then inventory', () => {
    const withCartSize = mapCartItem(
      row({
        size: 'cart-choice',
        product_variants: { id: 'v1', size: 'variant-size', stock: 1 },
      }),
    )
    assert.equal(withCartSize.size, 'cart-choice')

    const fallsBackToVariant = mapCartItem(
      row({
        size: null,
        product_variants: { id: 'v1', size: 'variant-size', stock: 1 },
      }),
    )
    assert.equal(fallsBackToVariant.size, 'variant-size')

    const fallsBackToInventory = mapCartItem(row({ size: null, product_variants: null }), {
      inventorySizes: { 'prod-1': '40' },
    })
    assert.equal(fallsBackToInventory.size, '40')
  })

  it('takes stock from the variant, falling back to inventory for that size', () => {
    const fromVariant = mapCartItem(
      row({
        size: '8',
        product_variants: { id: 'v1', size: '8', stock: 4, additional_price: 0 },
      }),
    )
    assert.equal(fromVariant.stock, 4)

    const fromInventory = mapCartItem(
      row({ size: '40', product_variants: { id: 'v1', size: '40', stock: 0 } }),
      { inventoryStock: { 'prod-1-40': 7 } },
    )
    assert.equal(fromInventory.stock, 7)
  })

  it('uses the first image by display_order', () => {
    const item = mapCartItem(row())
    assert.equal(item.imageUrl, 'first.jpg')
  })

  it('names the store, with a stated fallback', () => {
    assert.equal(
      mapCartItem(row(), { storeNames: { 'store-1': 'Valladolid Leather Co.' } })
        .storeName,
      'Valladolid Leather Co.',
    )
    assert.equal(mapCartItem(row()).storeName, 'Unknown Store')
  })
})

describe('totals', () => {
  it('lineTotal is unitPrice × quantity', () => {
    assert.equal(lineTotal({ unitPrice: 1050, quantity: 2 }), 2100)
    assert.equal(lineTotal({ unitPrice: 1050 }), 1050)
  })

  it('subtotal sums the lines', () => {
    assert.equal(
      cartSubtotal([
        { unitPrice: 1000, quantity: 2 },
        { unitPrice: 500, quantity: 1 },
      ]),
      2500,
    )
    assert.equal(cartSubtotal([]), 0)
  })

  it('count counts UNITS, not lines — that is what the badge shows', () => {
    assert.equal(
      cartCount([
        { quantity: 2 },
        { quantity: 3 },
      ]),
      5,
    )
  })
})

describe('unavailableReason', () => {
  it('flags an unpublished product', () => {
    assert.equal(unavailableReason({ isActive: false, stock: 5, quantity: 1 }), 'No longer available')
  })

  it('flags an empty size', () => {
    assert.equal(unavailableReason({ isActive: true, stock: 0, quantity: 1 }), 'Out of stock')
  })

  it('flags asking for more than is left — the case a stock badge misses', () => {
    assert.equal(
      unavailableReason({ isActive: true, stock: 3, quantity: 5 }),
      'Only 3 left',
    )
  })

  it('is null when the line can be bought', () => {
    assert.equal(unavailableReason({ isActive: true, stock: 3, quantity: 3 }), null)
  })
})

describe('groupByStore', () => {
  it('groups by store in order of first appearance', () => {
    const groups = groupByStore([
      { storeId: 'a', storeName: 'Alpha', id: '1' },
      { storeId: 'b', storeName: 'Beta', id: '2' },
      { storeId: 'a', storeName: 'Alpha', id: '3' },
    ])

    assert.deepEqual(
      groups.map((group) => [group.storeName, group.items.map((item) => item.id)]),
      [
        ['Alpha', ['1', '3']],
        ['Beta', ['2']],
      ],
    )
  })

  it('keeps a line with no store rather than dropping it', () => {
    const groups = groupByStore([{ storeId: null, id: '1' }])
    assert.equal(groups.length, 1)
    assert.equal(groups[0].storeName, 'Unknown Store')
  })

  it('is empty for an empty cart', () => {
    assert.deepEqual(groupByStore([]), [])
  })
})
