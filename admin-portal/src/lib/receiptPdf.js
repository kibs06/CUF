// admin-portal/src/lib/receiptPdf.js
//
// The receipt as a file, not a dialog.
//
// `printReceipt` writes an HTML document and hands it to the browser's print
// dialog, where "Save as PDF" is one option among several. That is fine for
// printing, but an admin who wants to attach the receipt to an email or keep it
// needs a file that exists afterwards. This module lays the same sale out on an
// A5 page with jsPDF and saves it as `receipt-<code>.pdf`.
//
// It reuses the money, code, fulfilment and payment labels from `receipt.js`,
// so the PDF and the emailed/printed copy agree about what they call things.
// Layout is drawn as text rather than rendered from the DOM: text stays
// selectable, the file is a few kilobytes, and nothing depends on the admin's
// screen size.

import { jsPDF } from 'jspdf'

import {
  receiptCode,
  receiptFulfillment,
  receiptMoney,
  receiptPaymentLabel,
} from './receipt.js'

const PAGE_W = 148 // A5, mm
const MARGIN = 12
const CONTENT_W = PAGE_W - MARGIN * 2
const BOTTOM = 196

const INK = [42, 27, 16]
const MUTED = [138, 122, 104]
const BRAND = [107, 66, 38]
const RULE = [217, 210, 199]

function line(doc, str, x, y, { size = 9, style = 'normal', color = INK, align = 'left' } = {}) {
  doc.setFont('helvetica', style)
  doc.setFontSize(size)
  doc.setTextColor(color[0], color[1], color[2])
  doc.text(String(str ?? ''), x, y, { align })
}

function dashed(doc, y) {
  doc.setDrawColor(RULE[0], RULE[1], RULE[2])
  doc.setLineWidth(0.2)
  doc.setLineDashPattern([1, 1], 0)
  doc.line(MARGIN, y, PAGE_W - MARGIN, y)
  doc.setLineDashPattern([], 0)
}

function detail(doc, y, label, value, { strong = false } = {}) {
  line(doc, label, MARGIN, y, { size: 8.5, color: MUTED })
  line(doc, value, PAGE_W - MARGIN, y, {
    size: 8.5,
    style: strong ? 'bold' : 'normal',
    align: 'right',
  })
  return y + 5
}

