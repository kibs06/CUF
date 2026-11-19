import { useState } from 'react'
import { Link } from 'react-router-dom'
import {
  Check,
  ChevronLeft,
  ChevronRight,
  Copy,
  Image as ImageIcon,
  Loader2,
  RotateCcw,
  Send,
  Wallet,
  X,
} from 'lucide-react'
import {
  returnProofSignedUrl,
  useMarkRefunded,
  useMarkReturnReplaced,
  useRefundOwed,
} from '../hooks/useRefunds.js'
import { proofSignedUrl } from '../hooks/useManualGcash.js'
import { formatCurrency, formatDateTime, shortId } from '../lib/constants'
import AnimatedNumber from '../components/ui/AnimatedNumber.jsx'
import Badge from '../components/ui/Badge.jsx'
import Tooltip from '../components/ui/Tooltip.jsx'

const BTN =
  'inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-card px-2.5 text-[12px] font-semibold text-secondary transition-colors hover:bg-canvas disabled:cursor-not-allowed disabled:opacity-50'
const BTN_SUCCESS =
  'inline-flex h-8 items-center gap-1.5 rounded-lg bg-[#4F6B35] px-2.5 text-[12px] font-semibold text-white transition-colors hover:bg-[#445C2D] disabled:cursor-not-allowed disabled:opacity-50'

const INPUT =
  'h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12px] text-ink outline-none transition-colors placeholder:text-muted/60 focus:border-primary focus:ring-2 focus:ring-primary/15'

/**
 * Label above value, so a row of these reads as a small facts table instead of
 * label/value pairs flung to opposite ends of a wide card.
 */
function Field({ label, children, tone, action }) {
  return (
    <div className="min-w-0">
      <p className="text-[10.5px] font-semibold uppercase tracking-[0.12em] text-muted">
        {label}
      </p>
      <div className="mt-0.5 flex min-w-0 items-center gap-1.5">
        <p
          className={`min-w-0 truncate text-[12.5px] font-medium ${
            tone === 'danger' ? 'text-error' : tone === 'ok' ? 'text-accent' : 'text-ink'
          }`}
          title={typeof children === 'string' ? children : undefined}
        >
          {children}
        </p>
        {action}
      </div>
    </div>
  )
}

/**
 * Copies a value the admin is about to paste into GCash or the order search.
 * Lives next to the value it copies, never in a toolbar, so there is no doubt
 * about what lands on the clipboard.
 */
