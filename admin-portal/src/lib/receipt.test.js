import test from 'node:test'
import assert from 'node:assert/strict'

import {
  buildReceiptDocument,
  printReceipt,
  receiptCode,
  receiptFulfillment,
  receiptMoney,
} from './receipt.js'

const onlineOrder = {
  id: 'be34a94e-0000-0000-0000-000000000000',
  order_code: 'BE34A94E',
  created_at: '2026-11-17T00:14:00Z',
  status: 'delivered',
  source: 'online',
  store_name: 'LIDEBETH SHOE TRADING',
  customer_name: 'Shaine Jayme',
  customer_email: 'jaymeshaine21@gmail.com',
  payment_method: 'cod',
  total_amount: 500,
  receipt_emailed_at: '2026-11-17T00:20:00Z',
  receipt_email_to: 'jaymeshaine21@gmail.com',
  order_items: [
    { product_name: 'Woven Wedge FlipFlops', size: '35', quantity: 1, unit_price: 500 },
  ],
}

const posOrder = {
  id: '1a9eed43-1111-2222-3333-444455556666',
  order_code: null,
  created_at: '2026-11-19T04:39:00Z',
  source: 'pos',
  store_name: 'LIDEBETH SHOE TRADING',
  payment_method: 'cash',
  total_amount: 1400,
  amount_tendered: 1500,
  change_amount: 100,
  order_items: [
    {
      product_name: 'Classic Black Leather Lace-Up Dress Shoes',
      size: 'Size 37',
      quantity: 1,
      unit_price: 1400,
    },
  ],
}

test('money and code read the way the app writes them', () => {
  assert.equal(receiptMoney(1400), '\u20b11,400.00')
  assert.equal(receiptMoney('nonsense'), '\u20b10.00')
  assert.equal(receiptCode(onlineOrder), 'BE34A94E')
  assert.equal(receiptCode(posOrder), '1A9EED43')
})

test('fulfilment never calls a till sale a pickup', () => {
  assert.equal(receiptFulfillment(posOrder), 'In store')
  assert.equal(receiptFulfillment(onlineOrder), 'Store pickup')
  assert.equal(receiptFulfillment({ ...onlineOrder, fulfillment: 'delivery' }), 'Delivery')
})

test('an online order prints both copies and the emailed stamp', () => {
  const html = buildReceiptDocument(onlineOrder, {
    storeLocation: 'Carcar, Cebu',
  })
  assert.match(html, /LIDEBETH SHOE TRADING/)
  assert.match(html, /Carcar, Cebu/)
  assert.match(html, /Order #BE34A94E/)
  assert.match(html, /Woven Wedge FlipFlops/)
  assert.match(html, /\u20b1500\.00/)
  assert.match(html, /Cash on delivery/)
  assert.match(html, /Fulfilment/)
  assert.match(html, /Customer copy emailed/)
  assert.match(html, /@page \{ size: A5/)
  // No till behind an online order, so no cash lines.
  assert.doesNotMatch(html, /Cash tendered/)
})

test('a till sale keeps the cash lines and the short code', () => {
  const html = buildReceiptDocument(posOrder)
  assert.match(html, /Order #1A9EED43/)
  assert.match(html, /In store/)
  assert.match(html, /Cash tendered/)
  assert.match(html, /\u20b11,500\.00/)
  assert.match(html, /Change/)
  assert.match(html, /\u20b1100\.00/)
  assert.match(html, /Customer copy has not been emailed yet/)
})

test('an item name cannot inject markup into the printed receipt', () => {
  const html = buildReceiptDocument({
    ...onlineOrder,
    order_items: [
      { product_name: '<script>alert(1)</script>', size: '', quantity: 1, unit_price: 1 },
    ],
  })
  assert.doesNotMatch(html, /<script>alert\(1\)/)
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/)
})

test('printReceipt says so when the popup is blocked', () => {
  assert.equal(typeof globalThis.window, 'undefined')
  assert.equal(printReceipt(onlineOrder), false)
})
