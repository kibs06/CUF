import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import {
  ADDRESS_FIELDS,
  DEFAULT_PAYMENT_METHOD,
  DEFAULT_PIN,
  DELIVERY_FEE,
  PAYMENT_METHODS,
  addressErrors,
  addressFromRow,
  addressInsert,
  cartLinesToClear,
  cashOrderInsert,
  chargedTotal,
  checkoutError,
  checkoutGroups,
  checkoutItems,
  deadlineState,
  emptyAddressDraft,
  feeLabel,
  formatCountdown,
  formatDeliveryAddress,
  functionError,
  isAddressComplete,
  isOnlinePayment,
  normalizePaymentMethod,
  orderItemInserts,
  paymentMethodLabel,
  paymentState,
  phoneError,
  quotedTotal,
  reconcileServerTotal,
  shippingSnapshot,
  shortOrderId,
  snapshotLines,
  stockUnavailableMessage,
  summaryLines,
} from './checkoutRules.js'

/** A cart line as `mapCartItem` produces it, with only the fields read here. */
const line = (overrides = {}) => ({
  id: 'cart-1',
  productId: 'prod-1',
  cartSize: 'EU40',
  size: 'EU40',
  quantity: 1,
  unitPrice: 300,
  storeId: 'store-1',
  storeName: 'Valladolid Leather Co.',
  ...overrides,
})

const draft = (overrides = {}) => ({
  ...emptyAddressDraft(),
  recipientName: 'Ana Reyes',
  recipientPhone: '0917 123 4567',
  region: 'Region VII (Central Visayas)',
  province: 'Cebu',
  cityMunicipality: 'Carcar City',
  barangay: 'Poblacion I',
  streetAddress: '12 Osmeña St.',
  ...overrides,
})

describe('the two payment methods', () => {
  it('offers the app’s two, in the app’s order', () => {
    // `checkout_screen.dart`'s RadioGroup: GCash first, Cash on Pickup second.
    assert.deepEqual(
      PAYMENT_METHODS.map((option) => option.value),
      ['gcash', 'cash'],
    )
    assert.equal(PAYMENT_METHODS[0].label, 'GCash')
    assert.equal(PAYMENT_METHODS[1].label, 'Cash on Pickup')
    assert.equal(DEFAULT_PAYMENT_METHOD, 'gcash')
  })

  it('normalizes the way the app does, including its cash default', () => {
    assert.equal(normalizePaymentMethod('GCash'), 'gcash')
    assert.equal(normalizePaymentMethod('gcash'), 'gcash')
    assert.equal(normalizePaymentMethod('Cash on Pickup'), 'cash')
    assert.equal(normalizePaymentMethod('CARD'), 'card')
    // The app's fallback: anything unrecognised is cash, which is exactly why
    // an unknown value must never reach the column.
    assert.equal(normalizePaymentMethod('bank transfer'), 'cash')
    assert.equal(normalizePaymentMethod(null), 'cash')
  })

  it('labels a stored column value the way a receipt should read it', () => {
    // The app stores the normalized word, but an older row may hold the label
    // the picker showed — both read correctly.
    assert.equal(paymentMethodLabel('gcash'), 'GCash')
    assert.equal(paymentMethodLabel('GCash'), 'GCash')
    assert.equal(paymentMethodLabel('cash'), 'Cash on Pickup')
    assert.equal(paymentMethodLabel('Cash on Pickup'), 'Cash on Pickup')
    assert.equal(paymentMethodLabel('card'), 'Card')
    assert.equal(paymentMethodLabel(null), 'Not recorded')
  })

  it('never relabels a method it does not know', () => {
    // `normalizePaymentMethod` maps the unknown to cash, because that is what
    // may be WRITTEN; calling somebody's PayMaya order "Cash on Pickup" would be
    // a lie about their receipt.
    assert.equal(paymentMethodLabel('paymaya'), 'paymaya')
  })

  it('asks for a payment page only for GCash', () => {
    assert.equal(isOnlinePayment('gcash'), true)
    assert.equal(isOnlinePayment('GCash'), true)
    assert.equal(isOnlinePayment('cash'), false)
    assert.equal(isOnlinePayment(null), false)
  })
})

