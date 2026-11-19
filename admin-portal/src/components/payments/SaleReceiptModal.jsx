import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { AnimatePresence, motion, useReducedMotion } from 'motion/react'
import { Download, Printer, X } from 'lucide-react'

import Badge from '../ui/Badge.jsx'
import Modal from '../ui/Modal.jsx'
import Tooltip from '../ui/Tooltip.jsx'
import { useToast } from '../ui/Toast.jsx'
import { formatCurrency, formatDateTime, shortId } from '../../lib/constants'
import { asReceiptOrder, printReceipt } from '../../lib/receipt.js'
import { proofSignedUrl } from '../../hooks/useManualGcash.js'

const PROOF_STATE_VARIANTS = {
  verified: 'approved',
  pending: 'pending',
  rejected: 'failed',
}

const PROOF_STATE_HINTS = {
  verified: 'The uploaded receipt was accepted, and this sale was marked paid.',
  pending: 'The proof is filed but nobody has accepted or rejected it yet.',
  rejected: 'The proof was refused — the reason is shown beside this badge.',
}

const EVENT_STATUS_VARIANTS = {
  processed: 'processed',
  processing: 'processing',
  received: 'processing',
  amount_mismatch: 'amount_mismatch',
  stock_conflict: 'stock_conflict',
  rejected_signature: 'rejected_signature',
  failed: 'failed',
}

// Paper, not dashboard: the same palette the emailed and printed receipt use,
// so the copy on screen is recognisably the copy the customer got.
const INK = '#2A1B10'
const MUTED = '#8A7A68'
const RULE = '#D9D2C7'

function humanize(value) {
  return String(value ?? '')
    .replace(/[._]/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase())
}

function methodLabel(method) {
  const value = (method ?? '').toString().trim().toLowerCase()
  if (value === 'cash') return 'Cash'
  if (value === 'gcash') return 'GCash'
  if (value === 'cod') return 'Cash on delivery'
  if (!value) return 'Not recorded'
  return value.charAt(0).toUpperCase() + value.slice(1)
}

function channelLabel(source) {
  return (source ?? '').toString().toLowerCase() === 'pos' ? 'Walk-in' : 'Online'
}

function fulfillmentLabel(sale) {
  if ((sale.source ?? '').toLowerCase() === 'pos') return 'In store'
  return (sale.fulfillment ?? '').toLowerCase() === 'delivery' ? 'Delivery' : 'Store pickup'
}

function Dashed() {
  return <div className="my-4 border-t border-dashed" style={{ borderColor: RULE }} />
}

function Line({ label, value, strong = false }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <span style={{ color: MUTED }}>{label}</span>
      <span
        className={`text-right ${strong ? 'font-semibold' : ''} font-mono`}
        style={{ color: INK }}
      >
        {value}
      </span>
    </div>
  )
}

/**
 * The customer's uploaded GCash screenshot.
 *
 * Proofs live in a private bucket, so the thumbnail is a short-lived signed
 * URL minted when the sale is opened, not a stored link. The image is the
 * receipt the customer was looking at when they paid: reference and amount are
 * typed into the fields above, and this is where an admin checks they agree.
 */
