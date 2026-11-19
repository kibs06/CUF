import test from 'node:test'
import assert from 'node:assert/strict'

import {
  RECEIPT_LEASE_MS,
  matchesReceiptFilter,
  matchesReceiptSearch,
  receiptAddress,
  receiptCodeOf,
  receiptRowState,
  receiptState,
  receiptSummary,
  receiptsCsv,
} from './receiptTrail.js'

const NOW = Date.parse('2026-11-19T10:00:00Z')

function order(overrides = {}) {
  return {
    id: '1a9eed43-1111-2222-3333-444455556666',
    order_code: null,
    store_name: 'LIDEBETH SHOE TRADING',
    customer_name: 'Shaine Jayme',
    customer_email: 'jaymeshaine21@gmail.com',
    total_amount: 1400,
    status: 'delivered',
    source: 'pos',
    ...overrides,
  }
}

test('the stamp is the only proof a customer has their copy', () => {
  assert.equal(receiptState(order({ receipt_emailed_at: '2026-11-19T09:00:00Z' }), NOW), 'sent')
})

test('an untouched order is pending, not failed', () => {
  assert.equal(receiptState(order(), NOW), 'pending')
})

test('a live lease reads as sending, and a dead one does not', () => {
  const live = new Date(NOW - RECEIPT_LEASE_MS + 30_000).toISOString()
  const dead = new Date(NOW - RECEIPT_LEASE_MS - 30_000).toISOString()
  assert.equal(receiptState(order({ receipt_email_sending_since: live }), NOW), 'sending')
  assert.equal(
    receiptState(
      order({
        receipt_email_sending_since: dead,
        receipt_email_attempts: 1,
        receipt_email_last_error: 'SMTP send failed: timeout',
      }),
      NOW,
    ),
    'failed',
  )
})

test('a scheduled retry is retrying; a spent backoff is failed', () => {
  const future = new Date(NOW + 10 * 60_000).toISOString()
  const past = new Date(NOW - 10 * 60_000).toISOString()
  assert.equal(
    receiptState(
      order({
        receipt_email_attempts: 2,
        receipt_email_last_error: 'boom',
        receipt_email_next_attempt_at: future,
      }),
      NOW,
    ),
    'retrying',
  )
  assert.equal(
    receiptState(
      order({
        receipt_email_attempts: 5,
        receipt_email_last_error: 'boom',
        receipt_email_next_attempt_at: past,
      }),
      NOW,
    ),
    'failed',
  )
})

test('filters line up with the states they promise', () => {
  const sent = order({ receipt_emailed_at: '2026-11-19T09:00:00Z' })
  const failed = order({ receipt_email_attempts: 5, receipt_email_last_error: 'boom' })
  const pending = order()

  assert.equal(matchesReceiptFilter(sent, 'sent', NOW), true)
  assert.equal(matchesReceiptFilter(sent, 'failed', NOW), false)
  assert.equal(matchesReceiptFilter(failed, 'failed', NOW), true)
  assert.equal(matchesReceiptFilter(failed, 'waiting', NOW), false)
  assert.equal(matchesReceiptFilter(pending, 'waiting', NOW), true)
  assert.equal(matchesReceiptFilter(pending, 'all', NOW), true)
})

test('search finds a sale by code, store, customer or address', () => {
  const sale = order({ receipt_email_to: 'other@example.com' })
  assert.equal(matchesReceiptSearch(sale, '1a9eed43'), true)
  assert.equal(matchesReceiptSearch(sale, 'lidebeth'), true)
  assert.equal(matchesReceiptSearch(sale, 'shaine'), true)
  assert.equal(matchesReceiptSearch(sale, 'other@example.com'), true)
  assert.equal(matchesReceiptSearch(sale, 'nope'), false)
  assert.equal(matchesReceiptSearch(sale, '   '), true)
})

test('the address falls back from receipt_email_to to the order to the profile', () => {
  assert.equal(receiptAddress(order({ receipt_email_to: 'sent@example.com' })), 'sent@example.com')
  assert.equal(receiptAddress(order({ customer_email: '' })), '')
  assert.equal(
    receiptAddress(order({ customer_email: '', profiles: { email: 'account@example.com' } })),
    'account@example.com',
  )
})

test('a receipt code is the order code, else the app’s eight-character id', () => {
  assert.equal(receiptCodeOf(order({ order_code: 'BE34A94E' })), 'BE34A94E')
  assert.equal(receiptCodeOf(order()), '1A9EED43')
})

test('a sale with no address reports that, not a pending send', () => {
  const walkIn = order({ customer_email: '', receipt_email_to: '' })
  const shown = receiptRowState(walkIn, NOW)
  assert.equal(shown.state, 'no_email')
  assert.equal(shown.meta.label, 'No email on file')
  assert.equal(shown.meta.tone, 'none')
})

test('a sale with an address still reads as not sent', () => {
  assert.equal(receiptRowState(order(), NOW).state, 'pending')
  assert.equal(receiptRowState(order(), NOW).meta.label, 'Not sent')
})

test('no address does not override a send that did happen', () => {
  const sent = order({ customer_email: '', receipt_emailed_at: '2026-11-19T09:00:00Z' })
  assert.equal(receiptRowState(sent, NOW).state, 'sent')
})

test('a failure stays a failure even if the address was cleared', () => {
  const failed = order({
    customer_email: '',
    receipt_email_attempts: 4,
    receipt_email_last_error: 'mailbox full',
  })
  assert.equal(receiptRowState(failed, NOW).state, 'failed')
})

test('the summary counts what the tiles promise', () => {
  const rows = [
    order({ receipt_emailed_at: '2026-11-19T09:00:00Z' }),
    order({ receipt_email_attempts: 5, receipt_email_last_error: 'boom' }),
    order(),
    order({ receipt_email_sending_since: new Date(NOW - 1000).toISOString() }),
  ]
  assert.deepEqual(receiptSummary(rows, NOW), { total: 4, sent: 1, waiting: 2, failed: 1 })
})

test('the CSV carries the trail, quoted where it has to be', () => {
  const csv = receiptsCsv(
    [
      order({
        receipt_email_attempts: 2,
        receipt_email_last_error: 'SMTP send failed: "quoted", comma',
      }),
    ],
    NOW,
  )
  const [header, row] = csv.split('\n')
  assert.match(header, /^Receipt,Store,Customer/)
  assert.match(row, /^1A9EED43,LIDEBETH SHOE TRADING,Shaine Jayme/)
  assert.match(row, /Failed/)
  assert.match(row, /"SMTP send failed: ""quoted"", comma"/)
})