describe('cashOrderInsert', () => {
  it('builds the app’s own payload, field for field', () => {
    const insert = cashOrderInsert({
      userId: 'u1',
      storeId: 's1',
      lines: [line({ quantity: 2, unitPrice: 300 })],
      deliveryAddress: 'Ana Reyes · 0917 123 4567 · 12 Osmeña St., Carcar City',
      shippingAddress: { recipient_name: 'Ana Reyes' },
    })

    assert.deepEqual(insert, {
      customer_id: 'u1',
      store_id: 's1',
      status: 'pending',
      fulfillment: 'pickup',
      total_amount: 700,
      payment_method: 'cash',
      payment_status: 'unpaid',
      notes: 'Ana Reyes · 0917 123 4567 · 12 Osmeña St., Carcar City',
      source: 'online',
      shipping_address: { recipient_name: 'Ana Reyes' },
    })
  })

  it('adds the fixed delivery fee once, from the cart’s own line totals', () => {
    const insert = cashOrderInsert({
      userId: 'u1',
      storeId: 's1',
      lines: [line({ unitPrice: 300 }), line({ id: 'cart-2', unitPrice: 150 })],
    })
    assert.equal(insert.total_amount, 550)
    assert.equal(insert.total_amount, quotedTotal([line({ unitPrice: 300 }), line({ id: 'cart-2', unitPrice: 150 })]).total)
  })

  it('leaves `unpaid` on the order — the whole point of paying at pickup', () => {
    const insert = cashOrderInsert({ userId: 'u1', storeId: 's1', lines: [line()] })
    assert.equal(insert.payment_status, 'unpaid')
    assert.equal(insert.payment_method, 'cash')
  })

  it('omits the address snapshot rather than sending a null column', () => {
    const insert = cashOrderInsert({ userId: 'u1', storeId: 's1', lines: [line()] })
    assert.equal('shipping_address' in insert, false)
  })

  it('refuses what cannot be ordered', () => {
    assert.equal(cashOrderInsert({ userId: null, storeId: 's1', lines: [line()] }), null)
    assert.equal(cashOrderInsert({ userId: 'u1', storeId: null, lines: [line()] }), null)
    assert.equal(cashOrderInsert({ userId: 'u1', storeId: 's1', lines: [] }), null)
  })
})

describe('orderItemInserts', () => {
  it('sends the cart’s own size string and pinned unit price', () => {
    // The trigger matches sizes by DIGITS, so this string reaches the same
    // inventory row the app's resolved size would.
    assert.deepEqual(orderItemInserts('o1', [line({ quantity: 2, unitPrice: 300 })]), [
      {
        order_id: 'o1',
        product_id: 'prod-1',
        size: 'EU40',
        quantity: 2,
        unit_price: 300,
      },
    ])
  })

  it('is empty without an order id, so nothing can be inserted unattached', () => {
    assert.deepEqual(orderItemInserts(null, [line()]), [])
    assert.deepEqual(orderItemInserts('o1', []), [])
  })
})

describe('stockUnavailableMessage', () => {
  const soldOut = {
    code: 'P0001',
    message: 'Insufficient stock for product prod-1 size EU40',
  }

  it('names the pair the customer was buying, not a uuid', () => {
    const message = stockUnavailableMessage(soldOut, [
      line({ productName: 'JBC Crown Leather Sandals', cartSize: 'EU40' }),
    ])
    assert.match(message, /JBC Crown Leather Sandals \(size EU40\)/)
    assert.match(message, /no longer available/)
  })

  it('still says something useful when the line is unknown', () => {
    assert.match(stockUnavailableMessage(soldOut, []), /That pair \(size EU40\)/)
  })

  it('is null for every other failure', () => {
    // Separating "the pair sold out" from "the insert failed" is the point:
    // only the first one means "go back to your cart".
    assert.equal(stockUnavailableMessage({ code: '42501', message: 'Insufficient stock for product p size s' }, [line()]), null)
    assert.equal(stockUnavailableMessage({ code: 'P0001', message: 'something else' }, [line()]), null)
    assert.equal(stockUnavailableMessage(null, [line()]), null)
  })
})

