import { useState } from 'react'
import {
  AlertTriangle,
  BadgeCheck,
  CheckCircle2,
  Image as ImageIcon,
  ShieldCheck,
  XCircle,
} from 'lucide-react'
import {
  proofSignedUrl,
  useAdminVerifyPayment,
  useClearPaymentFlag,
  useFlagPayment,
  useManualPayments,
  useReconcileOrder,
} from '../hooks/useManualGcash.js'
import { formatCurrency, formatDateTime, shortId } from '../lib/constants'
import Badge from '../components/ui/Badge.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'

const STATUS_LABEL = {
  payment_under_review: 'Awaiting store review',
  pending: 'Verified — pending',
  placed: 'Verified — placed',
  preparing: 'Verified — preparing',
}

const STATUS_VARIANT = {
  payment_under_review: 'under_review',
  pending: 'pending',
  placed: 'placed',
  preparing: 'preparing',
}

// Same control language as Orders / Users: 8–9px-high rounded-lg pills, white
// with a hairline for secondary actions, solid secondary for the main one.
const BTN =
  'inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-white px-2.5 text-[12px] font-semibold text-secondary transition-colors hover:bg-canvas disabled:cursor-not-allowed disabled:opacity-50'
const BTN_PRIMARY =
  'inline-flex h-8 items-center gap-1.5 rounded-lg bg-secondary px-2.5 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep disabled:cursor-not-allowed disabled:opacity-50'
const BTN_SUCCESS =
  'inline-flex h-8 items-center gap-1.5 rounded-lg bg-[#4F6B35] px-2.5 text-[12px] font-semibold text-white transition-colors hover:bg-[#445C2D] disabled:cursor-not-allowed disabled:opacity-50'
const BTN_DANGER =
  'inline-flex h-8 items-center gap-1.5 rounded-lg border border-error/35 bg-white px-2.5 text-[12px] font-semibold text-error transition-colors hover:bg-errorSoft disabled:cursor-not-allowed disabled:opacity-50'

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

