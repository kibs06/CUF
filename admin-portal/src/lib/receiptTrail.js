// admin-portal/src/lib/receiptTrail.js
//
// Reading the receipt trail out of an order row, for the admin monitor.
//
// Every fact here already exists on `orders` (migration 20261119120000): when
// the receipt went out and to whom, how many attempts were made, the last error
// and when the next try is due. Nothing in this file writes or resends — it
// only turns those columns into the one state support needs to read: does the
// customer have their copy, and if not, why and what happens next.
//
// Pure on purpose: `node --test` can hold it to the real shapes without a
// browser or a database.

/** The sender's own lease: a claim older than this is dead, not in flight. */
export const RECEIPT_LEASE_MS = 5 * 60 * 1000

export const RECEIPT_STATES = ['sent', 'sending', 'retrying', 'failed', 'pending']

/**
 * 'sent'      the customer has it (the stamp is only written after SMTP accepted)
 * 'sending'   a send is in flight right now
 * 'retrying'  it failed and the backoff has another try scheduled
 * 'failed'    it failed, and no retry is scheduled — a person has to look
 * 'pending'   no attempt yet
 */
export function receiptState(order, now = Date.now()) {
  if ((order?.receipt_emailed_at ?? '').toString().trim()) return 'sent'

  const attempts = Number(order?.receipt_email_attempts) || 0
  const sendingAt = Date.parse(order?.receipt_email_sending_since ?? '')
  if (Number.isFinite(sendingAt) && now - sendingAt < RECEIPT_LEASE_MS) {
    return 'sending'
  }
  if (attempts <= 0) return 'pending'

  const nextAt = Date.parse(order?.receipt_email_next_attempt_at ?? '')
  if (Number.isFinite(nextAt) && nextAt > now) return 'retrying'
  return 'failed'
}

export const RECEIPT_STATE_META = {
  sent: {
    label: 'Sent',
    tone: 'delivered',
    hint: 'The customer has their copy.',
  },
  sending: {
    label: 'Sending',
    tone: 'processing',
    hint: 'A send is in flight right now.',
  },
  retrying: {
    label: 'Retrying',
    tone: 'pending',
    hint: 'A failed send is queued for another try.',
  },
  failed: {
    label: 'Failed',
    tone: 'failed',
    hint: 'No retry is scheduled — this one needs a person.',
  },
  pending: {
    label: 'Not sent',
    tone: 'none',
    hint: 'No receipt has gone out yet.',
  },
}

/**
 * A sale nobody can be emailed about.
 *
 * A till sale rung up without a customer address is not a failed send and not a
 * send waiting to happen — there is no recipient, now or later. Letting it read
 * "Not sent" beside real failures makes the ledger look broken, so the tables
 * show this instead.
 */
export const RECEIPT_NO_EMAIL_META = {
  label: 'No email on file',
  tone: 'none',
  hint: 'The sale has no customer address, so no receipt will be emailed.',
}

/**
 * The state shown in a table cell, which is the delivery state except that an
 * address-less sale reports its own condition rather than a pending send.
 */
export function receiptRowState(order, now = Date.now()) {
  const state = receiptState(order, now)
  if (state === 'pending' && !receiptAddress(order)) {
    return { state: 'no_email', meta: RECEIPT_NO_EMAIL_META }
  }
  return { state, meta: RECEIPT_STATE_META[state] }
}

export const RECEIPT_FILTERS = [
  { key: 'all', label: 'All sales' },
  { key: 'sent', label: 'Sent' },
  { key: 'waiting', label: 'Waiting' },
  { key: 'failed', label: 'Failed' },
]

export function matchesReceiptFilter(order, filter, now = Date.now()) {
  if (filter === 'all' || !filter) return true
  const state = receiptState(order, now)
  if (filter === 'sent') return state === 'sent'
  if (filter === 'failed') return state === 'failed'
  if (filter === 'waiting') {
    return state === 'pending' || state === 'sending' || state === 'retrying'
  }
  return true
}

/** Where the customer's copy went, or would go. */
export function receiptAddress(order) {
  const direct = (order?.receipt_email_to ?? '').toString().trim()
  if (direct) return direct
  const typed = (order?.customer_email ?? '').toString().trim()
  if (typed) return typed
  return (order?.profiles?.email ?? '').toString().trim()
}

/** Receipt code: the order code, else the eight-character id the app shows. */
export function receiptCodeOf(order) {
  const code = (order?.order_code ?? '').toString().trim()
  if (code) return code
  const id = (order?.id ?? '').toString()
  return (id.length >= 8 ? id.slice(0, 8) : id).toUpperCase()
}

export function receiptSearchText(order) {
  return [
    receiptCodeOf(order),
    order?.store_name,
    order?.customer_name,
    receiptAddress(order),
    order?.payment_method,
    order?.source,
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase()
}

export function matchesReceiptSearch(order, query) {
  const needle = (query ?? '').toString().trim().toLowerCase()
  if (!needle) return true
  return receiptSearchText(order).includes(needle)
}

export function receiptSummary(rows, now = Date.now()) {
  const summary = { total: 0, sent: 0, waiting: 0, failed: 0 }
  for (const order of rows ?? []) {
    summary.total += 1
    const state = receiptState(order, now)
    if (state === 'sent') summary.sent += 1
    else if (state === 'failed') summary.failed += 1
    else summary.waiting += 1
  }
  return summary
}

function csvCell(value) {
  const text = (value ?? '').toString()
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

/** The monitor as a file: one row per sale, the trail as it stands now. */
export function receiptsCsv(rows, now = Date.now()) {
  const header = [
    'Receipt',
    'Store',
    'Customer',
    'Customer email',
    'Receipt email to',
    'Amount',
    'Payment',
    'Source',
    'Order status',
    'Receipt state',
    'Emailed at',
    'Attempts',
    'Last attempt',
    'Last error',
    'Next attempt',
  ]
  const lines = (rows ?? []).map((order) =>
    [
      receiptCodeOf(order),
      order.store_name,
      order.customer_name,
      order.customer_email ?? order.profiles?.email,
      receiptAddress(order),
      Number(order.total_amount) || 0,
      order.payment_method,
      order.source,
      order.status,
      RECEIPT_STATE_META[receiptState(order, now)].label,
      order.receipt_emailed_at,
      Number(order.receipt_email_attempts) || 0,
      order.receipt_email_last_attempt_at,
      order.receipt_email_last_error,
      order.receipt_email_next_attempt_at,
    ]
      .map(csvCell)
      .join(','),
  )
  return [header.join(','), ...lines].join('\n')
}
