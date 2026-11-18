import { useState } from 'react'
import { Banknote, Check, CheckCircle2, Copy, RefreshCw, Upload } from 'lucide-react'
import {
  uploadPayoutReceipt,
  useGeneratePayouts,
  useMarkPayoutPaid,
  usePayables,
  usePayouts,
} from '../hooks/useManualGcash.js'
import { formatCurrency, formatDateTime } from '../lib/constants'
import Badge from '../components/ui/Badge.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'

const today = () => new Date().toISOString().slice(0, 10)

const BTN =
  'inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-white px-2.5 text-[12px] font-semibold text-secondary transition-colors hover:bg-canvas disabled:cursor-not-allowed disabled:opacity-50'
const BTN_PRIMARY =
  'inline-flex h-8 items-center gap-1.5 rounded-lg bg-secondary px-2.5 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep disabled:cursor-not-allowed disabled:opacity-50'
const BTN_SUCCESS =
  'inline-flex h-8 items-center gap-1.5 rounded-lg bg-[#4F6B35] px-2.5 text-[12px] font-semibold text-white transition-colors hover:bg-[#445C2D] disabled:cursor-not-allowed disabled:opacity-50'

const INPUT =
  'h-9 w-full rounded-lg border border-border bg-white px-2.5 text-[12px] text-ink outline-none transition-colors placeholder:text-muted/60 focus:border-primary focus:ring-2 focus:ring-primary/15'

/**
 * "GCash · 09171234567" — the destination the admin actually types into the
 * GCash/bank app. Falls back through what is on file, and says so plainly when
 * nothing is, instead of showing an empty block that looks like a zero.
 */
