import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  euSizeLabel,
  euSizeValue,
  sizeBadgeFor,
  kPlausibleEuMax,
  kPlausibleEuMin,
  matchStockedSize,
  productsInMySize,
  shoppingEuSizeFrom,
  sizeAdvice,
  SIZE_MATCH_KIND,
  stockByEuSize,
  stocksMySize,
} from './sizeMatchRules.js'

/**
 * A mirror of `test/utils/size_match_test.dart`.
 *
 * The cases that matter are the ones where being *confidently wrong* would be
 * worse than saying nothing: a size stored in another system, a bare value
 * outside the app's bands, a sold-out exact size, and the near-size band.
 */
const productWithStock = (rows) => ({
  id: 'p',
  name: 'Artisan Shoe',
  inventory: rows.map(([size, stock]) => ({ size, stock })),
})

describe('stockByEuSize — the authoritative source', () => {
  it('keys inventory rows by EU size', () => {
    const stock = stockByEuSize(
      productWithStock([
        ['EU 42', 3],
        ['EU 43', 0],
      ]),
    )

    assert.equal(stock.get(42), 3)
    assert.equal(stock.get(43), 0)
  })

  it("a bare size counts as EU (the default system)", () => {
    assert.equal(stockByEuSize(productWithStock([['42', 5]])).get(42), 5)
  })

  it('sums a size across colours', () => {
    // Black EU 42: 2 + Brown EU 42: 3 → 5 available on EU 42.
    const stock = stockByEuSize(
      productWithStock([
        ['EU 42', 2],
        ['EU 42', 3],
      ]),
    )

    assert.equal(stock.get(42), 5)
  })

  it('a prefixed size is converted, not read as its digits', () => {
    // US 9 (men) = EU 42.
    const stock = stockByEuSize(productWithStock([['US 9', 4]]))

    assert.equal(stock.get(42), 4)
    assert.equal(stock.has(9), false)
  })

  it('a system we own no chart for is skipped', () => {
    // 'JP 25' is not EU 25 — guessing here is the wrong-claim risk.
    assert.equal(stockByEuSize(productWithStock([['JP 25', 9]])).size, 0)
  })

  it('a bare value outside the plausible band is skipped', () => {
    // A bare '9' is far more likely a US 9 than an EU 9.
    assert.equal(stockByEuSize(productWithStock([['9', 4]])).size, 0)
    assert.equal(stockByEuSize(productWithStock([['60', 4]])).size, 0)
    assert.equal(kPlausibleEuMin, 22)
    assert.equal(kPlausibleEuMax, 48)
  })

  it("a child's size is matched like anyone else's", () => {
    assert.equal(stockByEuSize(productWithStock([['28', 2]])).get(28), 2)
  })

  it('a product with no size data yields nothing', () => {
    assert.equal(stockByEuSize({ id: 'p' }).size, 0)
    assert.equal(stockByEuSize({ id: 'p', inventory: 'nonsense' }).size, 0)
    assert.equal(stockByEuSize(null).size, 0)
  })

  it('product_variants alone are NOT the stock source', () => {
    // inventory is authoritative; variants are derived from it. Reading both
    // could claim stock the buy button does not have (plan R4).
    const product = {
      id: 'p',
      product_variants: [{ size: 'EU 42', stock: 9 }],
    }

    assert.equal(stockByEuSize(product).size, 0)
    assert.equal(stocksMySize(product, 42), false)
  })

  it('reads the string numbers PostgREST can return', () => {
    // The Dart version casts (`as num?`) and would throw on a string; the
    // portal's stock.js is tolerant of them, so this is too.
    assert.equal(stockByEuSize(productWithStock([['EU 42', '4']])).get(42), 4)
    assert.equal(stockByEuSize(productWithStock([['EU 42', null]])).get(42), 0)
  })
})

