// admin-portal/src/lib/receipt.js
//
// The admin's own copy of a receipt.
//
// The customer keeps the copy the app emailed them and the seller keeps one in
// the POS history; this is the third copy, the one support can produce from the
// portal when a customer writes in months later with a question and nobody
// wants to depend on the other side's inbox.
//
// It is the same receipt the customer was emailed — store header, code, date,
// line items, money breakdown — rendered as a standalone HTML document so it
// prints (or saves as PDF) through the browser's own dialog. Nothing here is a
// screenshot of a page: the document is self-contained, so what comes out of
// the printer is the receipt and not the admin portal's chrome.
//
// `buildReceiptDocument` is pure — a string in, a string out — which is what
// makes it testable with `node --test`. Opening the window lives in
// `printReceipt`, the only part that needs a browser.

const CANVAS = '#FAF6F0'
const CARD = '#FFFFFF'
const BRAND = '#6B4226'
const INK = '#2A1B10'
const MUTED = '#8A7A68'
const RULE = '#EDE4DA'

function escapeHtml(value) {
  return (value ?? '')
    .toString()
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

/** Money as the app writes it: ₱1,234.50. */
export function receiptMoney(value) {
  const amount = Number(value)
  const safe = Number.isFinite(amount) ? amount : 0
  return (
    '\u20b1' +
    safe.toLocaleString('en-PH', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  )
}

/**
 * The code the receipt is quoted by: the order's own code when it has one
 * (online orders do), else the first eight characters of the id — the same
 * short code the app prints.
 */
export function receiptCode(order) {
  const code = (order?.order_code ?? '').toString().trim()
  if (code) return code
  const id = (order?.id ?? '').toString()
  return (id.length >= 8 ? id.slice(0, 8) : id).toUpperCase()
}

/** A till sale was handed over the counter; an online order was not. */
export function receiptFulfillment(order) {
  if ((order?.source ?? '').toString().toLowerCase() === 'pos') return 'In store'
  return (order?.fulfillment ?? '').toString().toLowerCase() === 'delivery'
    ? 'Delivery'
    : 'Store pickup'
}

function paymentLabel(method) {
  const value = (method ?? '').toString().toLowerCase()
  if (value === 'cash') return 'Cash'
  if (value === 'gcash') return 'GCash'
  if (value === 'cod') return 'Cash on delivery'
  if (!value) return 'Not recorded'
  return value.charAt(0).toUpperCase() + value.slice(1)
}

/**
 * A ledger row (mapped for the admin table) as the receipt builders read it.
 * `amount`/`items`/`tendered`/`change` are the table's names; the builders want
 * the order's own.
 */
export function asReceiptOrder(sale) {
  if (!sale) return null
  return {
    ...sale,
    total_amount: sale.total_amount ?? sale.amount,
    order_items: sale.order_items ?? sale.items ?? [],
    amount_tendered: sale.amount_tendered ?? sale.tendered,
    change_amount: sale.change_amount ?? sale.change,
    email: sale.customer_email,
  }
}

/** The payment label as any receipt copy prints it (HTML and PDF). */
export function receiptPaymentLabel(method) {
  return paymentLabel(method)
}

function dateLabel(value) {
  const at = new Date(value ?? '')
  if (Number.isNaN(at.getTime())) return ''
  return at.toLocaleString('en-PH', {
    timeZone: 'Asia/Manila',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

function itemRows(order) {
  const items = order?.order_items ?? []
  if (!items.length) {
    return `<tr><td colspan="2" style="padding:8px 0;color:${MUTED};font-size:13px;">No item lines were recorded for this order.</td></tr>`
  }
  return items
    .map((item) => {
      const name = (item.product_name ?? item.products?.name ?? 'Product').toString()
      const size = (item.size ?? '').toString().trim()
      const label = size ? `${name} (${size.startsWith('Size') ? size : `Size ${size}`})` : name
      const quantity = Number(item.quantity) || 0
      const unitPrice = Number(item.unit_price) || 0
      return `
        <tr>
          <td style="padding:8px 0;color:${INK};font-size:14px;">
            <span style="color:${MUTED};">${quantity}&times;</span> ${escapeHtml(label)}
          </td>
          <td align="right" style="padding:8px 0;color:${INK};font-size:14px;white-space:nowrap;">
            ${receiptMoney(unitPrice * quantity)}
          </td>
        </tr>`
    })
    .join('')
}

function row(label, value) {
  return `
    <tr>
      <td style="padding:4px 0;color:${MUTED};font-size:13px;">${escapeHtml(label)}</td>
      <td align="right" style="padding:4px 0;color:${INK};font-size:13px;">${escapeHtml(value)}</td>
    </tr>`
}

/**
 * The whole printable document for one order.
 *
 * `options.storeLocation` comes from the store row; the admin order list only
 * joins the store name, so it is optional. The emailed line at the bottom is
 * the point of the admin copy: it says whether the customer actually has their
 * own copy, and when it went.
 */
export function buildReceiptDocument(order, options = {}) {
  const store = (order?.store_name ?? 'CUFMAI').toString()
  const location = (options.storeLocation ?? '').toString().trim()
  const code = receiptCode(order)
  const placedAt = dateLabel(order?.created_at)
  const isPos = (order?.source ?? '').toString().toLowerCase() === 'pos'
  const total = Number(order?.total_amount) || 0

  const tendered = isPos ? Number(order?.amount_tendered) : NaN
  const change = isPos ? Number(order?.change_amount) : NaN
  const reference = (order?.gcash_reference_number ?? '').toString().trim()

  const emailedAt = (order?.receipt_emailed_at ?? '').toString().trim()
  const emailedTo = (order?.receipt_email_to ?? order?.customer_email ?? '').toString().trim()
  const emailedLine = emailedAt
    ? `Customer copy emailed ${dateLabel(emailedAt)}${emailedTo ? ` to ${escapeHtml(emailedTo)}` : ''}.`
    : 'Customer copy has not been emailed yet.'

  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Receipt #${escapeHtml(code)} — ${escapeHtml(store)}</title>
    <style>
      /* A5 is what the app prints; the browser dialog also offers "Save as PDF",
         which is how the admin keeps a copy without a printer. */
      @page { size: A5; margin: 10mm; }
      body { margin: 0; }
      @media print { body { background: #FFFFFF; } }
    </style>
  </head>
  <body style="margin:0;padding:24px;background:${CANVAS};font-family:Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;margin:0 auto;background:${CARD};border-radius:16px;overflow:hidden;border:1px solid ${RULE};">
      <tr>
        <td style="padding:24px 24px 16px;">
          <p style="margin:0;color:${BRAND};font-size:12px;letter-spacing:2px;text-transform:uppercase;">${escapeHtml(store)}</p>
          ${location ? `<p style="margin:4px 0 0;color:${MUTED};font-size:12px;">${escapeHtml(location)}</p>` : ''}
          <h1 style="margin:16px 0 4px;color:${INK};font-size:22px;">Your receipt</h1>
          <p style="margin:0;color:${MUTED};font-size:13px;">
            Order #${escapeHtml(code)} &middot; ${escapeHtml(placedAt)}
          </p>
          ${order?.customer_name ? `<p style="margin:6px 0 0;color:${MUTED};font-size:13px;">For ${escapeHtml(order.customer_name)}</p>` : ''}
          ${emailedTo ? `<p style="margin:6px 0 0;color:${MUTED};font-size:13px;">${escapeHtml(emailedTo)}</p>` : ''}
        </td>
      </tr>
      <tr><td style="padding:0 24px;"><div style="height:1px;background:${RULE};"></div></td></tr>
      <tr>
        <td style="padding:16px 24px 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            ${itemRows(order)}
          </table>
        </td>
      </tr>
      <tr>
        <td style="padding:8px 24px 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr>
              <td style="padding:10px 0 0;color:${INK};font-size:15px;font-weight:bold;">Total</td>
              <td align="right" style="padding:10px 0 0;color:${INK};font-size:15px;font-weight:bold;">${receiptMoney(total)}</td>
            </tr>
            ${row('Paid via', paymentLabel(order?.payment_method))}
            ${reference ? row('GCash reference', reference) : ''}
            ${Number.isFinite(tendered) && tendered > 0 ? row('Cash tendered', receiptMoney(tendered)) : ''}
            ${Number.isFinite(change) && Number.isFinite(tendered) && tendered > 0 ? row('Change', receiptMoney(change)) : ''}
            ${row('Fulfilment', receiptFulfillment(order))}
          </table>
        </td>
      </tr>
      <tr>
        <td style="padding:20px 24px 24px;">
          <p style="margin:0;color:${MUTED};font-size:12px;line-height:1.6;">
            ${emailedLine} Quote receipt #${escapeHtml(code)} if you need help with this order.
          </p>
        </td>
      </tr>
    </table>
    <p style="max-width:520px;margin:16px auto 0;color:${MUTED};font-size:11px;text-align:center;">
      CUFMAI Marketplace &middot; copy printed from the admin portal.
    </p>
  </body>
</html>`
}

/**
 * Open the receipt in its own window and ask the browser to print it.
 *
 * A separate window (rather than a print-only block inside the portal) keeps
 * the printed page to the receipt alone. If the popup is blocked there is
 * nothing to print, so the caller gets `false` and can say so.
 */
export function printReceipt(order, options = {}) {
  if (typeof window === 'undefined') return false
  const win = window.open('', '_blank', 'width=520,height=780')
  if (!win) return false
  win.document.open()
  win.document.write(buildReceiptDocument(order, options))
  win.document.close()
  win.focus()
  // The document is written synchronously, but give the browser a tick to lay
  // it out before asking for the print dialog — otherwise some engines print
  // the previous blank page.
  setTimeout(() => win.print(), 250)
  return true
}
