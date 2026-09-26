import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  earliestSaleEnd,
  effectivePrice,
  isOnSale,
  maxDiscountPercent,
  saleDateInput,
  saleDateValue,
  salePercent,
  salePreview,
  salePriceProblem,
  saleWindowNote,
} from './pricing.js'

// A fixed clock. Every date case below is relative to it, so these tests do
// not start failing on a particular afternoon.
const NOW = new Date('2026-09-25T12:00:00.000Z')

/** A product with sane defaults, so each case names only what it is testing. */
const product = (overrides = {}) => ({
  price: 1000,
  sale_price: null,
  ...overrides,
})

describe('isOnSale', () => {
  it('is false when there is no sale price at all', () => {
    assert.equal(isOnSale(product(), NOW), false)
    assert.equal(isOnSale(product({ sale_price: null }), NOW), false)
  })

  it('is false for a cleared sale (zero or negative price)', () => {
    assert.equal(isOnSale(product({ sale_price: 0 }), NOW), false)
    assert.equal(isOnSale(product({ sale_price: -50 }), NOW), false)
  })

  it('is false unless the sale price is STRICTLY below the price', () => {
    assert.equal(isOnSale(product({ sale_price: 1000 }), NOW), false)
    assert.equal(isOnSale(product({ sale_price: 1200 }), NOW), false)
    assert.equal(isOnSale(product({ sale_price: 999.99 }), NOW), true)
  })

  it('is true with no dates set — an open-ended sale', () => {
    assert.equal(isOnSale(product({ sale_price: 800 }), NOW), true)
  })

  it('is false before the sale has started', () => {
    assert.equal(
      isOnSale(
        product({
          sale_price: 800,
          sale_starts_at: '2026-09-26T00:00:00.000Z',
        }),
        NOW,
      ),
      false,
    )
  })

  it('is true inside the window', () => {
    assert.equal(
      isOnSale(
        product({
          sale_price: 800,
          sale_starts_at: '2026-09-20T00:00:00.000Z',
          sale_ends_at: '2026-09-30T00:00:00.000Z',
        }),
        NOW,
      ),
      true,
    )
  })

  it('is false after the sale has ended', () => {
    assert.equal(
      isOnSale(
        product({
          sale_price: 800,
          sale_starts_at: '2026-09-01T00:00:00.000Z',
          sale_ends_at: '2026-09-20T00:00:00.000Z',
        }),
        NOW,
      ),
      false,
    )
  })

  it('treats both boundaries as INSIDE the sale', () => {
    // The Dart rule is `now.isBefore(start)` / `now.isAfter(end)`, so an exact
    // match is on sale on both ends. An exclusive comparison here would blink
    // the badge off for one second at midnight.
    assert.equal(
      isOnSale(
        product({ sale_price: 800, sale_starts_at: NOW.toISOString() }),
        NOW,
      ),
      true,
    )
    assert.equal(
      isOnSale(
        product({ sale_price: 800, sale_ends_at: NOW.toISOString() }),
        NOW,
      ),
      true,
    )
  })

  it('reads the string numbers Supabase actually returns', () => {
    assert.equal(
      isOnSale({ price: '1000.00', sale_price: '800.00' }, NOW),
      true,
    )
  })

  it('is false when the price is missing, whatever the sale price', () => {
    // price coerces to 0, and any positive sale price is >= 0.
    assert.equal(isOnSale({ sale_price: 500 }, NOW), false)
  })

  it('is false for an unparseable sale price', () => {
    assert.equal(isOnSale(product({ sale_price: 'abc' }), NOW), false)
    assert.equal(isOnSale(product({ sale_price: '2026-09-25' }), NOW), false)
  })

  it('survives a null product rather than throwing', () => {
    assert.equal(isOnSale(null, NOW), false)
    assert.equal(isOnSale(undefined, NOW), false)
  })
})

describe('effectivePrice', () => {
  it('is the sale price while the sale is active', () => {
    assert.equal(effectivePrice(product({ sale_price: 800 }), NOW), 800)
  })

  it('falls back to the original price when not on sale', () => {
    assert.equal(effectivePrice(product(), NOW), 1000)
    assert.equal(
      effectivePrice(
        product({ sale_price: 800, sale_ends_at: '2026-09-01T00:00:00.000Z' }),
        NOW,
      ),
      1000,
    )
  })

  it('is 0 rather than NaN when the price is missing', () => {
    assert.equal(effectivePrice({ sale_price: 800 }, NOW), 0)
  })
})

describe('salePercent', () => {
  it('is ROUNDED, because it names one product', () => {
    assert.equal(salePercent(product({ sale_price: 800 }), NOW), 20)
    // 66.66% → 67
    assert.equal(salePercent(product({ price: 1000, sale_price: 333 }), NOW), 67)
  })

  it('is null when not on sale, or when the price is unusable', () => {
    assert.equal(salePercent(product(), NOW), null)
    assert.equal(salePercent({ price: 0, sale_price: 1 }, NOW), null)
  })
})

