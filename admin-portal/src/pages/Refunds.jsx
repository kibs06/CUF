import { useState } from 'react'
import { Image as ImageIcon, Loader2, RotateCcw, Send, Wallet, X } from 'lucide-react'
import { useMarkRefunded, useRefundOwed } from '../hooks/useRefunds.js'
import { proofSignedUrl } from '../hooks/useManualGcash.js'
import { formatCurrency, formatDateTime, shortId } from '../lib/constants'
import Badge from '../components/ui/Badge.jsx'

const BTN =
  'inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-card px-2.5 text-[12px] font-semibold text-secondary transition-colors hover:bg-canvas disabled:cursor-not-allowed disabled:opacity-50'
const BTN_SUCCESS =
  'inline-flex h-8 items-center gap-1.5 rounded-lg bg-[#4F6B35] px-2.5 text-[12px] font-semibold text-white transition-colors hover:bg-[#445C2D] disabled:cursor-not-allowed disabled:opacity-50'

const INPUT =
  'h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12px] text-ink outline-none transition-colors placeholder:text-muted/60 focus:border-primary focus:ring-2 focus:ring-primary/15'

/** One label/value pair, the way the other detail panels read. */
function Detail({ label, children, tone }) {
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
      <span className="text-[12px] text-muted">{label}</span>
      <span
        className={`text-[12.5px] font-medium tabular-nums ${
          tone === 'danger' ? 'text-error' : tone === 'ok' ? 'text-accent' : 'text-ink'
        }`}
      >
        {children}
      </span>
    </div>
  )
}

/**
 * Money the platform may owe a customer.
 *
 * It only exists because rejecting a proof is not a refund: the seller's
 * decision cancels the order, and the customer's transfer is already in the
 * platform account. Every row here is a transfer someone has to send by hand,
 * with the proof's reference beside it so it can be found in the GCash
 * statement rather than reconstructed from memory.
 */