describe('phoneError', () => {
  it('accepts local and international mobile forms', () => {
    assert.equal(phoneError('0917 123 4567'), null)
    assert.equal(phoneError('+63 917 123 4567'), null)
  })

  it('rejects an incomplete number', () => {
    assert.match(phoneError('0917'), /complete mobile number/)
    assert.match(phoneError(''), /mobile number the rider can reach/)
  })
})

describe('addressErrors', () => {
  it('passes a complete draft', () => {
    assert.deepEqual(addressErrors(draft()), {})
    assert.equal(isAddressComplete(draft()), true)
  })

  it('asks for every NOT NULL column rather than letting the insert fail', () => {
    const errors = addressErrors(emptyAddressDraft())
    for (const field of [
      'recipientName',
      'recipientPhone',
      'region',
      'province',
      'cityMunicipality',
      'barangay',
      'streetAddress',
    ]) {
      assert.ok(errors[field], `${field} should be required`)
    }
  })

  it('does not require the optional ones', () => {
    const errors = addressErrors(draft({ landmark: '', label: '' }))
    assert.deepEqual(errors, {})
  })
})

describe('formatDeliveryAddress', () => {
  it('writes the address in the same order as the app', () => {
    assert.equal(
      formatDeliveryAddress(draft()),
      '12 Osmeña St., Poblacion I, Carcar City, Cebu, Region VII (Central Visayas)',
    )
  })

  it('drops blanks instead of leaving empty commas', () => {
    assert.equal(
      formatDeliveryAddress(draft({ landmark: '' })),
      '12 Osmeña St., Poblacion I, Carcar City, Cebu, Region VII (Central Visayas)',
    )
  })
})

describe('shippingSnapshot', () => {
  it('uses the snake_case keys the app reads back', () => {
    const snapshot = shippingSnapshot(draft())
    assert.equal(snapshot.recipient_name, 'Ana Reyes')
    assert.equal(snapshot.city_municipality, 'Carcar City')
    assert.equal(snapshot.landmark, null)
    assert.ok(!('recipientName' in snapshot))
  })

  it('omits coordinates rather than inventing a pin', () => {
    // A false pin on a delivery record is worse than an absent one.
    assert.ok(!('latitude' in shippingSnapshot(draft())))
    assert.ok(!('latitude' in shippingSnapshot(draft({ latitude: 0, longitude: 0 }))))
  })

  it('keeps a real pin', () => {
    const snapshot = shippingSnapshot(
      draft({ latitude: 10.1, longitude: 123.6 }),
    )
    assert.equal(snapshot.latitude, 10.1)
    assert.equal(snapshot.longitude, 123.6)
  })
})

describe('addressInsert', () => {
  it('fills the NOT NULL coordinates with the app’s default center', () => {
    const insert = addressInsert('user-1', draft())
    assert.equal(insert.user_id, 'user-1')
    assert.equal(insert.latitude, DEFAULT_PIN.latitude)
    assert.equal(insert.longitude, DEFAULT_PIN.longitude)
  })
})

describe('addressFromRow', () => {
  it('maps a saved row to a draft', () => {
    const mapped = addressFromRow({
      id: 'addr-1',
      label: 'Office',
      recipient_name: 'Ana Reyes',
      recipient_phone: '09171234567',
      region: 'Region VII (Central Visayas)',
      province: 'Cebu',
      city_municipality: 'Carcar City',
      barangay: 'Poblacion I',
      street_address: '12 Osmeña St.',
      landmark: 'Blue gate',
      latitude: 10.1,
      longitude: 123.6,
      is_default: true,
    })
    assert.equal(mapped.cityMunicipality, 'Carcar City')
    assert.equal(mapped.streetAddress, '12 Osmeña St.')
    assert.equal(mapped.isDefault, true)
  })

  it('is null for no row', () => {
    assert.equal(addressFromRow(null), null)
  })
})