function destination(payout) {
  const details = String(payout?.payout_details ?? '').trim()
  const method = String(payout?.payout_method ?? '').trim()
  if (details) {
    return method === 'bank' ? `Bank · ${details}` : `GCash · ${details}`
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

  const copyDestination = async (payout) => {
    try {
      await navigator.clipboard.writeText(destination(payout))
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
        } created, ${result?.orders_added ?? 0} order(s) added.`,
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
      await markPaid.mutateAsync({ payoutId: openId, reference, receiptPath: path })
      setOpenId(null)
      setReference('')
      setReceipt(null)
      setMessage({ tone: 'ok', text: 'Payout marked paid.' })
    } catch (err) {
      setMessage({ tone: 'error', text: err.message })
    } finally {
      setSaving(false)
    }
  }

  const pendingTotal = payables.reduce((sum, row) => sum + Number(row.net_amount ?? 0), 0)
  const openPayout = payouts.find((row) => row.id === openId) ?? null

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

      <section className="overflow-hidden rounded-xl border border-border bg-white">
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
        </div>

        {loadingPayables ? (
          <p className="px-4 py-6 text-[12px] text-muted">Loading…</p>
        ) : payables.length === 0 ? (
          <div className="px-4 py-4">
            <EmptyState
              Icon={Banknote}
              title="Nothing awaiting payout"
              description="Verified orders appear here once you mark the funds as seen in Payment Verification."
            />
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

      <section className="overflow-hidden rounded-xl border border-border bg-white">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3.5">
          <div>
            <h2 className="text-[15px] font-bold text-ink">Payout batches</h2>
            <p className="mt-0.5 text-[12px] text-muted">
              One row per store per night. A batch is payable only after every order in it is
              reconciled.
            </p>
          </div>
          <Badge label={`${payouts.length} batches`} variant="none" />
        </div>

        {loadingPayouts ? (
          <p className="px-4 py-6 text-[12px] text-muted">Loading…</p>
        ) : payouts.length === 0 ? (
          <div className="px-4 py-4">
            <EmptyState
              Icon={Banknote}
              title="No payouts generated yet"
              description="Generate today's batch after the 23:59 Asia/Manila cutoff."
            />
          </div>
        ) : (
          <ul className="divide-y divide-border">
            {payouts.map((payout) => (
              <li
                key={payout.id}
                className="flex flex-wrap items-center gap-3 px-4 py-3 transition-colors hover:bg-canvas/60"
              >
                <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-canvas text-muted">
                  <Banknote size={15} strokeWidth={1.6} aria-hidden="true" />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[13px] font-semibold text-ink">
                    {payout.store_name}
                  </p>
                  <p className="font-mono text-[11.5px] text-muted">
                    {payout.period_date} · {payout.order_count} order(s) · net{' '}
                    {formatCurrency(payout.net_amount)}
                  </p>
                  <div className="mt-1 flex flex-wrap items-center gap-1.5">
                    <span className="text-[11.5px] text-muted">Send to</span>
                    <span
                      className={`text-[11.5px] font-medium ${
                        payout.payout_details ? 'text-ink' : 'text-error'
                      }`}
                    >
                      {destination(payout)}
                    </span>
                    <button
                      type="button"
                      onClick={() => copyDestination(payout)}
                      aria-label={`Copy the payout destination for ${payout.store_name}`}
                      title="Copy"
                      className="inline-flex h-5 w-5 items-center justify-center rounded text-muted transition-colors hover:bg-canvas hover:text-ink"
                    >
                      {copiedId === payout.id ? (
                        <Check size={12} strokeWidth={2} aria-hidden="true" />
                      ) : (
                        <Copy size={12} strokeWidth={1.8} aria-hidden="true" />
                      )}
                    </button>
                    {payout.seller_name ? (
                      <span className="text-[11.5px] text-muted">· {payout.seller_name}</span>
                    ) : null}
                  </div>
                  {payout.paid_at ? (
                    <p className="mt-0.5 text-[11.5px] text-muted">
                      paid {formatDateTime(payout.paid_at)}
                      {payout.paid_reference ? ` · ref ${payout.paid_reference}` : ''}
                    </p>
                  ) : null}
                </div>
                {payout.status !== 'paid' && payout.requested_at ? (
                  <Badge label="Requested" variant="pending" />
                ) : null}
                {payout.status === 'paid' ? (
                  <Badge label="Paid" variant="approved" dot />
                ) : (
                  <button type="button" className={BTN} onClick={() => setOpenId(payout.id)}>
                    <CheckCircle2 size={13} strokeWidth={1.7} aria-hidden="true" />
                    Mark paid
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      {openId ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="payout-transfer-title"
          className="fixed inset-0 z-50 flex items-end justify-center bg-secondary/45 p-4 backdrop-blur-sm sm:items-center"
        >
          <div className="w-full max-w-md rounded-xl border border-border bg-white p-5 shadow-[0_24px_60px_-24px_rgba(59,35,20,0.55)]">
            <h3 id="payout-transfer-title" className="text-[15px] font-bold text-ink">
              Record the transfer
            </h3>
            {openPayout ? (
              <p className="mt-0.5 text-[12px] text-muted">
                {openPayout.store_name} · {formatCurrency(openPayout.net_amount)} for{' '}
                {openPayout.period_date}
              </p>
            ) : null}

            {openPayout ? (
              <div className="mt-4 rounded-lg border border-border bg-canvas/60 px-3 py-2.5">
                <p className="text-[11px] font-semibold uppercase tracking-wider text-muted">
                  Send to
                </p>
                <div className="mt-1 flex flex-wrap items-center gap-2">
                  <span className="text-[13px] font-semibold text-ink">
                    {destination(openPayout)}
                  </span>
                  <button
                    type="button"
                    onClick={() => copyDestination(openPayout)}
                    className="inline-flex h-7 items-center gap-1 rounded-lg border border-border bg-white px-2 text-[11.5px] font-semibold text-secondary transition-colors hover:bg-canvas"
                  >
                    {copiedId === openPayout.id ? (
                      <Check size={12} strokeWidth={2} aria-hidden="true" />
                    ) : (
                      <Copy size={12} strokeWidth={1.8} aria-hidden="true" />
                    )}
                    {copiedId === openPayout.id ? 'Copied' : 'Copy'}
                  </button>
                </div>
                {openPayout.seller_name ? (
                  <p className="mt-1 text-[11.5px] text-muted">
                    {openPayout.seller_name}
                    {openPayout.seller_phone ? ` · ${openPayout.seller_phone}` : ''}
                  </p>
                ) : null}
                {openPayout.requested_at ? (
                  <p className="mt-1 text-[11.5px] text-muted">
                    Requested by the seller {formatDateTime(openPayout.requested_at)}
                  </p>
                ) : null}
              </div>
            ) : null}

            <div className="mt-4 space-y-3">
              <label className="block" htmlFor="payout-reference">
                <span className="mb-1 block text-[12px] font-medium text-muted">
                  GCash / bank reference
                </span>
                <input
                  id="payout-reference"
                  className={INPUT}
                  placeholder="e.g. 1029384756"
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                />
                <span className="mt-1 block text-[11.5px] text-muted">
                  At least 4 characters. This is what the store sees in its payout history.
                </span>
              </label>

              <label
                htmlFor="payout-receipt"
                className="flex cursor-pointer items-center gap-2 rounded-lg border border-dashed border-border bg-canvas px-3 py-2.5 transition-colors hover:border-primary/40"
              >
                <Upload size={13} strokeWidth={1.7} className="shrink-0 text-muted" />
                <input
                  id="payout-receipt"
                  type="file"
                  accept="image/*,application/pdf"
                  className="w-full text-[11.5px] text-muted file:mr-2 file:rounded-md file:border-0 file:bg-white file:px-2 file:py-1 file:text-[11px] file:font-semibold file:text-ink"
                  onChange={(e) => setReceipt(e.target.files?.[0] ?? null)}
                />
              </label>
            </div>

            <div className="mt-5 flex flex-wrap items-center justify-end gap-2">
              <button type="button" className={BTN} onClick={() => setOpenId(null)}>
                Cancel
              </button>
              <button
                type="button"
                className={BTN_SUCCESS}
                onClick={submitPaid}
                disabled={saving || reference.trim().length < 4}
              >
                <CheckCircle2 size={13} strokeWidth={1.7} aria-hidden="true" />
                {saving ? 'Saving…' : 'Mark paid'}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}