function CopyValue({ value, label, onError }) {
  const [copied, setCopied] = useState(false)

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(value)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1600)
    } catch {
      onError?.('Could not copy — select the text and copy it manually.')
    }
  }

  return (
    <Tooltip label={label}>
      <button
        type="button"
        onClick={copy}
        aria-label={label}
        className="inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-md border border-border bg-card text-muted transition-colors hover:bg-canvas hover:text-ink"
      >
        {copied ? (
          <Check size={12} strokeWidth={2} aria-hidden="true" />
        ) : (
          <Copy size={12} strokeWidth={1.8} aria-hidden="true" />
        )}
      </button>
    </Tooltip>
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
  const markReturn = useMarkReturnReplaced()

  const [busyId, setBusyId] = useState(null)
  const [message, setMessage] = useState(null)
  const [referenceById, setReferenceById] = useState({})
  const [notesById, setNotesById] = useState({})
  const [proofView, setProofView] = useState(null)

  const owed = rows.filter((row) => row.r_payment_status === 'refund_pending').length
  const returns = rows.filter((row) => row.r_kind === 'return').length
  const done = rows.filter((row) => row.r_payment_status === 'refunded').length
  const totalOwed = rows
    .filter((row) => row.r_payment_status === 'refund_pending')
    .reduce((sum, row) => sum + Number(row.r_total ?? 0), 0)

  // Returns carry 1-4 photos in the private `return-proofs` bucket; a rejected
  // proof carries one screenshot in `payment-proofs`. Both open in the same
  // viewer, with arrows and thumbnails when there is more than one photo.
  const openProof = async (row) => {
    const isReturn = row.r_kind === 'return'
    const paths = isReturn
      ? row.r_proof_paths?.length
        ? row.r_proof_paths
        : [row.r_screenshot_path].filter(Boolean)
      : [row.r_screenshot_path].filter(Boolean)

    setProofView({
      key: row.r_order_id,
      isReturn,
      urls: [],
      index: 0,
      loading: paths.length > 0,
      error: paths.length ? null : 'There is no photo attached to this row.',
    })

    const urls = (
      await Promise.all(
        paths.map((path) => (isReturn ? returnProofSignedUrl(path) : proofSignedUrl(path))),
      )
    ).filter(Boolean)

    setProofView((prev) => {
      // A late response for a card the admin already closed must not reopen it.
      if (!prev || prev.key !== row.r_order_id) return prev
      if (!urls.length) {
        return {
          ...prev,
          loading: false,
          error: isReturn
            ? 'The photos could not be opened — the admin account has no read access to the private return-proofs bucket yet.'
            : 'The screenshot could not be signed.',
        }
      }
      return { ...prev, loading: false, urls, index: 0, error: null }
    })
  }

  const submit = async (row) => {
    const isReturn = row.r_kind === 'return'
    const reference = (referenceById[row.r_order_id] ?? '').trim()
    // A return ends in a replacement, so there is no transfer to reference;
    // only a real refund needs the GCash ref.
    if (!isReturn && reference.length < 4) {
      setMessage({ tone: 'error', text: 'Type the GCash reference of the refund first.' })
      return
    }
    setBusyId(row.r_order_id)
    setMessage(null)
    try {
      const notes = notesById[row.r_order_id]
      if (isReturn) await markReturn.mutateAsync({ orderId: row.r_order_id, notes })
      else await markRefunded.mutateAsync({ orderId: row.r_order_id, reference, notes })
      setMessage({
        tone: 'ok',
        text: isReturn
          ? `Replacement recorded for order #${shortId(row.r_order_id)}.`
          : `Refund recorded for order #${shortId(row.r_order_id)} — ref ${reference}.`,
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

      <section
        aria-label="Replacement and refund totals"
        className="grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-border bg-border lg:grid-cols-3"
      >
        <div className="bg-card p-4">
          <p className="text-[12px] font-medium text-muted">To send</p>
          <p className="tnum mt-1.5 font-mono text-[22px] font-semibold leading-none text-ink">
            <AnimatedNumber value={totalOwed} format={formatCurrency} />
          </p>
          <p className="mt-2 text-[12px] text-muted">
            {owed} refund{owed === 1 ? '' : 's'} awaiting transfer
          </p>
        </div>
        <div className="bg-card p-4">
          <p className="text-[12px] font-medium text-muted">Replacements due</p>
          <p className="tnum mt-1.5 font-mono text-[22px] font-semibold leading-none text-ink">
            <AnimatedNumber value={returns} format={(v) => Math.round(v).toLocaleString()} />
          </p>
          <p className="mt-2 text-[12px] text-muted">Customer requests to review</p>
        </div>
        <div className="col-span-2 bg-card p-4 lg:col-span-1">
          <p className="text-[12px] font-medium text-muted">Refunds sent</p>
          <p className="tnum mt-1.5 font-mono text-[22px] font-semibold leading-none text-ink">
            <AnimatedNumber value={done} format={(v) => Math.round(v).toLocaleString()} />
          </p>
          <p className="mt-2 text-[12px] text-muted">Logged with a GCash reference</p>
        </div>
      </section>

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
            {returns ? (
              <Badge
                label={`${returns} replacement${returns === 1 ? '' : 's'}`}
                variant="return_requested"
              />
            ) : null}
            {owed ? <Badge label={formatCurrency(totalOwed)} variant="none" /> : null}
            {done ? (
              <Tooltip label="Include refunds already marked sent in the list.">
                <button
                  type="button"
                  className={BTN}
                  onClick={() => setIncludeRefunded((v) => !v)}
                  aria-pressed={includeRefunded}
                >
                  <RotateCcw size={13} strokeWidth={1.7} aria-hidden="true" />
                  {includeRefunded ? `Hide sent (${done})` : `Show sent (${done})`}
                </button>
              </Tooltip>
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
            <p className="mt-1 max-w-md text-[12.5px] leading-relaxed text-muted">
              Replacement requests and refunds from rejected proofs both land here.
              A proof rejected three times cancels the order and leaves the
              customer&apos;s transfer in the platform account; a replacement request
              is an order the buyer sent back for the seller to make good with a new
              pair — never cash.
            </p>
          </div>
        ) : (
          <ul className="divide-y divide-border">
            {rows.map((row) => {
              const refunded = row.r_payment_status === 'refunded'
              const isReturn = row.r_kind === 'return'
              return (
                <li key={row.r_order_id} className="px-4 py-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-1.5 font-mono text-[11px] text-muted">
                        <span>#{shortId(row.r_order_id)}</span>
                        {row.r_order_code ? (
                          <>
                            <span aria-hidden="true">·</span>
                            <span>code {row.r_order_code}</span>
                            <CopyValue
                              value={row.r_order_code}
                              label="Copy the order code."
                              onError={(text) => setMessage({ tone: 'error', text })}
                            />
                          </>
                        ) : null}
                      </div>
                      <div className="mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-1">
                        <p className="tnum font-mono text-[20px] font-semibold leading-none text-ink">
                          {formatCurrency(row.r_total)}
                        </p>
                        <p className="text-[12px] text-muted">
                          {row.r_store_name ?? 'Store unavailable'} ·{' '}
                          {row.r_customer_name ?? 'Customer'}
                        </p>
                      </div>
                    </div>
                    <Badge
                      label={
                        isReturn ? 'Replacement due' : refunded ? 'Refunded' : 'Refund due'
                      }
                      variant={
                        isReturn ? 'return_requested' : refunded ? 'approved' : 'pending'
                      }
                    />
                  </div>

                  <div className="mt-3 grid gap-x-4 gap-y-3 rounded-lg border border-border/70 bg-canvas/50 px-3.5 py-3 sm:grid-cols-3">
                    {isReturn ? (
                      <>
                        <Field label="Reason">{row.r_return_reason ?? 'Not recorded'}</Field>
                        <Field label="Requested">
                          {row.r_requested_at ? formatDateTime(row.r_requested_at) : '—'}
                        </Field>
                        <Field label="Customer note">
                          {row.r_return_details ? `“${row.r_return_details}”` : 'None'}
                        </Field>
                        {row.r_decline_reason ? (
                          <p className="text-[11.5px] text-error sm:col-span-3">
                            Seller declined: {row.r_decline_reason}
                          </p>
                        ) : null}
                      </>
                    ) : (
                      <>
                        <Field
                          label="GCash reference"
                          action={
                            row.r_reference ? (
                              <CopyValue
                                value={row.r_reference}
                                label="Copy the GCash reference."
                                onError={(text) => setMessage({ tone: 'error', text })}
                              />
                            ) : null
                          }
                        >
                          {row.r_reference ?? 'Not recorded'}
                        </Field>
                        <Field label="Sender">{row.r_sender || '—'}</Field>
                        <Field label="Amount sent">
                          {row.r_amount_paid != null ? formatCurrency(row.r_amount_paid) : '—'}
                        </Field>
                        <Field label="Attempt">
                          {row.r_attempt_no ?? '—'}
                          {row.r_proof_submitted_at
                            ? ` · ${formatDateTime(row.r_proof_submitted_at)}`
                            : ''}
                        </Field>
                        <Field label={refunded ? 'Refunded' : 'Cancelled'}>
                          {refunded && row.r_refunded_at
                            ? formatDateTime(row.r_refunded_at)
                            : row.r_cancelled_at
                              ? formatDateTime(row.r_cancelled_at)
                              : '—'}
                        </Field>
                        <Field label="Refund reference" tone={refunded ? 'ok' : undefined}>
                          {row.r_refund_reference ?? 'Not sent yet'}
                        </Field>
                        {row.r_rejection_reason ? (
                          <p className="text-[11.5px] text-error sm:col-span-3">
                            Rejected: {row.r_rejection_reason}
                          </p>
                        ) : null}
                        {!row.r_reference ? (
                          <p className="text-[11.5px] text-muted sm:col-span-3">
                            No proof row on this order — the refund can&apos;t be matched to a
                            reference.
                          </p>
                        ) : null}
                      </>
                    )}
                  </div>

                  <div className="mt-3 flex flex-wrap items-center gap-2">
                    {row.r_screenshot_path || row.r_proof_paths?.length ? (
                      <Tooltip
                        label={
                          isReturn
                            ? 'See the photos the customer attached.'
                            : "See the customer's payment screenshot."
                        }
                      >
                        <button type="button" className={BTN} onClick={() => openProof(row)}>
                          <ImageIcon size={13} strokeWidth={1.7} aria-hidden="true" />
                          {isReturn
                            ? (row.r_proof_paths?.length ?? 0) > 1
                              ? `Photos (${row.r_proof_paths.length})`
                              : 'Photo'
                            : 'Screenshot'}
                        </button>
                      </Tooltip>
                    ) : null}

                    <Link
                      to={`/orders?order=${row.r_order_id}`}
                      className={BTN}
                      title="Open this order in Orders"
                    >
                      Open order
                    </Link>

                    {refunded ? (
                      <p className="text-[12px] text-muted">Money sent back to the customer.</p>
                    ) : (
                      <>
                        {isReturn ? (
                          <p className="basis-full text-[12px] text-muted">
                            Replacement only — returns are never paid back in cash. Mark it once
                            the new pair is handed over or shipped.
                          </p>
                        ) : (
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
                        )}
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
                        <Tooltip
                          label={
                            isReturn
                              ? 'Closes the return as a product replacement. No money moves.'
                              : 'Records that this money was sent back to the customer.'
                          }
                        >
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
                            {isReturn ? 'Mark replaced' : 'Mark refunded'}
                          </button>
                        </Tooltip>
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
          aria-label={proofView.isReturn ? 'Customer photos' : 'Payment screenshot'}
          onClick={() => setProofView(null)}
        >
          <div
            className="mt-6 flex max-h-full w-full max-w-2xl flex-col items-center gap-3"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex w-full items-center justify-between text-[12px] text-white/70">
              <span>
                {proofView.isReturn ? 'Customer photos' : 'Customer screenshot'}
                {proofView.urls.length > 1
                  ? ` · ${proofView.index + 1} of ${proofView.urls.length}`
                  : ''}
              </span>
              <Tooltip label="Close the photo viewer.">
              <button
                type="button"
                className="rounded-lg p-1 hover:bg-white/10"
                onClick={() => setProofView(null)}
                aria-label="Close photos"
              >
                <X size={16} />
              </button>
              </Tooltip>
            </div>
            {proofView.error ? (
              <p className="max-w-md py-10 text-center text-[12px] leading-relaxed text-white/80">
                {proofView.error}
              </p>
            ) : proofView.loading ? (
              <Loader2 className="my-16 animate-spin text-white" size={22} />
            ) : (
              <>
                <div className="flex w-full items-center gap-2">
                  {proofView.urls.length > 1 ? (
                    <button
                      type="button"
                      className="rounded-lg p-1 text-white/80 hover:bg-white/10"
                      onClick={() =>
                        setProofView((prev) =>
                          prev
                            ? {
                                ...prev,
                                index: (prev.index - 1 + prev.urls.length) % prev.urls.length,
                              }
                            : prev,
                        )
                      }
                      aria-label="Previous photo"
                    >
                      <ChevronLeft size={22} />
                    </button>
                  ) : null}
                  <img
                    src={proofView.urls[proofView.index]}
                    alt={proofView.isReturn ? 'Customer return photo' : 'Customer payment screenshot'}
                    className="max-h-[76vh] w-auto min-w-0 flex-1 rounded-lg object-contain"
                  />
                  {proofView.urls.length > 1 ? (
                    <button
                      type="button"
                      className="rounded-lg p-1 text-white/80 hover:bg-white/10"
                      onClick={() =>
                        setProofView((prev) =>
                          prev ? { ...prev, index: (prev.index + 1) % prev.urls.length } : prev,
                        )
                      }
                      aria-label="Next photo"
                    >
                      <ChevronRight size={22} />
                    </button>
                  ) : null}
                </div>
                {proofView.urls.length > 1 ? (
                  <div className="flex items-center gap-2">
                    {proofView.urls.map((url, i) => (
                      <button
                        key={url}
                        type="button"
                        onClick={() => setProofView((prev) => (prev ? { ...prev, index: i } : prev))}
                        aria-label={`Show photo ${i + 1}`}
                        aria-pressed={i === proofView.index}
                        className={`h-12 w-12 overflow-hidden rounded-md border ${
                          i === proofView.index ? 'border-white' : 'border-white/25'
                        }`}
                      >
                        <img src={url} alt="" className="h-full w-full object-cover" />
                      </button>
                    ))}
                  </div>
                ) : null}
              </>
            )}
          </div>
        </div>
      ) : null}
    </div>
  )
}