function ProofScreenshot({ path, reference, orderCode }) {
  const [state, setState] = useState({ status: 'loading', url: null, error: null })
  const [zoomed, setZoomed] = useState(false)
  const [attempt, setAttempt] = useState(0)
  const [downloading, setDownloading] = useState(false)

  useEffect(() => {
    if (!path) return undefined
    let alive = true
    setState({ status: 'loading', url: null, error: null })
    proofSignedUrl(path)
      .then((url) => {
        if (!alive) return
        setState(
          url
            ? { status: 'ready', url, error: null }
            : {
                status: 'error',
                url: null,
                error: 'No read access to this file — it may have been removed from storage.',
              },
        )
      })
      .catch((err) => {
        if (!alive) return
        setState({
          status: 'error',
          url: null,
          error: err?.message ?? 'Could not load the proof screenshot.',
        })
      })
    return () => {
      alive = false
    }
  }, [path, attempt])

  // Save the file, not just view it: an admin attaching evidence to a case
  // needs the image on disk after the signed link has expired.
  const download = async () => {
    if (state.status !== 'ready') return
    setDownloading(true)
    try {
      const res = await fetch(state.url)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const blob = await res.blob()
      const subtype = (blob.type || 'image/jpeg').split('/')[1] || 'jpg'
      const ext = subtype === 'jpeg' ? 'jpg' : subtype.replace(/[^a-z0-9]/gi, '') || 'jpg'
      const stem = (reference || orderCode || 'sale').toString().replace(/[^A-Za-z0-9_-]+/g, '-')
      const href = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = href
      a.download = `gcash-proof-${stem}.${ext}`
      document.body.appendChild(a)
      a.click()
      a.remove()
      setTimeout(() => URL.revokeObjectURL(href), 1000)
    } catch {
      // A storage response fetch cannot read (CORS) still displays fine, so
      // open it and let the browser's own "Save image as" finish the job.
      window.open(state.url, '_blank', 'noopener')
    } finally {
      setDownloading(false)
    }
  }

  useEffect(() => {
    if (!zoomed) return undefined
    const onKey = (e) => {
      if (e.key === 'Escape') setZoomed(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [zoomed])

  return (
    <div className="mt-3 border-t border-border pt-3">
      <div className="mb-2 flex items-center justify-between gap-3">
        <h4 className="text-[12px] font-medium text-muted">Proof screenshot</h4>
        {state.status === 'ready' && (
          <div className="flex items-center gap-3">
            <Tooltip label="Save the screenshot to your computer as an image file.">
              <button
                type="button"
                onClick={download}
                disabled={downloading}
                className="inline-flex items-center gap-1 text-[11.5px] font-semibold text-primary hover:underline disabled:opacity-50"
              >
                <Download size={12} aria-hidden="true" />
                {downloading ? 'Saving…' : 'Download'}
              </button>
            </Tooltip>
            <Tooltip label="The image link expires after an hour — reload it if it stopped showing.">
              <button
                type="button"
                onClick={() => setAttempt((n) => n + 1)}
                className="text-[11.5px] font-semibold text-primary hover:underline"
              >
                Reload
              </button>
            </Tooltip>
          </div>
        )}
      </div>

      {state.status === 'loading' && (
        <div
          role="status"
          aria-label="Loading proof screenshot"
          className="h-40 animate-pulse rounded-lg border border-border bg-canvas"
        />
      )}

      {state.status === 'error' && (
        <div className="rounded-lg border border-border bg-canvas p-3 text-[11.5px] leading-relaxed text-muted">
          {state.error}{' '}
          <button
            type="button"
            onClick={() => setAttempt((n) => n + 1)}
            className="font-semibold text-primary hover:underline"
          >
            Try again
          </button>
        </div>
      )}

      {state.status === 'ready' && (
        <button
          type="button"
          onClick={() => setZoomed(true)}
          aria-label="Open the GCash proof screenshot full size"
          className="group relative block w-full overflow-hidden rounded-lg border border-border bg-canvas"
        >
          <img
            src={state.url}
            alt={`GCash proof${reference ? ` for reference ${reference}` : ''}`}
            className="max-h-64 w-full object-contain"
            loading="lazy"
          />
          <span className="pointer-events-none absolute bottom-2 right-2 rounded-full bg-black/60 px-2 py-1 text-[10.5px] font-semibold text-white">
            View full size
          </span>
        </button>
      )}

      {zoomed &&
        state.status === 'ready' &&
        createPortal(
          <div
            className="fixed inset-0 z-[70] flex cursor-zoom-out flex-col items-center justify-center bg-black/80 p-4"
            role="dialog"
            aria-modal="true"
            aria-label="GCash proof screenshot"
            onClick={() => setZoomed(false)}
          >
            <button
              type="button"
              onClick={() => setZoomed(false)}
              aria-label="Close image"
              className="absolute right-4 top-4 rounded-full bg-white/10 p-2 text-white transition-colors hover:bg-white/20"
            >
              <X size={20} />
            </button>
            <img
              src={state.url}
              alt={`GCash proof${reference ? ` for reference ${reference}` : ''}`}
              className="max-h-[88vh] max-w-full cursor-default rounded-lg object-contain"
              onClick={(e) => e.stopPropagation()}
            />
            <p className="mt-3 text-[12px] text-white/70">
              {reference ? `Reference ${reference}` : 'Proof screenshot'}
              {orderCode ? ` · Order #${orderCode}` : ''} · click anywhere to close
            </p>
          </div>,
          document.body,
        )}
    </div>
  )
}

function EventTimeline({ events }) {
  const reduce = useReducedMotion()
  const [openPayload, setOpenPayload] = useState(null)

  if (!events?.length) {
    return <p className="text-[12px] text-muted">No webhook events recorded for this sale.</p>
  }

  return (
    <ol className="relative space-y-3 border-l border-border pl-5">
      <AnimatePresence initial={false}>
        {events.map((e, i) => (
          <motion.li
            key={e.id}
            initial={reduce ? false : { opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.25, delay: i * 0.05 }}
          >
            <span className="absolute -left-[5px] mt-1.5 h-2.5 w-2.5 rounded-full border-2 border-white bg-secondary" />
            <div className="flex flex-wrap items-center gap-2">
              <p className="text-[12.5px] font-semibold text-ink">{humanize(e.event_type)}</p>
              <Badge label={e.status} variant={EVENT_STATUS_VARIANTS[e.status] ?? e.status} />
            </div>
            <p className="mt-0.5 text-[11.5px] text-muted">
              {formatDateTime(e.received_at)}
              {e.processed_at ? ` · processed ${formatDateTime(e.processed_at)}` : ''}
              {e.amount != null ? ` · ${formatCurrency(e.amount)}` : ''}
            </p>
            {e.redacted_payload && (
              <div>
                <button
                  type="button"
                  onClick={() => setOpenPayload(openPayload === e.id ? null : e.id)}
                  className="mt-1 text-[11.5px] font-semibold text-primary hover:underline"
                >
                  {openPayload === e.id ? 'Hide raw event' : 'View raw event'}
                </button>
                {openPayload === e.id && (
                  <pre className="mt-2 max-h-48 overflow-auto rounded-xl border border-border bg-canvas p-3 text-[11px] leading-relaxed text-muted">
                    {JSON.stringify(e.redacted_payload, null, 2)}
                  </pre>
                )}
              </div>
            )}
          </motion.li>
        ))}
      </AnimatePresence>
    </ol>
  )
}

/**
 * One paid sale, shown as the receipt it is.
 *
 * The dashboard's cards are fine for scanning a list, but an admin opening a
 * sale is usually answering "what did this customer actually buy, and what
 * proves they paid?". So the body is the slip: shop, code, date, items, total,
 * how it was paid — and the confirmation trail sits underneath in muted type,
 * because it explains the paper rather than competing with it.
 */
export default function SaleReceiptModal({ sale, onClose }) {
  const { showToast } = useToast()
  const intent = sale?.intent
  const proof = sale?.proof ?? null
  const isGcash = (sale?.method ?? '').toString().toLowerCase() === 'gcash'
  // The transfer's own reference beats the order column: it is what the sender
  // sees in their GCash app, which is what they quote when they ask for help.
  const gcashReference =
    (proof?.reference_number ?? '').toString().trim() ||
    (sale?.gcash_reference_number ?? '').toString().trim()
  const amountSent =
    proof?.amount_paid == null ? null : Number(proof.amount_paid)
  const amountMismatch =
    amountSent != null && Number.isFinite(amountSent) && amountSent !== Number(sale?.amount)
  const items = sale?.items ?? []
  const code = sale ? sale.order_code || shortId(sale.order_id) : ''
  const tendered = Number.isFinite(sale?.tendered) && sale.tendered > 0 ? sale.tendered : null

  // Both copies read the order as the database writes it; the row here is
  // mapped for the table, so hand them the names they expect.
  const asOrder = () => asReceiptOrder(sale)

  const handlePrint = () => {
    if (!sale) return
    if (!printReceipt(asOrder())) {
      showToast('Allow pop-ups for this site to print the receipt', 'error')
    }
  }

  // The PDF writer is the heaviest thing on this page and is only needed when
  // someone actually asks for a file, so it loads on the click.
  const handleDownload = async () => {
    if (!sale) return
    try {
      const { downloadReceiptPdf } = await import('../../lib/receiptPdf.js')
      showToast(`Saved ${downloadReceiptPdf(asOrder())}`)
    } catch (err) {
      showToast(err?.message ?? 'Could not build the receipt PDF', 'error')
    }
  }

  return (
    <Modal
      open={!!sale}
      onClose={onClose}
      title={sale ? `Receipt #${code}` : ''}
      size="xl"
      footer={
        <>
          <Tooltip label="Close without doing anything else." side="top">
            <button
              type="button"
              onClick={onClose}
              className="inline-flex h-9 items-center rounded-lg border border-border bg-card px-3.5 text-[12px] font-semibold text-ink transition-colors hover:border-primary hover:text-primary"
            >
              Close
            </button>
          </Tooltip>
          <Tooltip label="Opens the A5 receipt in the print dialog — Save as PDF works there too.">
            <button
              type="button"
              onClick={handlePrint}
              className="inline-flex h-9 items-center gap-1.5 rounded-lg border border-border bg-card px-3.5 text-[12px] font-semibold text-ink transition-colors hover:border-primary hover:text-primary"
            >
              <Printer size={13} aria-hidden="true" />
              Print
            </button>
          </Tooltip>
          <Tooltip label="Saves a receipt-<code>.pdf file you can keep or attach.">
            <button
              type="button"
              onClick={handleDownload}
              className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-primary px-3.5 text-[12px] font-semibold text-white transition-colors hover:bg-secondary"
            >
              <Download size={13} aria-hidden="true" />
              Download PDF
            </button>
          </Tooltip>
        </>
      }
    >
      {sale && (
        <div className="space-y-4">
          <div
            className="mx-auto w-full max-w-[440px] rounded-2xl px-6 py-7 text-[13px] shadow-[0_18px_40px_-24px_rgba(42,27,16,0.45)]"
            style={{ background: '#FFFDF9', border: '1px solid #E7DED2', color: INK }}
          >
            <div className="text-center">
              <p
                className="text-[10.5px] font-semibold uppercase tracking-[0.22em]"
                style={{ color: MUTED }}
              >
                {sale.store_name}
              </p>
              <p className="mt-2 font-display text-[20px] font-bold leading-tight">
                Sale receipt
              </p>
              <p className="mt-1 font-mono text-[12px]" style={{ color: '#6B5E52' }}>
                #{code}
              </p>
              <div className="mt-2.5 flex items-center justify-center gap-1.5">
                <span
                  className="rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em]"
                  style={{ background: '#F1E9DE', color: '#6B4226' }}
                >
                  {channelLabel(sale.source)}
                </span>
                <span
                  className="rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em]"
                  style={{ background: '#E6F3F1', color: '#2F7A72' }}
                >
                  Paid
                </span>
              </div>
            </div>

            <Dashed />

            <div className="space-y-1 text-[12px]">
              <Line label="Date" value={formatDateTime(sale.created_at)} />
              <Line label="Customer" value={sale.customer_name} />
              {sale.customer_email && <Line label="Email" value={sale.customer_email} />}
              {sale.paid_at && <Line label="Paid at" value={formatDateTime(sale.paid_at)} />}
              <Line label="Order" value={`#${shortId(sale.order_id)}`} />
            </div>

            <Dashed />

            <div
              className="flex items-baseline justify-between text-[10px] font-semibold uppercase tracking-[0.14em]"
              style={{ color: MUTED }}
            >
              <span>Item</span>
              <span>Amount</span>
            </div>
            <div className="mt-2 space-y-2.5">
              {items.length === 0 ? (
                <p className="text-[12px]" style={{ color: MUTED }}>
                  No item lines were recorded for this sale.
                </p>
              ) : (
                items.map((item, index) => {
                  const quantity = Number(item.quantity) || 0
                  const unitPrice = Number(item.unit_price) || 0
                  const size = (item.size ?? '').toString().trim()
                  return (
                    <div
                      key={`${item.product_name}-${index}`}
                      className="flex items-start justify-between gap-3"
                    >
                      <div className="min-w-0">
                        <p className="leading-snug">
                          <span style={{ color: MUTED }}>{quantity}&times;</span>{' '}
                          <span className="font-medium">{item.product_name}</span>
                        </p>
                        <p className="mt-0.5 text-[11px]" style={{ color: MUTED }}>
                          {size ? (size.toLowerCase().startsWith('size') ? size : `Size ${size}`) : ''}
                          {size ? ' · ' : ''}
                          {formatCurrency(unitPrice)} each
                        </p>
                      </div>
                      <span className="shrink-0 font-mono">
                        {formatCurrency(unitPrice * quantity)}
                      </span>
                    </div>
                  )
                })
              )}
            </div>

            <Dashed />

            <div className="flex items-baseline justify-between">
              <span
                className="text-[10.5px] font-semibold uppercase tracking-[0.18em]"
                style={{ color: MUTED }}
              >
                Total
              </span>
              <span className="font-mono text-[22px] font-bold">
                {formatCurrency(sale.amount)}
              </span>
            </div>

            <div className="mt-3 space-y-1 text-[12px]">
              <Line label="Paid via" value={methodLabel(sale.method)} strong />
              {tendered != null && (
                <Line label="Cash tendered" value={formatCurrency(tendered)} />
              )}
              {tendered != null && Number.isFinite(sale.change) && (
                <Line label="Change" value={formatCurrency(sale.change)} />
              )}
              <Line label="Fulfilment" value={fulfillmentLabel(sale)} />
              {isGcash && gcashReference && (
                <Line label="GCash reference" value={gcashReference} />
              )}
              {isGcash && proof?.sender_name && (
                <Line label="Sender" value={proof.sender_name} />
              )}
              {isGcash && amountSent != null && (
                <Line label="Amount sent" value={formatCurrency(amountSent)} />
              )}
              {sale.gcash_transaction_id && (
                <Line label="GCash transaction" value={sale.gcash_transaction_id} />
              )}
            </div>

            <Dashed />

            <p
              className="text-center text-[10.5px] leading-relaxed"
              style={{ color: MUTED }}
            >
              Keep this receipt as proof of the sale. Quote #{code} if you need
              help with this order.
            </p>
          </div>

          {/* Why the paper can be trusted: the confirmation trail, secondary. */}
          <div className="rounded-xl border border-border bg-card p-4">
            <h3 className="text-[12px] font-medium text-muted">
              How this payment was confirmed
            </h3>
            <p className="mt-1 text-[12px] text-ink">
              {intent
                ? 'Confirmed by the payment gateway; the references below are its own.'
                : 'Taken at the counter — no gateway checkout was involved.'}
            </p>
            <div className="mt-2 grid grid-cols-1 gap-1.5 text-[11.5px] sm:grid-cols-2">
              <div className="flex justify-between gap-3">
                <span className="text-muted">Order status</span>
                <span className="inline-flex">
                  <Badge label={sale.order_status ?? '—'} variant={sale.order_status} dot />
                </span>
              </div>
              <div className="flex justify-between gap-3">
                <span className="text-muted">Customer copy</span>
                <span className="text-ink">
                  {sale.receipt_emailed_at
                    ? `emailed ${formatDateTime(sale.receipt_emailed_at)}`
                    : 'not emailed'}
                </span>
              </div>
              <div className="flex justify-between gap-3">
                <span className="text-muted">PayMongo payment</span>
                <span className="font-mono text-ink">
                  {intent?.paymongo_payment_intent_id ?? '—'}
                </span>
              </div>
              {intent && (
                <>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted">Checkout session</span>
                    <span className="font-mono text-ink">{intent.checkout_session_id ?? '—'}</span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted">Gateway paid at</span>
                    <span className="font-mono text-ink">
                      {intent.paid_at ? formatDateTime(intent.paid_at) : '—'}
                    </span>
                  </div>
                </>
              )}
            </div>
            {isGcash && proof && (
              <div className="mt-3 border-t border-border pt-3">
                <div className="mb-2 flex items-center justify-between gap-3">
                  <h4 className="text-[12px] font-medium text-muted">GCash proof</h4>
                  <Tooltip
                    label={
                      PROOF_STATE_HINTS[proof.status] ??
                      'What the customer uploaded to show they paid.'
                    }
                  >
                    <Badge
                      label={`Proof ${proof.status ?? 'unknown'}`}
                      variant={PROOF_STATE_VARIANTS[proof.status] ?? 'none'}
                      dot
                    />
                  </Tooltip>
                </div>
                <div className="grid grid-cols-1 gap-1.5 text-[11.5px] sm:grid-cols-2">
                  <div className="flex justify-between gap-3">
                    <span className="text-muted">Reference</span>
                    <span className="font-mono text-ink">{gcashReference || '—'}</span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted">Order code</span>
                    <span className="font-mono text-ink">{code || '—'}</span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted">Sender</span>
                    <span className="text-ink">{proof.sender_name || '—'}</span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted">Amount sent</span>
                    <span
                      className={`font-mono ${amountMismatch ? 'font-semibold text-error' : 'text-ink'}`}
                    >
                      {amountSent == null ? '—' : formatCurrency(amountSent)}
                    </span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted">Attempt</span>
                    <span className="text-ink">
                      {proof.attempt_no ?? '—'} · received{' '}
                      {proof.submitted_at ? formatDateTime(proof.submitted_at) : '—'}
                    </span>
                  </div>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted">Receipt time (claimed)</span>
                    <span className="text-ink">
                      {proof.paid_at
                        ? formatDateTime(proof.paid_at)
                        : 'Not readable on the receipt'}
                    </span>
                  </div>
                </div>
                {amountMismatch && (
                  <p className="mt-2 text-[11.5px] font-medium text-error">
                    The proof says {formatCurrency(amountSent)} but the order is{' '}
                    {formatCurrency(sale.amount)}.
                  </p>
                )}
                {proof.status === 'rejected' && proof.rejection_reason && (
                  <p className="mt-2 text-[11.5px] text-error">
                    Rejected: {proof.rejection_reason}
                  </p>
                )}
                {proof.screenshot_url && (
                  <ProofScreenshot
                    path={proof.screenshot_url}
                    reference={gcashReference}
                    orderCode={code}
                  />
                )}
              </div>
            )}

            <div className="mt-3 border-t border-border pt-3">
              <h4 className="mb-2 text-[12px] font-medium text-muted">
                Webhook events ({sale.events_count})
              </h4>
              <EventTimeline events={sale.events} />
            </div>
          </div>
        </div>
      )}
    </Modal>
  )
}