describe('maxDiscountPercent', () => {
  it('is FLOORED, because it is a claim about the whole shelf', () => {
    // 33.33% off must advertise 33: rounding up would promise a discount no
    // product in the catalog actually offers.
    assert.equal(
      maxDiscountPercent([product({ price: 3000, sale_price: 2000 })], NOW),
      33,
    )
  })

  it('takes the best discount among the live sales', () => {
    assert.equal(
      maxDiscountPercent(
        [
          product({ sale_price: 900 }), // 10%
          product({ sale_price: 500 }), // 50%
          product({ sale_price: 800 }), // 20%
        ],
        NOW,
      ),
      50,
    )
  })

  it('ignores products whose sale is not live', () => {
    assert.equal(
      maxDiscountPercent(
        [
          product({ sale_price: 800 }), // not on sale
          product({
            sale_price: 100,
            sale_ends_at: '2026-09-01T00:00:00.000Z', // expired
          }),
        ],
        NOW,
      ),
      20,
    )
  })

  it('is null when nothing is on sale', () => {
    assert.equal(maxDiscountPercent([product()], NOW), null)
    assert.equal(maxDiscountPercent([], NOW), null)
  })
})

describe('earliestSaleEnd', () => {
  it('is the soonest end among the live sales', () => {
    assert.deepEqual(
      earliestSaleEnd(
        [
          product({ sale_price: 800, sale_ends_at: '2026-09-30T00:00:00.000Z' }),
          product({ sale_price: 700, sale_ends_at: '2026-09-27T00:00:00.000Z' }),
        ],
        NOW,
      ),
      new Date('2026-09-27T00:00:00.000Z'),
    )
  })

  it('skips an open-ended sale rather than reporting "never"', () => {
    assert.deepEqual(
      earliestSaleEnd(
        [
          product({ sale_price: 800 }),
          product({ sale_price: 700, sale_ends_at: '2026-09-27T00:00:00.000Z' }),
        ],
        NOW,
      ),
      new Date('2026-09-27T00:00:00.000Z'),
    )
  })

  it('is null when no live sale has an end date', () => {
    assert.equal(earliestSaleEnd([product({ sale_price: 800 })], NOW), null)
    assert.equal(earliestSaleEnd([], NOW), null)
  })
})

/*
  The writing side. These test the rules the *form* enforces against the rules
  the readers above implement, and that is the point of having both in one file:
  a `salePriceProblem` that let through a price `isOnSale` would ignore is a form
  that writes a sale nobody can see.
*/
describe('salePriceProblem', () => {
  const at = (salePrice, price = 1000) => salePriceProblem({ price, salePrice })

  it('passes any price strictly below the base price', () => {
    assert.equal(at(1), null)
    assert.equal(at(999.99), null)
    assert.equal(at('750'), null)
  })

  it('refuses the app’s own case, in the app’s own words', () => {
    assert.equal(at(1000), 'Sale price must be lower than the base price.')
    assert.equal(at(1200), 'Sale price must be lower than the base price.')
    assert.equal(at('1000'), 'Sale price must be lower than the base price.')
    // A free product has no price to undercut, so anything at or above zero is
    // refused: the app's guard is the same comparison.
    assert.equal(at(0, 0), null)
    assert.equal(at(1, 0), 'Sale price must be lower than the base price.')
  })

  it('treats blank, zero and unreadable text as “no sale”', () => {
    // The app's `double.tryParse` yields null for text it cannot read and its
    // guard is skipped — junk silently means no sale there too. A zero sale
    // price is inert in every reader above, so it is not a fault either.
    for (const value of [null, undefined, '', 0, '0', 'free']) {
      assert.equal(at(value), null, `${String(value)} should not be a fault`)
    }
  })

  it('refuses a negative price, which no reader would honour', () => {
    assert.equal(at(-1), 'A sale price cannot be negative.')
  })

  it('says nothing when the base price is not a number yet', () => {
    // An empty price field is the name-the-product problem, not this one.
    assert.equal(at(500, ''), null)
    assert.equal(at(500, null), null)
    assert.equal(at(500, 'abc'), null)
  })

  it('agrees with isOnSale about what a sale is', () => {
    // The one property worth pinning: a price this function accepts for a
    // product with no window is a price `isOnSale` calls a live sale.
    assert.equal(at(900), null)
    assert.equal(
      isOnSale({ price: 1000, sale_price: 900 }, NOW),
      true,
      'a price the form accepts must be a sale the storefront shows',
    )
  })
})

