import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  ArrowRight,
  Banknote,
  Check,
  CheckCircle2,
  Copy,
  ImageUp,
  Loader2,
  RefreshCw,
  Upload,
  X,
} from 'lucide-react'
import {
  uploadPayoutReceipt,
  useGeneratePayouts,
  useMarkPayoutPaid,
  usePayables,
  usePayouts,
} from '../hooks/useManualGcash.js'
import { formatCurrency, formatDateTime } from '../lib/constants'
import { SHOW_GCASH_VERIFICATION } from '../lib/features.js'
import { parseReceiptText } from '../lib/gcashReceipt.js'
import { recognizeReceiptText } from '../lib/ocrReceipt.js'
import AnimatedNumber from '../components/ui/AnimatedNumber.jsx'
import Badge from '../components/ui/Badge.jsx'
import Modal from '../components/ui/Modal.jsx'
import Tooltip from '../components/ui/Tooltip.jsx'

const today = () => new Date().toISOString().slice(0, 10)

const BTN =
  'inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-card px-2.5 text-[12px] font-semibold text-secondary transition-colors hover:bg-canvas disabled:cursor-not-allowed disabled:opacity-50'
const BTN_PRIMARY =
  'inline-flex h-8 items-center gap-1.5 rounded-lg bg-secondary px-2.5 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep disabled:cursor-not-allowed disabled:opacity-50'
const BTN_SUCCESS =
  'inline-flex h-8 items-center gap-1.5 rounded-lg bg-[#4F6B35] px-2.5 text-[12px] font-semibold text-white transition-colors hover:bg-[#445C2D] disabled:cursor-not-allowed disabled:opacity-50'

const INPUT =
  'h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12px] text-ink outline-none transition-colors placeholder:text-muted/60 focus:border-primary focus:ring-2 focus:ring-primary/15'

const MODAL_BTN_GHOST =
  'inline-flex h-9 items-center justify-center rounded-lg border border-border bg-card px-3.5 text-[12.5px] font-semibold text-secondary transition-colors hover:bg-canvas'
const MODAL_BTN_PRIMARY =
  'inline-flex h-9 items-center justify-center gap-1.5 rounded-lg bg-[#4F6B35] px-4 text-[12.5px] font-semibold text-white transition-colors hover:bg-[#445C2D] disabled:cursor-not-allowed disabled:opacity-50'

/**
 * The seller's payout account, split into what gets copied and what gets
 * checked. The seller app writes `payout_details` as "09171234567 · JUAN CRUZ"
 * (number first — see lib/utils/payout_account.dart), so the number is the part
 * that belongs in the GCash field and the name is the account holder it must
 * match. Values written before the seller had a field on file are a bare number
 * or free text (bank rail), and both still read correctly here.
 */
function payoutAccount(payout) {
  const details = String(payout?.payout_details ?? '').trim()
  const method = String(payout?.payout_method ?? '').trim().toLowerCase()
  if (!details) return { number: '', name: '', method }
  if (method === 'bank') return { number: details, name: '', method }
  const [rawNumber, ...rest] = details.split('·')
  return {
    number: rawNumber.trim(),
    name: rest.join('·').trim(),
    method,
  }
}

/**
 * "GCash · 09171234567" — the destination the admin actually types into the
 * GCash/bank app. Falls back through what is on file, and says so plainly when
 * nothing is, instead of showing an empty block that looks like a zero.
 */
function destination(payout) {
  const { number, method } = payoutAccount(payout)
  if (number) {
    return method === 'bank' ? `Bank · ${number}` : `GCash · ${number}`
  }
  const phone = String(payout?.seller_phone ?? '').trim()
  return phone || 'No payout details on file'
}

/** One label/value pair, the way the other detail panels read. */
function Detail({ label, children }) {
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
      <span className="text-[12px] text-muted">{label}</span>
      <span className="text-[12.5px] font-medium tabular-nums text-ink">{children}</span>
    </div>
  )
}

/**
 * What the seller actually received when the transfer was recorded. The payout
 * is already saved by the time this runs, so a failed or partial receipt is
 * reported beside the success — never as a failed payment.
 */