function stamp(value) {
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

function sizeLabel(size) {
  const text = (size ?? '').toString().trim()
  if (!text) return ''
  return text.toLowerCase().startsWith('size') ? text : `Size ${text}`
}

/** The sale as the database writes it, or the shape the admin table maps it to. */
function normalise(order) {
  const proof = order?.proof ?? null
  return {
    code: receiptCode(order),
    store: (order?.store_name ?? 'CUFMAI').toString(),
    total: Number(order?.total_amount ?? order?.amount) || 0,
    isPos: (order?.source ?? '').toString().toLowerCase() === 'pos',
    items: order?.order_items ?? order?.items ?? [],
    customer: order?.customer_name ?? 'Customer',
    email: (order?.customer_email ?? order?.receipt_email_to ?? '').toString().trim(),
    placedAt: stamp(order?.created_at),
    paidAt: stamp(order?.paid_at ?? order?.payment_verified_at),
    orderId: (order?.order_id ?? order?.id ?? '').toString(),
    method: order?.payment_method ?? order?.method,
    tendered: Number(order?.amount_tendered ?? order?.tendered),
    change: Number(order?.change_amount ?? order?.change),
    gcashReference: (proof?.reference_number ?? order?.gcash_reference_number ?? '')
      .toString()
      .trim(),
    gcashTransaction: (order?.gcash_transaction_id ?? '').toString().trim(),
    sender: (proof?.sender_name ?? '').toString().trim(),
    amountSent: proof?.amount_paid == null ? null : Number(proof.amount_paid),
    fulfilment: receiptFulfillment(order),
  }
}

/**
 * The whole A5 receipt for one sale. Pure enough to test: no DOM, no window.
 */
export function buildReceiptPdf(order) {
  const sale = normalise(order)
  const doc = new jsPDF({ unit: 'mm', format: 'a5', compress: true })
  doc.setProperties({
    title: `Receipt #${sale.code}`,
    subject: `${sale.store} — sale receipt`,
    creator: 'CUFMAI Admin',
  })

  const center = PAGE_W / 2
  let y = 18

  line(doc, sale.store.toUpperCase(), center, y, { size: 7.5, color: MUTED, align: 'center' })
  y += 8
  line(doc, 'SALE RECEIPT', center, y, { size: 15, style: 'bold', align: 'center' })
  y += 6
  line(doc, `#${sale.code}`, center, y, { size: 9, color: MUTED, align: 'center' })
  y += 5
  line(doc, `${sale.isPos ? 'WALK-IN' : 'ONLINE'}   ·   PAID`, center, y, {
    size: 7,
    style: 'bold',
    color: BRAND,
    align: 'center',
  })
  y += 5

  dashed(doc, y)
  y += 6

  y = detail(doc, y, 'Date', sale.placedAt || '—')
  y = detail(doc, y, 'Customer', sale.customer)
  if (sale.email) y = detail(doc, y, 'Email', sale.email)
  if (sale.paidAt) y = detail(doc, y, 'Paid at', sale.paidAt)
  if (sale.orderId) y = detail(doc, y, 'Order', `#${sale.orderId.slice(0, 8)}`)

  y += 1
  dashed(doc, y)
  y += 7

  line(doc, 'ITEM', MARGIN, y, { size: 7, style: 'bold', color: MUTED })
  line(doc, 'AMOUNT', PAGE_W - MARGIN, y, { size: 7, style: 'bold', color: MUTED, align: 'right' })
  y += 5

  if (!sale.items.length) {
    line(doc, 'No item lines were recorded for this sale.', MARGIN, y, {
      size: 8.5,
      color: MUTED,
    })
    y += 6
  } else {
    for (const item of sale.items) {
      if (y > BOTTOM) {
        doc.addPage()
        y = 18
      }
      const quantity = Number(item.quantity) || 0
      const unitPrice = Number(item.unit_price) || 0
      const name = (item.product_name ?? item.products?.name ?? 'Product').toString()
      const size = sizeLabel(item.size)
      const label = `${quantity} × ${name}${size ? ` (${size})` : ''}`

      doc.setFont('helvetica', 'normal')
      doc.setFontSize(8.5)
      const wrapped = doc.splitTextToSize(label, CONTENT_W - 28)
      wrapped.forEach((textLine, index) => {
        line(doc, textLine, MARGIN, y + index * 4.2, { size: 8.5 })
      })
      line(doc, receiptMoney(unitPrice * quantity), PAGE_W - MARGIN, y, {
        size: 8.5,
        align: 'right',
      })
      y += wrapped.length * 4.2
      line(doc, `${receiptMoney(unitPrice)} each`, MARGIN, y, { size: 7.5, color: MUTED })
      y += 5
    }
  }

  y += 1
  dashed(doc, y)
  y += 7

  line(doc, 'TOTAL', MARGIN, y, { size: 8, style: 'bold', color: MUTED })
  line(doc, receiptMoney(sale.total), PAGE_W - MARGIN, y + 1, {
    size: 14,
    style: 'bold',
    align: 'right',
  })
  y += 8

  y = detail(doc, y, 'Paid via', receiptPaymentLabel(sale.method), { strong: true })
  if (sale.isPos && Number.isFinite(sale.tendered) && sale.tendered > 0) {
    y = detail(doc, y, 'Cash tendered', receiptMoney(sale.tendered))
    if (Number.isFinite(sale.change)) y = detail(doc, y, 'Change', receiptMoney(sale.change))
  }
  y = detail(doc, y, 'Fulfilment', sale.fulfilment)
  if (sale.gcashReference) y = detail(doc, y, 'GCash reference', sale.gcashReference)
  if (sale.sender) y = detail(doc, y, 'Sender', sale.sender)
  if (sale.amountSent != null && Number.isFinite(sale.amountSent)) {
    y = detail(doc, y, 'Amount sent', receiptMoney(sale.amountSent))
  }
  if (sale.gcashTransaction) y = detail(doc, y, 'GCash transaction', sale.gcashTransaction)

  y += 1
  dashed(doc, y)
  y += 7

  line(doc, 'Keep this receipt as proof of the sale.', center, y, {
    size: 7.5,
    color: MUTED,
    align: 'center',
  })
  line(doc, `Quote #${sale.code} if you need help with this order.`, center, y + 4, {
    size: 7.5,
    color: MUTED,
    align: 'center',
  })

  return doc
}

/** `receipt-1F12CB92.pdf` — the code, with anything a filesystem dislikes removed. */
export function receiptPdfFilename(order) {
  const code = receiptCode(order) || 'sale'
  const safe = code.replace(/[^A-Za-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '')
  return `receipt-${safe || 'sale'}.pdf`
}

/** Saves the PDF through the browser's own download path. */
export function downloadReceiptPdf(order) {
  const doc = buildReceiptPdf(order)
  const filename = receiptPdfFilename(order)
  doc.save(filename)
  return filename
}