describe('matchStockedSize', () => {
  it('an exact size in stock is an exact match', () => {
    const match = matchStockedSize(productWithStock([['EU 42', 2]]), 42)

    assert.equal(match.kind, SIZE_MATCH_KIND.exact)
    assert.equal(match.euSize, 42)
    assert.equal(match.stock, 2)
    assert.equal(match.isAvailable, true)
  })

  it('a sold-out exact size still answers, and reads as unavailable', () => {
    // The product DOES sell EU 42. Offering EU 41.5 instead would be a
    // different shoe on a different fit.
    const match = matchStockedSize(
      productWithStock([
        ['EU 42', 0],
        ['EU 41.5', 4],
      ]),
      42,
    )

    assert.equal(match.kind, SIZE_MATCH_KIND.exact)
    assert.equal(match.stock, 0)
    assert.equal(match.isAvailable, false)
    assert.equal(stocksMySize(productWithStock([['EU 42', 0]]), 42), false)
  })

  it('a half size away answers as near, and is never substituted', () => {
    const match = matchStockedSize(productWithStock([['EU 41.5', 3]]), 42)

    assert.equal(match.kind, SIZE_MATCH_KIND.near)
    assert.equal(match.euSize, 41.5)
    assert.equal(match.isAvailable, true)
    // Near is not "my size": a suggestion shelf must not include it.
    assert.equal(stocksMySize(productWithStock([['EU 41.5', 3]]), 42), false)
  })

  it('a whole size away is not close enough to mention', () => {
    assert.equal(matchStockedSize(productWithStock([['EU 43', 3]]), 42), null)
  })

  it("equally-near sizes resolve down, never above the customer's size", () => {
    // 41.5 and 42.5 are both 0.5 away.
    const match = matchStockedSize(
      productWithStock([
        ['EU 42.5', 2],
        ['EU 41.5', 2],
      ]),
      42,
    )

    assert.equal(match.euSize, 41.5)
  })

  it('no size data at all is null, not a guess', () => {
    assert.equal(matchStockedSize({ id: 'p' }, 42), null)
  })
})

describe('shoppingEuSizeFrom — where "my size" comes from', () => {
  it('the profile snapshot is the answer', () => {
    assert.equal(shoppingEuSizeFrom({ foot_size_ph: 42 }), 42)
    // Stored as a string, and pre-labelled — both are the same size.
    assert.equal(shoppingEuSizeFrom({ foot_size_ph: '42' }), 42)
    assert.equal(shoppingEuSizeFrom({ foot_size_ph: 'EU 42.5' }), 42.5)
  })

  it('nothing anywhere is null — every surface then renders nothing', () => {
    assert.equal(shoppingEuSizeFrom(null), null)
    assert.equal(shoppingEuSizeFrom({}), null)
    assert.equal(shoppingEuSizeFrom({ foot_size_ph: null }), null)
    assert.equal(shoppingEuSizeFrom({ foot_size_ph: '   ' }), null)
    assert.equal(shoppingEuSizeFrom({ foot_size_ph: 'not a size' }), null)
  })
})

describe('euSizeLabel / euSizeValue', () => {
  it('names the system and drops the pointless decimal', () => {
    assert.equal(euSizeLabel(42), 'EU 42')
    assert.equal(euSizeLabel(42.5), 'EU 42.5')
  })

  it('prints the number alone for a heading that labels the unit itself', () => {
    assert.equal(euSizeValue(42), '42')
    assert.equal(euSizeValue(42.5), '42.5')
    assert.equal(euSizeValue(22), '22')
  })
})

describe('productsInMySize — the shelf’s inclusion rule', () => {
  const catalog = [
    { id: 'in-stock', inventory: [{ size: 'EU 42', stock: 2 }] },
    { id: 'sold-out', inventory: [{ size: 'EU 42', stock: 0 }] },
    { id: 'near-only', inventory: [{ size: 'EU 41.5', stock: 3 }] },
    { id: 'other-size', inventory: [{ size: 'EU 44', stock: 5 }] },
    { id: 'no-data' },
  ]

  it('keeps only the products that stock my size right now', () => {
    assert.deepEqual(
      productsInMySize(catalog, 42).map((product) => product.id),
      ['in-stock'],
    )
  })

  it('is empty without a size — absent profile, absent shelf', () => {
    assert.deepEqual(productsInMySize(catalog, null), [])
    assert.deepEqual(productsInMySize(catalog, undefined), [])
    assert.deepEqual(productsInMySize(null, 42), [])
  })
})