function receiptSummary(result) {
  if (result?.noticeError) {
    return `Payout marked paid — but the seller's receipt failed (${result.noticeError}).`
  }
  const notice = result?.notice
  if (!notice) return 'Payout marked paid.'
  if (notice.skipped === 'already_sent') {
    return 'Payout marked paid. The seller was already sent this receipt.'
  }

  const delivered = []
  const missing = []
  const email = notice.email ?? {}
  if (email.sent) delivered.push(`emailed to ${notice.to}`)
  else if (email.reason === 'no_email') missing.push('the seller has no email on file')
  else if (email.reason === 'email_not_configured') missing.push('the mailer is not configured')
  else if (email.reason === 'smtp_failed') missing.push('the mail server refused the email')
  else missing.push('no email receipt was sent')

  const push = notice.push ?? {}
  if (push.success_count > 0) {
    delivered.push(
      `pushed to ${push.success_count} device${push.success_count === 1 ? '' : 's'}`,
    )
  } else if (push.devices === 0) {
    missing.push('the seller has no registered device for a push')
  } else {
    missing.push('the push did not reach any device')
  }

  if (notice.in_app && notice.in_app.inserted === false) {
    missing.push(
      `the bell entry could not be saved (${notice.in_app.reason ?? 'unknown reason'})`,
    )
  } else if (notice.in_app?.inserted) {
    delivered.push('added to the seller\'s notifications')
  }

  const sent = delivered.length ? ` Seller notified: ${delivered.join(', ')}.` : ''
  const gaps = missing.length ? ` ${missing.join('; ')}.` : ''
  return `Payout marked paid.${sent}${gaps}`
}