export default function PaymentVerification() {
  const { data: rows = [], isLoading, error } = useManualPayments()
  const flag = useFlagPayment()
  const clearFlag = useClearPaymentFlag()
  const verify = useAdminVerifyPayment()
  const reconcile = useReconcileOrder()
  const [busyId, setBusyId] = useState(null)
  const [message, setMessage] = useState(null)

  const run = async (id, fn) => {
    setBusyId(id)
    setMessage(null)
    try {
      await fn()
      setMessage({ tone: 'ok', text: 'Done.' })
    } catch (err) {
      setMessage({ tone: 'error', text: err.message })
    } finally {
      setBusyId(null)
    }
  }

  const openProof = async (path) => {
    const url = await proofSignedUrl(path)
    if (url) window.open(url, '_blank', 'noopener,noreferrer')
    else setMessage({ tone: 'error', text: 'Could not open the screenshot.' })
  }

  const onFlag = (row) => {
    const reason = window.prompt('Why is this payment flagged?', 'Not found in the GCash statement')
    if (!reason) return
    run(row.id, () => flag.mutateAsync({ p_order_id: row.id, p_reason: reason }))
  }

  const waiting = rows.filter((row) => row.status === 'payment_under_review').length
  const missingProof = rows.filter((row) => !row.proof).length
  const unreconciled = rows.filter(
    (row) => row.payment_status === 'paid' && !row.funds_reconciled_at,
  ).length

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
      {error ? (
        <div className="rounded-xl border border-error/25 bg-errorSoft px-4 py-3 text-[12px] text-error">
          {error.message}
        </div>
      ) : null}

      <section className="overflow-hidden rounded-xl border border-border bg-white">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3.5">
          <div>
            <h2 className="text-[15px] font-bold text-ink">Proofs and money</h2>
            <p className="mt-0.5 text-[12px] text-muted">
              {rows.length === 0
                ? 'Every manual-GCash order lands here.'
                : `${rows.length} order${rows.length === 1 ? '' : 's'} · reference, sender and amount come from the customer's submission`}
            </p>
          </div>
          {rows.length ? (
            <div className="flex flex-wrap items-center gap-1.5">
              <Badge label={`${waiting} awaiting store`} variant="pending" />
              {missingProof ? <Badge label={`${missingProof} without proof`} variant="none" /> : null}
              <Badge
                label={`${unreconciled} unreconciled`}
                variant={unreconciled ? 'failed' : 'approved'}
              />
            </div>
          ) : null}
        </div>

        {isLoading ? (
          <p className="px-4 py-6 text-[12px] text-muted">Loading…</p>
        ) : rows.length === 0 ? (
          <div className="px-4 py-4">
            <EmptyState
              title="Nothing to verify"
              description="New GCash proofs land here the moment a customer submits one."
            />
          </div>
        ) : (
          <ul className="divide-y divide-border">
            {rows.map((row) => {
              const proof = row.proof
              const amountMatches =
                proof?.amount_paid != null &&
                Math.abs(Number(proof.amount_paid) - Number(row.total_amount)) < 0.01
              // No proof row does NOT always mean the customer skipped it:
              //   • gatewayPaid   — PayMongo confirmed it (gcash_transaction_id
              //     is pay_xxx); a screenshot never existed for this flow.
              //   • legacyPaid    — confirmed before the proof flow, so the
              //     money landed but no receipt was recorded.
              //   • reviewWithoutProof — under review, yet nothing to review:
              //     the one case that needs an admin's attention.
              const gatewayPaid = !proof && !!row.gcash_transaction_id
              const legacyPaid =
                !proof && !gatewayPaid && !!row.payment_verified_at
              const reviewWithoutProof =
                !proof &&
                !gatewayPaid &&
                !legacyPaid &&
                row.status === 'payment_under_review'
              const proofNote = gatewayPaid
                ? `Confirmed by the payment gateway${row.payment_verified_at ? ` on ${formatDateTime(row.payment_verified_at)}` : ''}. Gateway orders carry no proof screenshot — the reference is on the payment intent, not in this queue.`
                : legacyPaid
                  ? `Marked paid${row.payment_verified_at ? ` on ${formatDateTime(row.payment_verified_at)}` : ''}, before the manual proof flow existed — the money was accepted but no receipt was recorded.`
                  : reviewWithoutProof
                    ? 'Under review, but no proof is readable for this order — the customer may have submitted one that is not visible here. Do not verify until you can see the reference and the receipt.'
                    : 'No reference or receipt has been submitted yet. The order code above is what ties the transfer to this order if it arrives.'

              return (
                <li key={row.id} className="px-4 py-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="font-mono text-[11px] text-muted">
                        #{shortId(row.id)} · {row.store_name}
                      </p>
                      <div className="mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-1">
                        <p className="font-mono text-[19px] font-semibold leading-none tabular-nums text-ink">
                          {formatCurrency(row.total_amount)}
                        </p>
                        <p className="text-[12px] text-muted">
                          {row.customer_name} · {formatDateTime(row.created_at)}
                        </p>
                      </div>
                    </div>

                    <div className="flex flex-wrap items-center gap-1.5">
                      <Badge
                        label={STATUS_LABEL[row.status] ?? row.status}
                        variant={STATUS_VARIANT[row.status] ?? 'none'}
                      />
                      {gatewayPaid ? <Badge label="Paid via gateway" variant="approved" /> : null}
                      {legacyPaid ? <Badge label="Confirmed earlier" variant="approved" /> : null}
                      {!proof && !gatewayPaid && !legacyPaid ? (
                        <Badge label="No proof" variant="pending" />
                      ) : null}
                      {proof && !amountMatches ? (
                        <Badge label="Amount mismatch" variant="failed" />
                      ) : null}
                      {row.payment_flagged ? <Badge label="Flagged" variant="failed" /> : null}
                      {row.funds_reconciled_at ? (
                        <Badge label="Funds seen" variant="approved" />
                      ) : null}
                    </div>
                  </div>

                  <div className="mt-3 grid gap-3 lg:grid-cols-[minmax(0,1fr)_auto]">
                    <div className="rounded-lg border border-border/70 bg-canvas/50 px-3.5 py-3">
                      {proof ? (
                        <div className="grid gap-x-6 gap-y-1 sm:grid-cols-2">
                          <Detail label="Reference">{proof.reference_number}</Detail>
                          <Detail label="Sender">{proof.sender_name || '—'}</Detail>
                          <Detail label="Amount sent" tone={amountMatches ? 'ok' : 'danger'}>
                            {proof.amount_paid != null
                              ? formatCurrency(proof.amount_paid)
                              : '—'}
                          </Detail>
                          <Detail label="Order code">{row.order_code ?? '—'}</Detail>
                          <Detail label="Attempt">
                            {proof.attempt_no} · received {formatDateTime(proof.submitted_at)}
                          </Detail>
                          <Detail label="Receipt time (claimed)">
                            {proof.paid_at
                              ? formatDateTime(proof.paid_at)
                              : 'Not readable on the receipt'}
                          </Detail>
                          <Detail label="Proof state">{proof.status}</Detail>
                          {proof.status === 'rejected' && proof.rejection_reason ? (
                            <p className="text-[11.5px] text-error sm:col-span-2">
                              Rejected: {proof.rejection_reason}
                            </p>
                          ) : null}
                        </div>
                      ) : (
                        <div className="grid gap-2">
                          <div className="grid gap-x-6 gap-y-1 sm:grid-cols-2">
                            <Detail label="Order code">{row.order_code ?? '—'}</Detail>
                            <Detail label="Order status">
                              {STATUS_LABEL[row.status] ?? row.status}
                            </Detail>
                            {row.gcash_reference_number ? (
                              <Detail label="Reference on order">
                                {row.gcash_reference_number}
                              </Detail>
                            ) : null}
                          </div>
                          <div className="flex items-start gap-2">
                            {gatewayPaid || legacyPaid ? (
                              <ShieldCheck
                                size={13}
                                strokeWidth={1.8}
                                className="mt-0.5 shrink-0 text-accent"
                              />
                            ) : (
                              <AlertTriangle
                                size={13}
                                strokeWidth={1.8}
                                className="mt-0.5 shrink-0 text-[#8A5D14]"
                              />
                            )}
                            <p className="text-[12px] leading-relaxed text-muted">{proofNote}</p>
                          </div>
                        </div>
                      )}
                    </div>

                    {/* Actions stay available with or without a proof: an order
                        can be flagged at any point in its life. */}
                    <div className="flex flex-wrap items-start gap-2 lg:max-w-[260px] lg:justify-end">
                      {proof ? (
                        <button
                          type="button"
                          className={BTN}
                          onClick={() => openProof(proof.screenshot_url)}
                        >
                          <ImageIcon size={13} strokeWidth={1.7} aria-hidden="true" />
                          Screenshot
                        </button>
                      ) : null}
                      {row.status === 'payment_under_review' ? (
                        <button
                          type="button"
                          className={BTN_PRIMARY}
                          disabled={busyId === row.id || !proof}
                          title={!proof ? 'A proof is required before verifying' : undefined}
                          onClick={() =>
                            run(row.id, () => verify.mutateAsync({ p_order_id: row.id }))
                          }
                        >
                          <BadgeCheck size={13} strokeWidth={1.7} aria-hidden="true" />
                          Verify for store
                        </button>
                      ) : null}
                      {row.payment_status === 'paid' && !row.funds_reconciled_at ? (
                        <button
                          type="button"
                          className={BTN_SUCCESS}
                          disabled={busyId === row.id || row.payment_flagged}
                          onClick={() =>
                            run(row.id, () => reconcile.mutateAsync({ p_order_id: row.id }))
                          }
                        >
                          <ShieldCheck size={13} strokeWidth={1.7} aria-hidden="true" />
                          Funds seen
                        </button>
                      ) : null}
                      {row.payment_flagged ? (
                        <button
                          type="button"
                          className={BTN}
                          disabled={busyId === row.id}
                          onClick={() =>
                            run(row.id, () => clearFlag.mutateAsync({ p_order_id: row.id }))
                          }
                        >
                          <CheckCircle2 size={13} strokeWidth={1.7} aria-hidden="true" />
                          Clear flag
                        </button>
                      ) : (
                        <button
                          type="button"
                          className={BTN_DANGER}
                          disabled={busyId === row.id}
                          onClick={() => onFlag(row)}
                        >
                          <XCircle size={13} strokeWidth={1.7} aria-hidden="true" />
                          Flag
                        </button>
                      )}
                    </div>
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </section>
    </div>
  )
}