describe('quotedTotal', () => {
  it('matches the cart: sale prices, multiplied by quantity', () => {
    const { subtotal, deliveryFee, total } = quotedTotal([
      line({ unitPrice: 300, quantity: 2 }),
      line({ id: 'cart-2', unitPrice: 799 }),
    ])
    assert.equal(subtotal, 1399)
    assert.equal(deliveryFee, DELIVERY_FEE)
    assert.equal(total, 1499)
  })

  it('adds no fee to an empty basket', () => {
    assert.deepEqual(quotedTotal([]), {
      subtotal: 0,
      deliveryFee: 0,
      total: 0,
    })
  })

  it('does not drift on fractional prices', () => {
    const { subtotal } = quotedTotal([
      line({ unitPrice: 0.1 }),
      line({ unitPrice: 0.2 }),
    ])
    assert.equal(subtotal, 0.3)
  })
})

describe('reconcileServerTotal', () => {
  it('accepts an exact match', () => {
    const result = reconcileServerTotal({ quoted: 1499, server: 1499 })
    assert.equal(result.matches, true)
    assert.equal(result.delta, 0)
  })

  it('tolerates a sub-centavo rounding difference', () => {
    const result = reconcileServerTotal({ quoted: 1499, server: 1499.001 })
    assert.equal(result.matches, true)
  })

  it('flags the list-price trap and says which way it points', () => {
    // A ₱799 pair on sale at ₱300: the RPC prices from products.price, so the
    // server total lands above what the storefront showed.
    const result = reconcileServerTotal({ quoted: 400, server: 899 })
    assert.equal(result.matches, false)
    assert.equal(result.delta, 499)
    assert.equal(result.direction, 'higher')
  })

  it('flags a server total below the quote too', () => {
    const result = reconcileServerTotal({ quoted: 900, server: 400 })
    assert.equal(result.matches, false)
    assert.equal(result.direction, 'lower')
  })
})

describe('checkoutItems', () => {
  it('sends no prices — the server pins them', () => {
    const items = checkoutItems([line({ cartSize: 'EU41', quantity: 2 })])
    assert.deepEqual(items, [
      { product_id: 'prod-1', size: 'EU41', quantity: 2 },
    ])
  })

  it('falls back to the resolved size when the cart row has none', () => {
    const items = checkoutItems([line({ cartSize: null, size: 'EU42' })])
    assert.equal(items[0].size, 'EU42')
  })
})

describe('checkoutGroups', () => {
  it('splits a mixed cart per maker', () => {
    const groups = checkoutGroups([
      line({ storeId: 'a', storeName: 'Maker A', unitPrice: 300 }),
      line({ id: 'c2', storeId: 'b', storeName: 'Maker B', unitPrice: 500 }),
      line({ id: 'c3', storeId: 'a', storeName: 'Maker A', unitPrice: 100 }),
    ])

    assert.equal(groups.length, 2)
    assert.equal(groups[0].storeName, 'Maker A')
    assert.equal(groups[0].items.length, 2)
    assert.equal(groups[0].subtotal, 400)
    assert.equal(groups[1].subtotal, 500)
  })

  it('keeps every line when the makers are the same', () => {
    const groups = checkoutGroups([line(), line({ id: 'c2' })])
    assert.equal(groups.length, 1)
    assert.equal(groups[0].subtotal, 600)
  })
})