export default function Refunds() {
  const [includeRefunded, setIncludeRefunded] = useState(false)
  const { data: rows = [], isLoading, error } = useRefundOwed(includeRefunded)
  const markRefunded = useMarkRefunded()

  const [busyId, setBusyId] = useState(null)
  const [message, setMessage] = useState(null)
  const [referenceById, setReferenceById] = useState({})
  const [notesById, setNotesById] = useState({})
  const [proofView, setProofView] = useState(null)

  const owed = rows.filter((row) => row.r_payment_status === 'refund_pending').length
  const done = rows.length - owed
  const totalOwed = rows
    .filter((row) => row.r_payment_status === 'refund_pending')
    .reduce((sum, row) => sum + Number(row.r_total ?? 0), 0)

  const openProof = async (row) => {
    setProofView({ key: row.r_order_id, path: row.r_screenshot_path, url: null, error: null })
    const url = await proofSignedUrl(row.r_screenshot_path)
    setProofView((prev) => {
      // A late response for a card the admin already closed must not reopen it.
      if (!prev || prev.key !== row.r_order_id) return prev
      return { ...prev, url, error: url ? null : 'The screenshot could not be signed.' }
    })
  }

  const submit = async (row) => {
    const reference = (referenceById[row.r_order_id] ?? '').trim()
    if (reference.length < 4) {
      setMessage({ tone: 'error', text: 'Type the GCash reference of the refund first.' })
      return
    }
    setBusyId(row.r_order_id)
    setMessage(null)
    try {
      await markRefunded.mutateAsync({
        orderId: row.r_order_id,
        reference,
        notes: notesById[row.r_order_id],
      })
      setMessage({
        tone: 'ok',
        text: `Refund recorded for order #${shortId(row.r_order_id)} — ref ${reference}.`,
      })
    } catch (err) {
      setMessage({ tone: 'error', text: err.message })
    } finally {
      setBusyId(null)
    }
  }

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

      <div className="rounded-xl border border-border bg-card">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3.5">
          <div className="flex flex-wrap items-center gap-2">
            <p className="text-[13px] font-semibold text-ink">Queue</p>
            {error ? (
              <Badge label={error.message ?? 'Could not load'} variant="failed" />
            ) : null}
          </div>
          <div className="flex flex-wrap items-center gap-1.5">
            <Badge label={`${owed} to send`} variant={owed ? 'pending' : 'approved'} />
            {owed ? <Badge label={formatCurrency(totalOwed)} variant="none" /> : null}
            {rows.length ? (
              <button
                type="button"
                className={BTN}
                onClick={() => setIncludeRefunded((v) => !v)}
                aria-pressed={includeRefunded}
              >
                <RotateCcw size={13} strokeWidth={1.7} aria-hidden="true" />
                {includeRefunded ? `Hide sent (${done})` : `Show sent (${done})`}
              </button>
            ) : null}
          </div>
        </div>

        {isLoading ? (
          <p className="px-4 py-6 text-[12px] text-muted">Loading…</p>
        ) : rows.length === 0 ? (
          <div className="flex flex-col items-center px-6 py-16 text-center">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-canvas">
              <Wallet size={18} strokeWidth={1.5} className="text-muted" aria-hidden="true" />
            </div>
            <p className="mt-3 text-[15px] font-semibold text-ink">Nothing owed</p>
            <p className="mt-1 max-w-sm text-[12.5px] leading-relaxed text-muted">
              A proof rejected three times cancels the order, but the customer&apos;s
              transfer stays in the platform account. Those orders appear here so
              the money can be sent back.
            </p>
          </div>
        ) : (
          <ul className="divide-y divide-border">
            {rows.map((row) => {
              const refunded = row.r_payment_status === 'refunded'
              return (
                <li key={row.r_order_id} className="px-4 py-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="font-mono text-[11px] text-muted">
                        #{shortId(row.r_order_id)} · {row.r_store_name}
                      </p>
                      <div className="mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-1">
                        <p className="font-mono text-[19px] font-semibold leading-none tabular-nums text-ink">
                          {formatCurrency(row.r_total)}
                        </p>
                        <p className="text-[12px] text-muted">
                          {row.r_customer_name ?? 'Customer'}
                          {row.r_cancelled_at
                            ? ` · cancelled ${formatDateTime(row.r_cancelled_at)}`
                            : ''}
                        </p>
                      </div>
                    </div>
                    <div className="flex flex-wrap items-center gap-1.5">
                      <Badge
                        label={refunded ? 'Refunded' : 'Refund due'}
                        variant={refunded ? 'approved' : 'pending'}
                      />
                      {row.r_order_code ? (
                        <Badge label={`code ${row.r_order_code}`} variant="none" />
                      ) : null}
                    </div>
                  </div>

                  <div className="mt-3 rounded-lg border border-border/70 bg-canvas/50 px-3.5 py-3">
                    {row.r_reference ? (
                      <div className="grid gap-x-6 gap-y-1 sm:grid-cols-2">
                        <Detail label="Reference">{row.r_reference}</Detail>
                        <Detail label="Sender">{row.r_sender || '—'}</Detail>
                        <Detail label="Amount sent">
                          {row.r_amount_paid != null
                            ? formatCurrency(row.r_amount_paid)
                            : '—'}
                        </Detail>
                        <Detail label="Attempt">
                          {row.r_attempt_no ?? '—'}
                          {row.r_proof_submitted_at
                            ? ` · received ${formatDateTime(row.r_proof_submitted_at)}`
                            : ''}
                        </Detail>
                        {row.r_rejection_reason ? (
                          <p className="text-[11.5px] text-error sm:col-span-2">
                            Rejected: {row.r_rejection_reason}
                          </p>
                        ) : null}
                        {row.r_refund_reference ? (
                          <Detail label="Refunded with" tone="ok">
                            {row.r_refund_reference}
                            {row.r_refunded_at
                              ? ` · ${formatDateTime(row.r_refunded_at)}`
                              : ''}
                          </Detail>
                        ) : null}
                      </div>
                    ) : (
                      <p className="text-[12px] text-muted">
                        No proof row on this order — the refund cannot be matched
                        to a reference.
                      </p>
                    )}
                  </div>

                  <div className="mt-3 flex flex-wrap items-start gap-2">
                    {row.r_screenshot_path ? (
                      <button
                        type="button"
                        className={BTN}
                        onClick={() => openProof(row)}
                      >
                        <ImageIcon size={13} strokeWidth={1.7} aria-hidden="true" />
                        Screenshot
                      </button>
                    ) : null}

                    {refunded ? null : (
                      <>
                        <input
                          className={`${INPUT} max-w-[220px]`}
                          placeholder="GCash ref of the refund"
                          value={referenceById[row.r_order_id] ?? ''}
                          onChange={(e) =>
                            setReferenceById((prev) => ({
                              ...prev,
                              [row.r_order_id]: e.target.value,
                            }))
                          }
                          aria-label="GCash reference of the refund"
                        />
                        <input
                          className={`${INPUT} max-w-[220px]`}
                          placeholder="Note (optional)"
                          value={notesById[row.r_order_id] ?? ''}
                          onChange={(e) =>
                            setNotesById((prev) => ({
                              ...prev,
                              [row.r_order_id]: e.target.value,
                            }))
                          }
                          aria-label="Refund note"
                        />
                        <button
                          type="button"
                          className={BTN_SUCCESS}
                          disabled={busyId === row.r_order_id}
                          onClick={() => submit(row)}
                        >
                          {busyId === row.r_order_id ? (
                            <Loader2 size={13} className="animate-spin" aria-hidden="true" />
                          ) : (
                            <Send size={13} strokeWidth={1.7} aria-hidden="true" />
                          )}
                          Mark refunded
                        </button>
                      </>
                    )}
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </div>

      {proofView ? (
        <div
          className="fixed inset-0 z-50 flex items-start justify-center bg-black/90 p-4"
          role="dialog"
          aria-modal="true"
          aria-label="Payment screenshot"
          onClick={() => setProofView(null)}
        >
          <div
            className="mt-6 flex max-h-full w-full max-w-2xl flex-col items-center gap-3"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex w-full items-center justify-between text-[12px] text-white/70">
              <span>Customer screenshot</span>
              <button
                type="button"
                className="rounded-lg p-1 hover:bg-white/10"
                onClick={() => setProofView(null)}
                aria-label="Close screenshot"
              >
                <X size={16} />
              </button>
            </div>
            {proofView.error ? (
              <p className="py-10 text-center text-[12px] text-white/80">{proofView.error}</p>
            ) : proofView.url ? (
              <img
                src={proofView.url}
                alt="Customer payment screenshot"
                className="max-h-[80vh] w-auto rounded-lg object-contain"
              />
            ) : (
              <Loader2 className="my-16 animate-spin text-white" size={22} />
            )}
          </div>
        </div>
      ) : null}
    </div>
  )
}
