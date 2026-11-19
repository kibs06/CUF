import test from 'node:test'
import assert from 'node:assert/strict'

import { channelLabel, matchesSaleSearch, methodLabel, saleSearchText } from './saleFields.js'

const SALE = {
  order_id: 'd1c1bb63-1111-2222-3333-444455556666',
  order_code: '',
  store_name: 'LIDEBETH SHOE TRADING',
  customer_name: 'Lidebeth Arrosa',
  customer_email: 'lidebeth5d@gmail.com',
  amount: 990,
  method: 'cash',
  source: 'pos',
  order_status: 'delivered',
  fulfillment: 'delivery',
  created_at: '2026-11-19T08:38:00.000Z',
  paid_at: '2026-11-19T08:38:10.000Z',
  receipt_emailed_at: '2026-11-19T08:39:00.000Z',
  gcash_transaction_id: 'pay_TX123',
  items: [{ product_name: 'Black Leather Sandals', size: '38', quantity: 1, unit_price: 990 }],
  proof: null,
  events: [{ event_type: 'payment.paid' }],
  intent: null,
}

const GCASH_SALE = {
  ...SALE,
  order_code: '1F12CB92',
  amount: 250,
  method: 'gcash',
  source: 'online',
  gcash_reference_number: '4047398097426',
  proof: {
    reference_number: '4047398097426',
    sender_name: 'Keith Vincent D Abalo',
    amount_paid: 250,
    status: 'verified',
    attempt_no: 2,
  },
  intent: { paymongo_payment_intent_id: 'pi_abc123', checkout_session_id: 'cs_xyz' },
}

const NO_EMAIL_SALE = {
  ...SALE,
  customer_email: '',
  receipt_emailed_at: '',
}

test('finds a sale by item name and by size', () => {
  assert.equal(matchesSaleSearch(SALE, 'sandals'), true)
  assert.equal(matchesSaleSearch(SALE, 'leather 38'), true)
  assert.equal(matchesSaleSearch(SALE, '35'), false)
})

test('finds a sale by order id prefix, full code and store', () => {
  assert.equal(matchesSaleSearch(SALE, 'd1c1bb63'), true)
  assert.equal(matchesSaleSearch(GCASH_SALE, '1f12cb92'), true)
  assert.equal(matchesSaleSearch(SALE, 'lidebeth shoe'), true)
})

test('finds the amount however it is typed or printed', () => {
  assert.equal(matchesSaleSearch(SALE, '990'), true)
  assert.equal(matchesSaleSearch(SALE, '990.00'), true)
  assert.equal(matchesSaleSearch(SALE, '₱990'), true)
  assert.equal(matchesSaleSearch(SALE, '991'), false)
})

test('finds a GCash sale by reference, sender, transaction or gateway id', () => {
  assert.equal(matchesSaleSearch(GCASH_SALE, '4047398097426'), true)
  assert.equal(matchesSaleSearch(GCASH_SALE, 'keith'), true)
  assert.equal(matchesSaleSearch(GCASH_SALE, 'pi_abc123'), true)
  assert.equal(matchesSaleSearch(GCASH_SALE, 'cs_xyz'), true)
})

test('finds a sale by its receipt state wording', () => {
  assert.equal(matchesSaleSearch(SALE, 'sent'), true)
  assert.equal(matchesSaleSearch(NO_EMAIL_SALE, 'no email on file'), true)
})

test('finds a sale by date and by webhook event', () => {
  assert.equal(matchesSaleSearch(SALE, '2026'), true)
  assert.equal(matchesSaleSearch(SALE, 'payment.paid'), true)
})

test('finds a sale by payment method and channel', () => {
  assert.equal(matchesSaleSearch(GCASH_SALE, 'gcash online'), true)
  assert.equal(matchesSaleSearch(SALE, 'cash walk-in'), true)
})

test('several words narrow the result instead of widening it', () => {
  assert.equal(matchesSaleSearch(SALE, 'lidebeth 990'), true)
  assert.equal(matchesSaleSearch(SALE, 'lidebeth 250'), false)
})

test('an empty query matches everything', () => {
  assert.equal(matchesSaleSearch(SALE, ''), true)
  assert.equal(matchesSaleSearch(SALE, '   '), true)
  assert.equal(saleSearchText(null), '')
})

test('labels are the ones the table prints', () => {
  assert.equal(methodLabel('cod'), 'Cash on delivery')
  assert.equal(methodLabel(''), 'Not recorded')
  assert.equal(channelLabel('pos'), 'Walk-in')
  assert.equal(channelLabel('online'), 'Online')
})