describe('saleWindowNote', () => {
  it('says nothing about an open or half-open window', () => {
    assert.equal(
      saleWindowNote({ saleStartsAt: '2026-09-01', saleEndsAt: '2026-09-30' }),
      null,
    )
    assert.equal(saleWindowNote({ saleStartsAt: '2026-09-01' }), null)
    assert.equal(saleWindowNote({ saleEndsAt: '2026-09-30' }), null)
    assert.equal(saleWindowNote({}), null)
  })

  it('warns about a window that can never open', () => {
    assert.equal(
      saleWindowNote({ saleStartsAt: '2026-09-30', saleEndsAt: '2026-09-01' }),
      'The sale ends before it starts, so it will never be active.',
    )
    // Same day is the same problem: `isOnSale` needs the end AHEAD of now, and
    // a window that opens and closes at one instant is never ahead of anything.
    assert.equal(
      saleWindowNote({ saleStartsAt: '2026-09-30', saleEndsAt: '2026-09-30' }),
      'The sale ends before it starts, so it will never be active.',
    )
  })

  it('compares dates, not strings of different precision', () => {
    assert.equal(
      saleWindowNote({
        saleStartsAt: '2026-09-01T00:00:00',
        saleEndsAt: '2026-09-30T00:00:00+00:00',
      }),
      null,
    )
  })
})

describe('salePreview', () => {
  // The form passes `formatCurrency` and `formatDate`; a plain join here makes
  // the strings easy to read without importing the formatting module into a
  // file that is deliberately about the rules.
  const money = (value) => `P${value}`
  const date = (value) => (value instanceof Date ? value.toISOString().slice(0, 10) : String(value))
  const line = (product, now = NOW) => salePreview(product, { now, money, date })

  it('names both prices and the discount while a sale is live', () => {
    assert.equal(
      line(product({ price: 1450, sale_price: 1200 })),
      'Customers pay P1450 P1200 while this sale is on — 17% off.',
    )
  })

  it('states the regular price when there is no sale at all', () => {
    assert.equal(line(product({ price: 320 })), 'Customers pay P320.')
    // A zero sale price is not a price: nothing changes, so nothing is said.
    assert.equal(line(product({ price: 320, sale_price: 0 })), 'Customers pay P320.')
    // And neither is one at or above the regular price — the sale simply is not
    // live, and there is no other price to quote.
    assert.equal(
      line(product({ price: 320, sale_price: 400 })),
      'Customers pay P320.',
    )
  })

  it('says when a sale starts, and what is charged until it does', () => {
    assert.equal(
      line(
        product({
          price: 1000,
          sale_price: 900,
          sale_starts_at: '2026-10-01',
          sale_ends_at: '2026-10-31',
        }),
      ),
      'Customers pay P1000 until this sale starts on 2026-10-01, then P900.',
    )
  })

  it('says when a sale is over', () => {
    assert.equal(
      line(
        product({
          price: 1000,
          sale_price: 900,
          sale_starts_at: '2026-08-01',
          sale_ends_at: '2026-08-31',
        }),
      ),
      'Customers pay P1000. This sale ended on 2026-08-31.',
    )
  })

  it('agrees with the reader about every product it describes', () => {
    // The property that matters: whenever the line claims a discount, the price
    // the storefront charges is the one it quoted.
    const cases = [
      { price: 1450, sale_price: 1200 },
      { price: 1000, sale_price: 900, sale_starts_at: '2026-10-01' },
      { price: 1000, sale_price: 900, sale_ends_at: '2026-08-31' },
      { price: 1000, sale_price: 1000 },
      { price: 320 },
    ]
    for (const one of cases) {
      const row = product(one)
      const shown = effectivePrice(row, NOW)
      const sentence = line(row)
      assert.ok(
        sentence.includes(`P${shown}`),
        `${JSON.stringify(one)} → ${sentence} does not quote P${shown}`,
      )
    }
  })
})

describe('the sale date round trip', () => {
  it('writes the shape the app writes', () => {
    // Flutter's `showDatePicker` gives a date-only DateTime and
    // `toIso8601String()` gives `2026-09-26T00:00:00.000`; this is the same
    // instant with the same absence of a timezone, so the phone and the browser
    // landing the same picked date agree to the second.
    assert.equal(saleDateValue('2026-09-26'), '2026-09-26T00:00:00')
  })

  it('refuses anything that is not a plain date', () => {
    assert.equal(saleDateValue(''), null)
    assert.equal(saleDateValue(null), null)
    assert.equal(saleDateValue('26/09/2026'), null)
    assert.equal(saleDateValue('2026-9-6'), null)
    assert.equal(saleDateValue('2026-09-26T10:00:00'), null)
  })

  it('reads a stored timestamp back into a date input', () => {
    assert.equal(saleDateInput('2026-09-26T00:00:00+00:00'), '2026-09-26')
    assert.equal(saleDateInput('2026-09-26T00:00:00'), '2026-09-26')
    assert.equal(saleDateInput(new Date('2026-09-26T00:00:00Z')), '2026-09-26')
    assert.equal(saleDateInput(null), '')
    assert.equal(saleDateInput('not a date'), '')
  })

  it('is the inverse of itself for every value the column can hold', () => {
    for (const day of ['2026-01-01', '2026-09-26', '2036-12-31']) {
      assert.equal(saleDateInput(saleDateValue(day)), day)
    }
  })
})