describe('summaryLines', () => {
  it('translates the cart’s field names into the card’s', () => {
    // Caught live: the card was rendering "Size US 8 · Qty 1" with no name and
    // ₱0.00, because a cart line says `productName`/`cartSize` and the card
    // reads `name`/`size`.
    const [row] = summaryLines([
      {
        id: 'cart-1',
        productName: 'JBC Crown Leather Sandals',
        imageUrl: 'a.jpg',
        cartSize: 'US 8',
        quantity: 2,
        unitPrice: 300,
      },
    ])

    assert.equal(row.name, 'JBC Crown Leather Sandals')
    assert.equal(row.size, 'US 8')
    assert.equal(row.lineTotal, 600)
  })

  it('falls back to the order line’s own names, so it takes both shapes', () => {
    const [row] = summaryLines([
      { id: 'i1', name: 'From an order', size: '41', quantity: 1, unitPrice: 10.5 },
    ])
    assert.equal(row.name, 'From an order')
    assert.equal(row.size, '41')
    assert.equal(row.lineTotal, 10.5)
  })

  it('survives empty and missing input', () => {
    assert.deepEqual(summaryLines([]), [])
    assert.deepEqual(summaryLines(null), [])
  })
})

describe('snapshotLines', () => {
  it('reads the order’s own snapshot, which exists before the webhook does', () => {
    // Real shape, read from the deployed database for a pending order.
    const [row] = snapshotLines([
      {
        size: 'US 8',
        quantity: 1,
        product_id: 'fd44ad66-6c33-4540-9666-7960d47f4cdf',
        unit_price: 300,
        product_name: 'JBC Crown Leather Sandals',
      },
    ])

    assert.equal(row.name, 'JBC Crown Leather Sandals')
    assert.equal(row.size, 'US 8')
    assert.equal(row.lineTotal, 300)
    assert.equal(row.imageUrl, null)
  })

  it('multiplies the pinned unit price by the quantity', () => {
    const [row] = snapshotLines([{ unit_price: 99.5, quantity: 3 }])
    assert.equal(row.lineTotal, 298.5)
  })

  it('is empty for a missing or malformed snapshot', () => {
    assert.deepEqual(snapshotLines(null), [])
    assert.deepEqual(snapshotLines([]), [])
  })
})

describe('chargedTotal', () => {
  it('adds the fee to the order total', () => {
    // The shape get_gcash_fee returns for a ₱400 order: rate 2.23% + 12% VAT.
    assert.equal(chargedTotal({ orderTotal: 400, feeAmount: 10.25 }), 410.25)
  })

  it('does not drift on fractional fees', () => {
    assert.equal(chargedTotal({ orderTotal: 0.1, feeAmount: 0.2 }), 0.3)
  })

  it('treats a missing fee as zero rather than NaN', () => {
    assert.equal(chargedTotal({ orderTotal: 500 }), 500)
  })
})

describe('feeLabel', () => {
  it('builds the sentence from the server’s basis points', () => {
    // rate_bps 223 -> 2.23%, vat_bps 1200 -> 12%. A rate change in
    // payment_fee_config must change what the customer reads, without a deploy.
    assert.equal(
      feeLabel({ rate_bps: 223, vat_bps: 1200 }),
      'GCash fee (2.23% + 12% VAT)',
    )
  })

  it('copes with no VAT and with no rate at all', () => {
    assert.equal(feeLabel({ rate_bps: 250, vat_bps: 0 }), 'GCash fee (2.50%)')
    assert.equal(feeLabel({}), 'GCash fee')
    assert.equal(feeLabel(null), 'GCash fee')
  })
})