describe('sizeBadgeFor — the tag on a product card', () => {
  it('tags an exact size in stock with the size alone', () => {
    assert.deepEqual(sizeBadgeFor(productWithStock([['EU 42', 2]]), 42), {
      tone: 'in-stock',
      label: 'EU 42',
    })
  })

  it('tags a sold-out exact size as sold out, in the same slot', () => {
    assert.deepEqual(sizeBadgeFor(productWithStock([['EU 42', 0]]), 42), {
      tone: 'sold-out',
      label: 'EU 42 sold out',
    })
  })

  it('does NOT tag a near size — a tag claims buyability', () => {
    // The shelf and the tag agree: near is excluded from both. Only the product
    // page, which has room to say "closest is", ever mentions it.
    assert.equal(sizeBadgeFor(productWithStock([['EU 41.5', 4]]), 42), null)
    assert.deepEqual(
      productsInMySize([{ id: 'near', inventory: [{ size: 'EU 41.5', stock: 4 }] }], 42),
      [],
    )
  })

  it('says nothing without a size, without size data, or out of band', () => {
    assert.equal(sizeBadgeFor(productWithStock([['EU 42', 2]]), null), null)
    assert.equal(sizeBadgeFor({ id: 'p' }, 42), null)
    assert.equal(sizeBadgeFor(productWithStock([['JP 25', 9]]), 42), null)
    assert.equal(sizeBadgeFor(productWithStock([['EU 44', 9]]), 42), null)
  })

  it('a tag means the cart would accept the pair', () => {
    // The R4 invariant: the tag's "available" is `stocksMySize`, which is the
    // same inventory sum the cart's stock comes from.
    const product = productWithStock([
      ['EU 42', 0],
      ['EU 42', 3],
    ])
    const badge = sizeBadgeFor(product, 42)

    assert.equal(badge.tone, 'in-stock')
    assert.equal(stocksMySize(product, 42), true)
  })
})

describe('sizeAdvice — what a product page is allowed to say', () => {
  it('names the size and the count when it can be bought', () => {
    assert.deepEqual(sizeAdvice(productWithStock([['EU 42', 3]]), 42), {
      tone: 'in-stock',
      text: 'In your size · EU 42 · 3 left',
    })
  })

  it('says sold out rather than offering the next size down', () => {
    assert.deepEqual(
      sizeAdvice(
        productWithStock([
          ['EU 42', 0],
          ['EU 41.5', 4],
        ]),
        42,
      ),
      { tone: 'sold-out', text: 'In your size · EU 42 · sold out' },
    )
  })

  it('names the closest as closest — never as the customer’s size', () => {
    assert.deepEqual(sizeAdvice(productWithStock([['EU 41.5', 6]]), 42), {
      tone: 'near',
      text: "EU 42 isn't available — closest is EU 41.5",
    })
  })

  it('says nothing when there is nothing honest to say', () => {
    assert.equal(sizeAdvice(productWithStock([['EU 44', 5]]), 42), null)
    assert.equal(sizeAdvice({ id: 'p' }, 42), null)
    assert.equal(sizeAdvice(productWithStock([['JP 25', 5]]), 42), null)
    assert.equal(sizeAdvice(productWithStock([['EU 42', 1]]), null), null)
  })

  it('the half-size case from the plan: EU 42 profile, 42.5 catalog', () => {
    const advice = sizeAdvice(productWithStock([['EU 42.5', 3]]), 42)
    assert.equal(advice.tone, 'near')
    assert.equal(advice.text, "EU 42 isn't available — closest is EU 42.5")
  })
})
