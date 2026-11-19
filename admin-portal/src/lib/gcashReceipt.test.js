import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  extractReference,
  formatGrouped,
  parseReceiptText,
} from './gcashReceipt.js'

// ─── The same rules the customer app applies to its own proof ─────────
//
// The payout dialog reads the admin's transfer screenshot with the app's
// extractor, so these cases are the app's cases: the label wins, the printed
// grouping is preferred, and money/dates/phone numbers are never mistaken for
// a reference. A regression here means an admin records the wrong number
// against a payout — the one thing the reference exists to prevent.

const REF = '4043676687260'

test('a "Ref No." line wins even with an amount above it', () => {
  const result = extractReference([
    'GCash',
    'You sent ₱650.00',
    'Amount Sent',
    'PHP 650.00',
    'Ref No. 4043 676 687260',
    'Nov 18, 2026 11:42 AM',
  ])
  assert.equal(result.reference, REF)
  assert.equal(result.matchedLabel, true)
  assert.equal(result.displayGrouped, '4043 676 687260')
})

test('a label split from its value is read from the next line', () => {
  const result = extractReference(['Reference Number', REF, 'Recipient: VeeJay'])
  assert.equal(result.reference, REF)
  assert.equal(result.matchedLabel, true)
})

test('without a label, the printed 4-3-6 group is the reference', () => {
  const result = extractReference(['Express Send', '4043 676 687260', 'Nov 18, 2026'])
  assert.equal(result.reference, REF)
  assert.equal(result.matchedLabel, false)
  assert.deepEqual(result.candidates, [REF])
})

test('13 digits beat a shorter plausible run', () => {
  const result = extractReference(['Batch 1234567890', 'Transfer 4043676687260'])
  assert.equal(result.reference, REF)
})

test('a Philippine mobile number is contact info, never a reference', () => {
  const result = extractReference(['09171234567', 'VeeJay Footwear'])
  assert.equal(result.reference, null)
})

test('money lines are excluded', () => {
  const result = extractReference([
    'Total 1234567890123',
    '₱2,000.00 9988776655443',
  ])
  assert.equal(result.reference, null)
})

test('a date and time is not a reference', () => {
  const result = extractReference(['07/15/2026 10:30', '11/18/2026 23:42'])
  assert.equal(result.reference, null)
})

test('nothing readable answers null instead of guessing', () => {
  const result = extractReference(['GCash', 'Successfully sent', 'Thank you'])
  assert.equal(result.reference, null)
  assert.deepEqual(result.candidates, [])
  assert.equal(result.displayGrouped, '')
})

test('grouping: 13 digits use 4-3-6, other lengths use 4-digit chunks', () => {
  assert.equal(formatGrouped(REF), '4043 676 687260')
  assert.equal(formatGrouped('1234567890'), '1234 5678 90')
})

test('OCR text is split into lines before extraction', () => {
  const { reference } = parseReceiptText(`GCash\nRef No. 4043 676 687260\nDone`)
  assert.equal(reference, REF)
})