describe('paymentState', () => {
  const now = new Date('2026-09-25T10:00:00.000Z')

  it('trusts the server’s paid flag above everything', () => {
    assert.equal(
      paymentState({ paid: true, orderStatus: 'awaiting_payment' }, now),
      'paid',
    )
    assert.equal(paymentState({ paymentStatus: 'paid' }, now), 'paid')
  })

  it('reads a cancelled order or a failed payment as cancelled', () => {
    assert.equal(paymentState({ orderStatus: 'cancelled' }, now), 'cancelled')
    assert.equal(paymentState({ paymentStatus: 'failed' }, now), 'cancelled')
    assert.equal(paymentState({ intentStatus: 'expired' }, now), 'cancelled')
  })

  it('stops polling once the order has left the payment step', () => {
    // Whatever the webhook decided is already in the order's status; there is
    // nothing left to poll for.
    assert.equal(paymentState({ orderStatus: 'preparing' }, now), 'processing')
  })

  it('is awaiting while the order is awaiting and time remains', () => {
    assert.equal(
      paymentState(
        {
          orderStatus: 'awaiting_payment',
          expiresAt: '2026-09-25T10:14:00.000Z',
        },
        now,
      ),
      'awaiting',
    )
  })

  it('is expired at the deadline itself, not after it', () => {
    assert.equal(
      paymentState(
        {
          orderStatus: 'awaiting_payment',
          expiresAt: '2026-09-25T10:00:00.000Z',
        },
        now,
      ),
      'expired',
    )
  })
})

describe('cartLinesToClear', () => {
  it('matches the order’s lines back onto the cart', () => {
    const ids = cartLinesToClear(
      [
        line({ id: 'cart-1', productId: 'p1', cartSize: 'EU 40' }),
        line({ id: 'cart-2', productId: 'p2', cartSize: '41' }),
      ],
      [{ productId: 'p1', size: '40' }],
    )
    // Size is compared digits-only — "EU 40" and "40" are one size.
    assert.deepEqual(ids, ['cart-1'])
  })

  it('leaves lines the order does not account for', () => {
    const ids = cartLinesToClear(
      [line({ id: 'cart-9', productId: 'p9', cartSize: '42' })],
      [{ productId: 'p1', size: '40' }],
    )
    assert.deepEqual(ids, [])
  })

  it('is empty for an order with no lines yet', () => {
    // Before the webhook fires, a real order legitimately has no items.
    assert.deepEqual(cartLinesToClear([line()], []), [])
    assert.deepEqual(cartLinesToClear(null, [{ productId: 'p1', size: '40' }]), [])
  })
})

describe('functionError', () => {
  const withBody = (status, body) => ({
    message: 'Edge Function returned a non-2xx status code',
    context: { status, json: async () => body },
  })

  it('reads the sentence out of the response body', async () => {
    const mapped = await functionError(
      withBody(400, { error: 'idempotency_key must be a UUID' }),
      'fallback',
    )
    assert.equal(mapped.message, 'idempotency_key must be a UUID')
    assert.equal(mapped.status, 400)
    assert.equal(mapped.openOrder, false)
  })

  it('flags a 409 as an already-open order', async () => {
    const mapped = await functionError(
      withBody(409, { error: 'A payment is already pending for this customer' }),
      'fallback',
    )
    assert.equal(mapped.openOrder, true)
  })

  it('falls back when the body is not JSON at all', async () => {
    const mapped = await functionError(
      {
        message: 'Failed to fetch',
        context: {
          status: 502,
          json: async () => {
            throw new Error('not json')
          },
        },
      },
      'We could not start the GCash payment.',
    )
    assert.equal(mapped.message, 'Failed to fetch')
  })

  it('uses the fallback for a plain thrown error', async () => {
    const mapped = await functionError(new Error(), 'Please try again.')
    assert.equal(mapped.message, 'Please try again.')
    assert.equal(mapped.openOrder, false)
  })
})

describe('shortOrderId', () => {
  it('is the first eight characters, as the server’s notifications print it', () => {
    assert.equal(shortOrderId('a1b2c3d4-e5f6-7890-abcd-ef1234567890'), 'a1b2c3d4')
  })

  it('survives a missing id', () => {
    assert.equal(shortOrderId(null), '')
  })
})

