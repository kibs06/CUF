// admin-portal/src/lib/saleFields.js
//
// What a search over a sale is allowed to find.
//
// The box used to match order code, customer, store and GCash reference only,
// so an admin holding a product name, a size, a sender, a date off a screenshot
// or the amount off a receipt had nothing to type. The haystack here is every
// field the page can show — the row, the slip, the proof and the gateway trail —
// flattened to lower-case, and the query is AND-ed token by token so
// "lidebeth 990" narrows instead of widening.

import { receiptAddress, receiptRowState } from './receiptTrail.js'

// Local copies of the app's money/date/short-code formats. `lib/constants.js`
// reads `import.meta.env` at module scope, which Node's test runner has no
// notion of; keeping this file dependency-free is what lets `node --test` cover
// the search without a bundler. The output must stay identical to what the
// table prints, so the same strings can be typed into the box.
function money(value) {
  const amount = Number(value) || 0
  return `\u20b1${amount.toLocaleString('en-PH', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`
}

function stamp(value) {
  if (!value) return ''
  const at = new Date(value)
  if (Number.isNaN(at.getTime())) return ''
  return at.toLocaleString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function shortCode(id) {
  const text = (id ?? '').toString()
  return (text.length >= 8 ? text.slice(0, 8) : text).toUpperCase()
}

export function methodLabel(method) {
  const value = (method ?? '').toString().trim().toLowerCase()
  if (value === 'cash') return 'Cash'
  if (value === 'gcash') return 'GCash'
  if (value === 'cod') return 'Cash on delivery'
  if (!value) return 'Not recorded'
  return value.charAt(0).toUpperCase() + value.slice(1)
}

/** A till sale was taken at the counter; everything else came through the app. */
export function channelLabel(source) {
  return (source ?? '').toString().toLowerCase() === 'pos' ? 'Walk-in' : 'Online'
}

export function saleSearchText(sale) {
  if (!sale) return ''

  const amount = Number(sale.amount) || 0
  const proof = sale.proof ?? null
  const receipt = receiptRowState(sale)
  const items = sale.items ?? []
  const events = sale.events ?? []

  const fields = [
    // Identity
    sale.order_id,
    sale.order_code,
    sale.order_id ? shortCode(sale.order_id) : '',
    // People and place
    sale.customer_name,
    sale.customer_email,
    receiptAddress(sale),
    sale.store_name,
    // What it was
    methodLabel(sale.method),
    sale.method,
    channelLabel(sale.source),
    sale.source,
    sale.order_status,
    sale.fulfillment,
    // Money, as typed or as printed
    amount,
    amount.toFixed(2),
    money(amount),
    // GCash evidence
    sale.gcash_reference_number,
    sale.gcash_transaction_id,
    proof?.reference_number,
    proof?.sender_name,
    proof?.status,
    proof?.attempt_no,
    proof?.amount_paid,
    // Receipt delivery
    receipt.meta?.label,
    receipt.state,
    receiptAddress(sale),
    sale.receipt_emailed_at ? stamp(sale.receipt_emailed_at) : '',
    sale.receipt_email_last_error,
    // Dates
    stamp(sale.created_at),
    sale.paid_at ? stamp(sale.paid_at) : '',
    // Gateway trail
    sale.intent?.paymongo_payment_intent_id,
    sale.intent?.checkout_session_id,
    sale.intent?.status,
    // Line items
    ...items.flatMap((item) => [item.product_name, item.size]),
    // Webhook events
    ...events.map((event) => event.event_type),
  ]

  return fields
    .filter((value) => value !== null && value !== undefined && value !== '')
    .join(' ')
    .toLowerCase()
}

/** Every whitespace-separated token has to appear somewhere in the sale. */
export function matchesSaleSearch(sale, query) {
  const tokens = String(query ?? '')
    .trim()
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
  if (!tokens.length) return true
  const haystack = saleSearchText(sale)
  return tokens.every((token) => haystack.includes(token))
}
