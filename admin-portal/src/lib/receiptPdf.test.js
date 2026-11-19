import test from 'node:test'
import assert from 'node:assert/strict'

import { buildReceiptPdf, receiptPdfFilename } from './receiptPdf.js'

const POS_SALE = {
  id: 'd1c1bb63-1111-2222-3333-444455556666',
  order_code: '',
  store_name: 'LIDEBETH SHOE TRADING',
  customer_name: 'Lidebeth Arrosa',
  customer_email: 'Lidebeth5D@gmail.com',
  created_at: '2026-11-19T08:38:00.000Z',
  payment_verified_at: '2026-11-19T08:38:10.000Z',
  total_amount: 990,
  amount_tendered: 1000,
  change_amount: 10,
  payment_method: 'cash',
  source: 'pos',
  order_items: [
    { product_name: 'Black Leather Sandals', size: '38', quantity: 1, unit_price: 990 },
  ],
}

const GCASH_SALE = {
  order_id: 'a1b2c3d4-0000-0000-0000-000000000000',
  order_code: '1F12CB92',
  store_name: 'CUFMAI Shoe Store',
  customer_name: 'Keith Vincent D Abalo',
  customer_email: 'keith@example.com',
  created_at: '2026-11-18T03:13:00.000Z',
  paid_at: '2026-11-18T03:13:00.000Z',
  amount: 250,
  method: 'gcash',
  source: 'online',
  items: [{ product_name: 'Canvas Sneakers', size: '42', quantity: 1, unit_price: 250 }],
  proof: {
    reference_number: '4047398097426',
    sender_name: 'Keith Vincent D Abalo',
    amount_paid: 250,
    status: 'verified',
  },
}

function pdfBytes(order) {
  return new Uint8Array(buildReceiptPdf(order).output('arraybuffer'))
}

test('builds a %PDF file for a POS sale', () => {
  const bytes = pdfBytes(POS_SALE)
  assert.equal(new TextDecoder().decode(bytes.slice(0, 5)), '%PDF-')
  assert.ok(bytes.length > 800, `expected a real document, got ${bytes.length} bytes`)
})

test('builds a file for a GCash sale with a proof', () => {
  const bytes = pdfBytes(GCASH_SALE)
  assert.equal(new TextDecoder().decode(bytes.slice(0, 5)), '%PDF-')
})

test('survives a sale with no item lines', () => {
  const bytes = pdfBytes({ ...POS_SALE, order_items: [] })
  assert.equal(new TextDecoder().decode(bytes.slice(0, 5)), '%PDF-')
})

test('survives an order with almost every field missing', () => {
  const bytes = pdfBytes({})
  assert.equal(new TextDecoder().decode(bytes.slice(0, 5)), '%PDF-')
})

test('long item lists paginate instead of overflowing one page', () => {
  const items = Array.from({ length: 40 }, (_, i) => ({
    product_name: `A rather long product name that has to wrap on the page ${i + 1}`,
    size: '39',
    quantity: 1,
    unit_price: 100,
  }))
  const doc = buildReceiptPdf({ ...POS_SALE, order_items: items })
  assert.ok(doc.getNumberOfPages() > 1, 'expected the receipt to continue onto another page')
})

test('filename uses the order code and strips anything unsafe', () => {
  assert.equal(receiptPdfFilename(GCASH_SALE), 'receipt-1F12CB92.pdf')
  assert.equal(
    receiptPdfFilename({ id: 'd1c1bb63-1111-2222-3333-444455556666' }),
    'receipt-D1C1BB63.pdf',
  )
  assert.equal(receiptPdfFilename({ order_code: '../etc/passwd' }), 'receipt-etc-passwd.pdf')
  assert.equal(receiptPdfFilename({}), 'receipt-sale.pdf')
})