export default function Payouts() {
  const { data: payables = [], isLoading: loadingPayables } = usePayables()
  const { data: payouts = [], isLoading: loadingPayouts } = usePayouts()
  const generate = useGeneratePayouts()
  const markPaid = useMarkPayoutPaid()

  const [openId, setOpenId] = useState(null)
  const [reference, setReference] = useState('')
  const [receipt, setReceipt] = useState(null)
  const [message, setMessage] = useState(null)
  const [saving, setSaving] = useState(false)
  const [copiedId, setCopiedId] = useState(null)

  // ── Reading the transfer screenshot ──────────────────────────────
  // The reference is the one thing that has to be typed correctly, and it is
  // printed on the receipt the admin already has. The dialog reads it with the
  // same extractor rules the customer app uses for its own proof of payment.
  const [reading, setReading] = useState(false)
  const [ocr, setOcr] = useState(null)
  const [previewUrl, setPreviewUrl] = useState(null)
  const [dragging, setDragging] = useState(false)
  const fileInputRef = useRef(null)

  // Object URLs are revoked on replace/unmount — a page left open for a shift
  // must not leak one blob per receipt.
  useEffect(() => () => {
    if (previewUrl) URL.revokeObjectURL(previewUrl)
  }, [previewUrl])

  const closeTransfer = () => {
    setOpenId(null)
    setReference('')
    setReceipt(null)
    setOcr(null)
    setReading(false)
    if (previewUrl) URL.revokeObjectURL(previewUrl)
    setPreviewUrl(null)
  }

  useEffect(() => {
    if (!openId) return undefined
    const onKeyDown = (event) => {
      if (event.key === 'Escape') closeTransfer()
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [openId, previewUrl])

  const chooseReceipt = async (file) => {
    setReceipt(file ?? null)
    setOcr(null)
    if (previewUrl) URL.revokeObjectURL(previewUrl)
    setPreviewUrl(file && file.type?.startsWith('image/') ? URL.createObjectURL(file) : null)
    if (!file) return

    if (!file.type?.startsWith('image/')) {
      setOcr({
        status: 'error',
        text: 'PDFs cannot be read here — attach a screenshot (PNG/JPG), or type the reference.',
      })
      return
    }

    setReading(true)
    try {
      const text = await recognizeReceiptText(file)
      const parsed = parseReceiptText(text)
      if (parsed.reference) {
        setReference(parsed.reference)
        setOcr({ status: 'ok', ...parsed })
      } else {
        setOcr({
          status: 'miss',
          text: 'No reference found in the screenshot — check it, or type the reference below.',
        })
      }
    } catch (err) {
      setOcr({
        status: 'error',
        text: `${err?.message ?? 'Could not read the screenshot'} — type the reference below.`,
      })
    } finally {
      setReading(false)
    }
  }

  const copyDestination = async (payout) => {
    try {
      // Only the number: the account name is for reading, and pasting it into
      // the GCash "send to" field would fail.
      const { number } = payoutAccount(payout)
      await navigator.clipboard.writeText(number || destination(payout))
      setCopiedId(payout.id)
      window.setTimeout(() => setCopiedId(null), 1600)
    } catch {
      setMessage({ tone: 'error', text: 'Could not copy — type the number manually.' })
    }
  }

  const onGenerate = async () => {
    setMessage(null)
    try {
      const result = await generate.mutateAsync(today())
      setMessage({
        tone: 'ok',
        text: `Payouts for ${result?.period_date ?? today()}: ${
          result?.payouts_created ?? 0
        } created, ${plural(result?.orders_added ?? 0, 'order')} added.`,
      })
    } catch (err) {
      setMessage({ tone: 'error', text: err.message })
    }
  }

  const submitPaid = async () => {
    setSaving(true)
    setMessage(null)
    try {
      let path = null
      if (receipt) path = await uploadPayoutReceipt(openId, receipt)
      const result = await markPaid.mutateAsync({
        payoutId: openId,
        reference,
        receiptPath: path,
      })
      closeTransfer()
      setMessage({ tone: 'ok', text: receiptSummary(result) })
    } catch (err) {
      setMessage({ tone: 'error', text: err.message })
    } finally {
      setSaving(false)
    }
  }

  const pendingTotal = payables.reduce((sum, row) => sum + Number(row.net_amount ?? 0), 0)
  const awaiting = payouts.filter((row) => row.status !== 'paid')
  const awaitingTotal = awaiting.reduce((sum, row) => sum + Number(row.net_amount ?? 0), 0)
  const paidBatches = payouts.filter((row) => row.status === 'paid')
  const openPayout = payouts.find((row) => row.id === openId) ?? null
  const plural = (count, word) => `${count} ${word}${count === 1 ? '' : 's'}`

  return (
    <div className="space-y-4">
      {message ? (
        <div
          role="status"
          className={`rounded-xl border px-4 py-3 text-[12px] ${
            message.tone === 'ok'
              ? 'border-accent/25 bg-accentSoft/70 text-ink'
              : 'border-error/25 bg-errorSoft text-error'
          }`}
        >
          {message.text}
        </div>
      ) : null}

      <section
        aria-label="Payout totals"
        className="grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-border bg-border lg:grid-cols-3"
      >
        <div className="bg-card p-4">
          <p className="text-[12px] font-medium text-muted">Owed to stores</p>
          <p className="tnum mt-1.5 font-mono text-[22px] font-semibold leading-none text-ink">
            <AnimatedNumber value={pendingTotal} format={formatCurrency} />
          </p>
          <p className="mt-2 text-[12px] text-muted">
            {plural(payables.length, 'store')} with unpaid orders
          </p>
        </div>
        <div className="bg-card p-4">
          <p className="text-[12px] font-medium text-muted">Awaiting transfer</p>
          <p className="tnum mt-1.5 font-mono text-[22px] font-semibold leading-none text-ink">
            <AnimatedNumber value={awaiting.length} format={(v) => Math.round(v).toLocaleString()} />
          </p>
          <p className="mt-2 text-[12px] text-muted">
            <AnimatedNumber value={awaitingTotal} format={formatCurrency} /> still to send
          </p>
        </div>
        <div className="col-span-2 bg-card p-4 lg:col-span-1">
          <p className="text-[12px] font-medium text-muted">Batches paid</p>
          <p className="tnum mt-1.5 font-mono text-[22px] font-semibold leading-none text-ink">
            <AnimatedNumber
              value={paidBatches.length}
              format={(v) => Math.round(v).toLocaleString()}
            />
          </p>
          <p className="mt-2 text-[12px] text-muted">Recorded with a reference</p>
        </div>
      </section>

      <section className="overflow-hidden rounded-xl border border-border bg-card">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3.5">
          <div>
            <h2 className="text-[15px] font-bold text-ink">Store balances</h2>
            <p className="mt-0.5 text-[12px] text-muted">
              Net of delivery and commission · {payables.length} store
              {payables.length === 1 ? '' : 's'} owed{' '}
              <span className="font-semibold tabular-nums text-ink">
                {formatCurrency(pendingTotal)}
              </span>
            </p>
          </div>
          <Tooltip label="Works out what each store is owed today and creates its payout.">
          <button
            type="button"
            className={BTN_PRIMARY}
            onClick={onGenerate}
            disabled={generate.isPending}
          >
            <RefreshCw
              size={13}
              strokeWidth={1.7}
              className={generate.isPending ? 'animate-spin' : ''}
              aria-hidden="true"
            />
            {generate.isPending ? 'Generating…' : 'Generate payouts for today'}
          </button>
          </Tooltip>
        </div>

        {loadingPayables ? (
          <p className="px-4 py-6 text-[12px] text-muted">Loading…</p>
        ) : payables.length === 0 ? (
          <div className="flex flex-wrap items-center gap-3 px-4 py-4">
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-canvas text-muted">
              <Banknote size={16} strokeWidth={1.6} aria-hidden="true" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[13px] font-semibold text-ink">Nothing awaiting payout</p>
              <p className="mt-0.5 text-[12px] text-muted">
                Paid orders show up here once their payment is confirmed.
                {SHOW_GCASH_VERIFICATION
                  ? ' Unconfirmed GCash proofs are reviewed in Payment Verification.'
                  : ''}
              </p>
            </div>
            {SHOW_GCASH_VERIFICATION ? (
              <Link
                to="/payment-verification"
                className="inline-flex h-8 items-center gap-1 rounded-lg border border-border bg-card px-2.5 text-[12px] font-semibold text-secondary transition-colors hover:bg-canvas"
              >
                Open verification <ArrowRight size={12} aria-hidden="true" />
              </Link>
            ) : null}
          </div>
        ) : (
          <ul className="divide-y divide-border">
            {payables.map((row) => (
              <li key={row.store_id} className="px-4 py-3.5">
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <p className="text-[13px] font-semibold text-ink">{row.store_name}</p>
                  <p className="font-mono text-[15px] tabular-nums text-ink">
                    {formatCurrency(row.net_amount)}
                  </p>
                </div>
                <div className="mt-1.5 grid gap-x-6 gap-y-1 sm:grid-cols-3">
                  <Detail label="Orders">{row.order_count}</Detail>
                  <Detail label="Gross">{formatCurrency(row.gross_amount)}</Detail>
                  <Detail label="Delivery">{formatCurrency(row.delivery_fees)}</Detail>
                </div>
                <p className="mt-1 text-[11.5px] text-muted">
                  commission {formatCurrency(row.platform_fee)} · net paid to store
                </p>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="overflow-hidden rounded-xl border border-border bg-card">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3.5">
          <div>
            <h2 className="text-[15px] font-bold text-ink">Payout batches</h2>
            <p className="mt-0.5 text-[12px] text-muted">
              One row per store per night. A batch is payable only after every order in it is
              reconciled.
            </p>
          </div>
          <Badge label={plural(payouts.length, 'batch')} variant="none" />
        </div>

        {loadingPayouts ? (
          <p className="px-4 py-6 text-[12px] text-muted">Loading…</p>
        ) : payouts.length === 0 ? (
          <div className="flex flex-wrap items-center gap-3 px-4 py-4">
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-canvas text-muted">
              <Banknote size={16} strokeWidth={1.6} aria-hidden="true" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[13px] font-semibold text-ink">No payouts generated yet</p>
              <p className="mt-0.5 text-[12px] text-muted">
                Use “Generate payouts for today” after the 23:59 Asia/Manila cutoff to create
                tonight’s batches.
              </p>
            </div>
          </div>
        ) : (
          <ul className="divide-y divide-border">
            {payouts.map((payout) => {
              const account = payoutAccount(payout)
              const paid = payout.status === 'paid'
              return (
                <li
                  key={payout.id}
                  className="flex flex-wrap items-start gap-3 px-4 py-3.5 transition-colors hover:bg-canvas/60 sm:flex-nowrap"
                >
                  <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-canvas text-muted">
                    <Banknote size={15} strokeWidth={1.6} aria-hidden="true" />
                  </span>

                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
                      <p className="truncate text-[13px] font-semibold text-ink">
                        {payout.store_name}
                      </p>
                      <p className="tnum text-[11.5px] text-muted">
                        {payout.period_date} · {payout.order_count} order
                        {payout.order_count === 1 ? '' : 's'}
                      </p>
                    </div>

                    <div className="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1">
                      <span className="text-[10.5px] font-semibold uppercase tracking-[0.12em] text-muted">
                        Send to
                      </span>
                      <span
                        className={`min-w-0 text-[12.5px] font-semibold ${
                          payout.payout_details ? 'text-ink' : 'text-error'
                        }`}
                      >
                        {destination(payout)}
                      </span>
                      {payout.payout_details ? (
                        <Tooltip label="Copy the number to send the money to.">
                          <button
                            type="button"
                            onClick={() => copyDestination(payout)}
                            aria-label={`Copy the payout destination for ${payout.store_name}`}
                            className="inline-flex h-6 w-6 items-center justify-center rounded-md border border-border bg-card text-muted transition-colors hover:bg-canvas hover:text-ink"
                          >
                            {copiedId === payout.id ? (
                              <Check size={12} strokeWidth={2} aria-hidden="true" />
                            ) : (
                              <Copy size={12} strokeWidth={1.8} aria-hidden="true" />
                            )}
                          </button>
                        </Tooltip>
                      ) : null}
                    </div>

                    {account.name || payout.seller_name ? (
                      <p className="mt-1 flex flex-wrap items-baseline gap-x-2 gap-y-0.5 text-[11.5px] text-muted">
                        {account.name ? (
                          <span>
                            <span className="font-semibold text-muted">Account holder</span>{' '}
                            {account.name}
                          </span>
                        ) : null}
                        {account.name && payout.seller_name ? (
                          <span aria-hidden="true">·</span>
                        ) : null}
                        {payout.seller_name ? (
                          <span>
                            <span className="font-semibold text-muted">Seller</span>{' '}
                            {payout.seller_name}
                          </span>
                        ) : null}
                      </p>
                    ) : null}

                    {paid && payout.paid_at ? (
                      <p className="mt-1 text-[11.5px] text-muted">
                        Paid {formatDateTime(payout.paid_at)}
                        {payout.paid_reference ? ` · ref ${payout.paid_reference}` : ''}
                      </p>
                    ) : payout.requested_at ? (
                      <p className="mt-1 text-[11.5px] text-muted">
                        Seller asked for this payout {formatDateTime(payout.requested_at)}
                      </p>
                    ) : null}
                  </div>

                  <div className="ml-auto flex shrink-0 flex-col items-end gap-1.5">
                    <p className="tnum font-mono text-[14px] font-semibold text-ink">
                      {formatCurrency(payout.net_amount)}
                    </p>
                    <div className="flex items-center gap-2">
                      {paid ? (
                        <Badge label="Paid" variant="approved" dot />
                      ) : payout.requested_at ? (
                        <Badge label="Requested" variant="pending" />
                      ) : (
                        <Badge label="Generated" variant="none" />
                      )}
                      {!paid ? (
                        <Tooltip label="Open this payout to record the transfer reference.">
                          <button type="button" className={BTN} onClick={() => setOpenId(payout.id)}>
                            <CheckCircle2 size={13} strokeWidth={1.7} aria-hidden="true" />
                            Mark paid
                          </button>
                        </Tooltip>
                      ) : null}
                    </div>
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </section>

      <Modal
        open={Boolean(openPayout)}
        onClose={closeTransfer}
        title="Record transfer"
        size="md"
        footer={
          <>
            <button type="button" className={MODAL_BTN_GHOST} onClick={closeTransfer}>
              Cancel
            </button>
            <button
              type="button"
              className={MODAL_BTN_PRIMARY}
              onClick={submitPaid}
              disabled={saving || reading || reference.trim().length < 4}
            >
              <CheckCircle2 size={14} strokeWidth={1.9} aria-hidden="true" />
              {saving ? 'Saving…' : 'Mark paid'}
            </button>
          </>
        }
      >
        {openPayout ? (
          <div className="space-y-6">
            <div className="flex items-start justify-between gap-4">
              <div className="min-w-0">
                <p className="text-[10.5px] font-semibold uppercase tracking-[0.16em] text-faint">
                  Payout
                </p>
                <p className="mt-1.5 font-mono text-[28px] font-semibold leading-none tracking-tight text-ink">
                  {formatCurrency(openPayout.net_amount)}
                </p>
                <p className="mt-2 truncate text-[12.5px] text-muted">
                  {openPayout.store_name}
                  {openPayout.period_date ? ` · ${openPayout.period_date}` : ''}
                </p>
              </div>
              <Badge
                label={openPayout.requested_at ? 'Requested' : 'Generated'}
                variant={openPayout.requested_at ? 'pending' : 'none'}
              />
            </div>

            <div className="rounded-xl border border-border bg-card px-3.5 py-3">
              <div className="flex items-center justify-between gap-3">
                <p className="text-[10.5px] font-semibold uppercase tracking-[0.14em] text-faint">
                  Send to
                </p>
                <button
                  type="button"
                  onClick={() => copyDestination(openPayout)}
                  className="inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-[11.5px] font-semibold text-primary transition-colors hover:bg-primary/5"
                >
                  {copiedId === openPayout.id ? (
                    <Check size={12} strokeWidth={2.2} aria-hidden="true" />
                  ) : (
                    <Copy size={12} strokeWidth={1.9} aria-hidden="true" />
                  )}
                  {copiedId === openPayout.id ? 'Copied' : 'Copy number'}
                </button>
              </div>
              <p className="mt-1 font-mono text-[15px] font-semibold tracking-wide text-ink">
                {payoutAccount(openPayout).number || destination(openPayout)}
              </p>
              <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11.5px] text-muted">
                {payoutAccount(openPayout).name || openPayout.seller_name ? (
                  <span>{payoutAccount(openPayout).name || openPayout.seller_name}</span>
                ) : null}
                {openPayout.seller_phone ? (
                  <span className="text-faint">· {openPayout.seller_phone}</span>
                ) : null}
              </div>
              {openPayout.requested_at ? (
                <p className="mt-1 text-[11.5px] text-faint">
                  The store asked for this on {formatDateTime(openPayout.requested_at)}
                </p>
              ) : null}
            </div>

            <div>
              <div className="flex items-baseline justify-between gap-3">
                <p className="text-[12.5px] font-semibold text-ink">Transfer screenshot</p>
                <span className="text-[11px] text-faint">The reference is read from it</span>
              </div>

              <input
                ref={fileInputRef}
                id="payout-receipt"
                type="file"
                accept="image/*"
                className="sr-only"
                onChange={(event) => chooseReceipt(event.target.files?.[0] ?? null)}
              />

              {receipt ? (
                <div
                  onDragOver={(event) => {
                    event.preventDefault()
                    setDragging(true)
                  }}
                  onDragLeave={() => setDragging(false)}
                  onDrop={(event) => {
                    event.preventDefault()
                    setDragging(false)
                    const dropped = event.dataTransfer?.files?.[0]
                    if (dropped) chooseReceipt(dropped)
                  }}
                  className={`mt-2 flex items-center gap-3 rounded-xl border bg-card p-2.5 transition-colors ${
                    dragging ? 'border-primary ring-2 ring-primary/15' : 'border-border'
                  }`}
                >
                  {previewUrl ? (
                    <img
                      src={previewUrl}
                      alt="Selected transfer screenshot"
                      className="h-16 w-16 shrink-0 rounded-lg border border-border object-cover"
                    />
                  ) : (
                    <span className="flex h-16 w-16 shrink-0 items-center justify-center rounded-lg bg-canvas text-muted">
                      <ImageUp size={18} strokeWidth={1.6} aria-hidden="true" />
                    </span>
                  )}

                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[12.5px] font-semibold text-ink">{receipt.name}</p>
                    <p className="mt-1 text-[11.5px] leading-snug">
                      {reading ? (
                        <span className="inline-flex items-center gap-1.5 text-muted">
                          <Loader2 size={12} className="animate-spin" aria-hidden="true" />
                          Reading the screenshot…
                        </span>
                      ) : ocr?.status === 'ok' ? (
                        <span className="inline-flex items-center gap-1.5 font-medium text-[#4F6B35]">
                          <CheckCircle2 size={12.5} strokeWidth={2.2} aria-hidden="true" />
                          Reference read: {ocr.displayGrouped}
                        </span>
                      ) : (
                        <span className="text-muted">
                          {ocr?.text ?? 'Ready to read the reference.'}
                        </span>
                      )}
                    </p>
                  </div>

                  <div className="flex shrink-0 items-center gap-1">
                    <Tooltip label="Replace this screenshot.">
                      <button
                        type="button"
                        aria-label="Replace screenshot"
                        onClick={() => fileInputRef.current?.click()}
                        className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-muted transition-colors hover:bg-canvas hover:text-ink"
                      >
                        <RefreshCw size={14} strokeWidth={1.8} aria-hidden="true" />
                      </button>
                    </Tooltip>
                    <Tooltip label="Remove this screenshot.">
                      <button
                        type="button"
                        aria-label="Remove screenshot"
                        onClick={() => chooseReceipt(null)}
                        className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-muted transition-colors hover:bg-errorSoft hover:text-error"
                      >
                        <X size={14} strokeWidth={1.8} aria-hidden="true" />
                      </button>
                    </Tooltip>
                  </div>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  onDragOver={(event) => {
                    event.preventDefault()
                    setDragging(true)
                  }}
                  onDragLeave={() => setDragging(false)}
                  onDrop={(event) => {
                    event.preventDefault()
                    setDragging(false)
                    const dropped = event.dataTransfer?.files?.[0]
                    if (dropped) chooseReceipt(dropped)
                  }}
                  className={`mt-2 flex w-full flex-col items-center gap-1.5 rounded-xl border border-dashed px-4 py-5 text-center transition-colors ${
                    dragging
                      ? 'border-primary bg-primary/5'
                      : 'border-border bg-canvas/70 hover:border-primary/40 hover:bg-canvas'
                  }`}
                >
                  <span className="flex h-10 w-10 items-center justify-center rounded-full bg-accentSoft text-[#4F6B35]">
                    <ImageUp size={17} strokeWidth={1.7} aria-hidden="true" />
                  </span>
                  <span className="mt-1 text-[12.5px] font-semibold text-ink">
                    Drop the GCash screenshot
                  </span>
                  <span className="text-[11.5px] text-muted">
                    or click to browse · PNG or JPG
                  </span>
                </button>
              )}
            </div>

            <div>
              <div className="flex items-baseline justify-between gap-3">
                <label htmlFor="payout-reference" className="text-[12.5px] font-semibold text-ink">
                  Reference number
                </label>
                {ocr?.status === 'ok' ? (
                  <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-[#4F6B35]">
                    <Check size={11} strokeWidth={2.4} aria-hidden="true" />
                    Auto-filled
                  </span>
                ) : null}
              </div>

              <div className="relative mt-2">
                <input
                  id="payout-reference"
                  className="h-11 w-full rounded-xl border border-border bg-card pl-3 pr-10 font-mono text-[14px] tracking-[0.06em] text-ink outline-none transition-colors placeholder:font-sans placeholder:tracking-normal placeholder:text-muted/60 focus:border-primary focus:ring-2 focus:ring-primary/15"
                  placeholder="e.g. 4043 676 687260"
                  inputMode="numeric"
                  autoComplete="off"
                  value={reference}
                  onChange={(event) => setReference(event.target.value)}
                />
                {ocr?.status === 'ok' ? (
                  <CheckCircle2
                    size={16}
                    strokeWidth={2.1}
                    aria-hidden="true"
                    className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-[#4F6B35]"
                  />
                ) : null}
              </div>
              <p className="mt-1.5 text-[11.5px] text-muted">
                At least 4 digits. This is what the store sees in its payout history.
              </p>
            </div>
          </div>
        ) : null}
      </Modal>
    </div>
  )
}