describe('deadlineState', () => {
  const now = new Date('2026-09-25T10:00:00.000Z')

  it('counts down to the deadline', () => {
    const state = deadlineState('2026-09-25T10:30:00.000Z', now)
    assert.equal(state.known, true)
    assert.equal(state.expired, false)
    assert.equal(state.msLeft, 30 * 60 * 1000)
  })

  it('is expired at the deadline itself, not after it', () => {
    assert.equal(deadlineState('2026-09-25T10:00:00.000Z', now).expired, true)
    assert.equal(deadlineState('2026-09-25T09:59:00.000Z', now).expired, true)
  })

  it('reports an unknown deadline rather than guessing', () => {
    assert.deepEqual(deadlineState(null, now), {
      known: false,
      expired: false,
      msLeft: null,
    })
    assert.equal(deadlineState('not a date', now).known, false)
  })
})

describe('formatCountdown', () => {
  it('pads the seconds', () => {
    assert.equal(formatCountdown(14 * 60 * 1000 + 5000), '14m 05s')
  })

  it('never goes negative', () => {
    assert.equal(formatCountdown(-5000), '0m 00s')
  })
})

describe('checkoutError', () => {
  it('passes a hand-written rejection through verbatim', () => {
    const mapped = checkoutError({ code: 'P0001', message: 'Size "40" is no longer available for Breeze. Please update your cart.' })
    assert.equal(mapped.message, 'Size "40" is no longer available for Breeze. Please update your cart.')
    assert.equal(mapped.openOrder, false)
  })

  it('prefers an edge function’s own error body', () => {
    const mapped = checkoutError({
      message: 'Edge Function returned a non-2xx status code',
      body: { error: 'Order total must be greater than zero' },
    })
    assert.equal(mapped.message, 'Order total must be greater than zero')
  })

  it('normalizes the re-raised one-open-order violation back to 23505', () => {
    // The RPC catches the unique violation and re-raises it without an ERRCODE,
    // so the message is the only signal that a pending order already exists.
    const mapped = checkoutError({
      code: 'P0001',
      message:
        'You already have a GCash checkout awaiting confirmation. Complete or cancel it first.',
    })
    assert.equal(mapped.code, '23505')
    assert.equal(mapped.openOrder, true)
  })

  it('flags a real 23505 as an open order too', () => {
    const mapped = checkoutError({ code: '23505', message: 'duplicate key' })
    assert.equal(mapped.openOrder, true)
    assert.match(mapped.message, /awaiting confirmation/)
  })

  it('does not print Postgres at a customer when the route is closed', () => {
    // `create_gcash_checkout` was revoked on 2026-09-05 and answers exactly
    // this. "permission denied for function create_gcash_checkout" is a
    // developer message; the customer needs to be told where they CAN order.
    const mapped = checkoutError({
      code: '42501',
      message: 'permission denied for function create_gcash_checkout',
    })
    assert.match(mapped.message, /not available on the web right now/)
    assert.ok(!/create_gcash_checkout/.test(mapped.message))
  })

  it('prefers the server copy for a permission failure', () => {
    // A session that expired mid-checkout says "Not authenticated" — being told
    // to sign in again is the only useful thing to hear.
    assert.equal(
      checkoutError({ code: '42501', message: 'Not authenticated' }).message,
      'Not authenticated',
    )
    assert.equal(
      checkoutError({ code: '42501', message: '' }).message,
      'You are not allowed to do that.',
    )
  })

  it('uses a thrown JS error’s message when there is no code', () => {
    assert.equal(
      checkoutError(new Error('Failed to fetch')).message,
      'Failed to fetch',
    )
  })

  it('falls back for anything unrecognisable', () => {
    assert.equal(
      checkoutError({}, 'We could not start the checkout.').message,
      'We could not start the checkout.',
    )
    assert.equal(checkoutError(null).message, 'Something went wrong. Please try again.')
  })
})

describe('ADDRESS_FIELDS', () => {
  it('lists exactly the fields a draft carries, bar the label', () => {
    const carried = Object.keys(emptyAddressDraft()).filter(
      (key) => key !== 'label',
    )
    assert.deepEqual([...ADDRESS_FIELDS].sort(), carried.sort())
  })
})
