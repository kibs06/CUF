import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  BadgeCheck,
  Check,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Copy,
  Image as ImageIcon,
  Loader2,
  RefreshCw,
  Search,
  SearchX,
  ShieldCheck,
  X,
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
import { useToast } from '../components/ui/Toast.jsx'
import Badge from '../components/ui/Badge.jsx'
import Tooltip from '../components/ui/Tooltip.jsx'
import DateRangePicker, {
  parseISODate,
  toISODate,
} from '../components/ui/DateRangePicker.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'

const PAGE_SIZE = 20

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

// Each queue is a predicate over a row, not a status string: an admin thinks
// in "what needs me", and three of these cut across statuses. `key` is what the
// "Show" select and the counts share.
const QUEUES = [
  { key: 'all', label: 'All orders' },
  { key: 'review', label: 'Awaiting store review' },
  { key: 'funds', label: 'Paid — funds not seen' },
  { key: 'flagged', label: 'Flagged' },
  { key: 'gap', label: 'No proof on file' },
  { key: 'verified', label: 'Verified / paid' },
]

const SORTS = [
  { key: 'newest', label: 'Newest first' },
  { key: 'oldest', label: 'Oldest first' },
  { key: 'amount_desc', label: 'Largest amount' },
  { key: 'amount_asc', label: 'Smallest amount' },
]

const inQueue = (row, queue) => {
  if (queue === 'review') return row.status === 'payment_under_review'
  if (queue === 'funds') {
    return row.payment_status === 'paid' && !row.funds_reconciled_at
  }
  if (queue === 'flagged') return Boolean(row.payment_flagged)
  if (queue === 'gap') return !row.proof
  if (queue === 'verified') return row.payment_status === 'paid'
  return true
}

// Same control language as Orders / Users / Refunds: 8–9px-high rounded-lg
// pills, white with a hairline for secondary actions, solid secondary for the
// main one. Focus rings come from the global `:where(a, button, [tabindex])`
// rule in index.css — do not add per-page ring classes here.
const BTN =
  'inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-card px-2.5 text-[12px] font-semibold text-secondary transition-colors hover:bg-canvas disabled:cursor-not-allowed disabled:opacity-50'
const BTN_PRIMARY =
  'inline-flex h-8 items-center gap-1.5 rounded-lg bg-secondary px-2.5 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep disabled:cursor-not-allowed disabled:opacity-50'
const BTN_SUCCESS =
  'inline-flex h-8 items-center gap-1.5 rounded-lg bg-[#4F6B35] px-2.5 text-[12px] font-semibold text-white transition-colors hover:bg-[#445C2D] disabled:cursor-not-allowed disabled:opacity-50'
const BTN_DANGER =
  'inline-flex h-8 items-center gap-1.5 rounded-lg border border-error/35 bg-card px-2.5 text-[12px] font-semibold text-error transition-colors hover:bg-errorSoft disabled:cursor-not-allowed disabled:opacity-50'
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
 * A reference or order code with its own copy button.
 *
 * These are the strings an admin carries into the GCash app, so typing them by
 * hand is the slowest, most error-prone step in verifying a payment.
 */
function CopyValue({ value, label }) {
  const { showToast } = useToast()
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    if (!copied) return
    const timer = setTimeout(() => setCopied(false), 1400)
    return () => clearTimeout(timer)
  }, [copied])

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(String(value))
      setCopied(true)
    } catch {
      showToast(`Could not copy the ${label.toLowerCase()} — select it manually.`, 'error')
    }
  }

  return (
    <span className="inline-flex items-center gap-1.5">
      <span className="font-mono tracking-wide">{value}</span>
      <button
        type="button"
        onClick={copy}
        aria-label={copied ? `${label} copied` : `Copy ${label}`}
        title={`Copy ${label}`}
        className="inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-md text-muted transition-colors hover:bg-canvas hover:text-ink"
      >
        {copied ? (
          <Check size={12} strokeWidth={2} aria-hidden="true" />
        ) : (
          <Copy size={12} strokeWidth={1.7} aria-hidden="true" />
        )}
      </button>
    </span>
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
  const [proofView, setProofView] = useState(null)

  const [search, setSearch] = useState('')
  const [queue, setQueue] = useState('all')
  const [sort, setSort] = useState('newest')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [amountMin, setAmountMin] = useState('')
  const [amountMax, setAmountMax] = useState('')
  const [page, setPage] = useState(1)
  const searchRef = useRef(null)

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

  // The receipt stays inside the queue: verifying means reading the reference
  // and the amount off the image while the row is still on screen, so a new tab
  // only splits the admin's attention. Escape (or the backdrop) closes it.
  //
  // The overlay opens on the click, before the signed URL exists. Signing is a
  // round trip to Storage, and waiting for it with nothing on screen reads as a
  // dead button.
  const openProof = (row) => {
    const view = {
      path: row.proof?.screenshot_url,
      url: null,
      status: 'loading',
      error: null,
      reference: row.proof?.reference_number,
      sender: row.proof?.sender_name,
      amount: row.total_amount,
      orderCode: row.order_code,
    }
    setProofView(view)
    loadProof(view)
  }

  // Signing and displaying fail separately — no read access to the file, or a
  // signed link that has gone stale — so the overlay reports either one itself
  // instead of dropping the reason into a banner behind it.
  const loadProof = async (view) => {
    const url = await proofSignedUrl(view.path)
    // An answer for a row the admin already closed or replaced is dropped.
    setProofView((current) => {
      if (current?.path !== view.path) return current
      return url
        ? { ...current, url, status: 'ready', error: null }
        : {
            ...current,
            status: 'error',
            error:
              "The screenshot couldn't be opened. It may have been removed from storage, or your account may not have access to it.",
          }
    })
  }

  const retryProof = () => {
    if (!proofView) return
    const retried = { ...proofView, status: 'loading', url: null, error: null }
    setProofView(retried)
    loadProof(retried)
  }

  const failProofImage = () =>
    setProofView((current) =>
      current && current.status === 'ready'
        ? {
            ...current,
            status: 'error',
            error:
              'The image came back empty. The signed link has probably expired — try again to fetch a fresh one.',
          }
        : current,
    )

  useEffect(() => {
    if (!proofView) return
    const onKey = (e) => {
      if (e.key === 'Escape') setProofView(null)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [proofView])

  // "/" jumps to search from anywhere on the page — the toolbar is the first
  // thing an admin reaches for, and this is one keystroke instead of a tab
  // crawl through every control above it.
  useEffect(() => {
    const onKey = (e) => {
      if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return
      const tag = document.activeElement?.tagName
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return
      e.preventDefault()
      searchRef.current?.focus()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const onFlag = (row) => {
    const reason = window.prompt('Why is this payment flagged?', 'Not found in the GCash statement')
    if (!reason) return
    run(row.id, () => flag.mutateAsync({ p_order_id: row.id, p_reason: reason }))
  }

  // ── counts ────────────────────────────────────────────────────────
  // Computed from every row, never from the filtered set: a chip that changes
  // as you filter cannot be used to decide where to go next.
  const counts = useMemo(
    () => ({
      all: rows.length,
      review: rows.filter((row) => inQueue(row, 'review')).length,
      funds: rows.filter((row) => inQueue(row, 'funds')).length,
      flagged: rows.filter((row) => inQueue(row, 'flagged')).length,
      gap: rows.filter((row) => inQueue(row, 'gap')).length,
      verified: rows.filter((row) => inQueue(row, 'verified')).length,
    }),
    [rows],
  )

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    const from = dateFrom ? new Date(`${dateFrom}T00:00:00`) : null
    const to = dateTo ? new Date(`${dateTo}T23:59:59`) : null
    const min = amountMin === '' ? null : Number(amountMin)
    const max = amountMax === '' ? null : Number(amountMax)

    const out = rows.filter((row) => {
      if (!inQueue(row, queue)) return false

      const created = row.created_at ? new Date(row.created_at) : null
      if (from && (!created || created < from)) return false
      if (to && (!created || created > to)) return false

      const amount = Number(row.total_amount)
      if (min != null && Number.isFinite(min) && amount < min) return false
      if (max != null && Number.isFinite(max) && amount > max) return false

      if (!q) return true
      // Everything a person might paste from GCash, an email or another screen.
      const haystack = [
        row.id,
        shortId(row.id),
        row.order_code,
        row.gcash_reference_number,
        row.gcash_transaction_id,
        row.customer_name,
        row.store_name,
        row.proof?.reference_number,
        row.proof?.sender_name,
        String(row.total_amount ?? ''),
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
      return haystack.includes(q)
    })

    const byDate = (row) => (row.created_at ? new Date(row.created_at).getTime() : 0)
    if (sort === 'oldest') out.sort((a, b) => byDate(a) - byDate(b))
    else if (sort === 'amount_desc') out.sort((a, b) => Number(b.total_amount) - Number(a.total_amount))
    else if (sort === 'amount_asc') out.sort((a, b) => Number(a.total_amount) - Number(b.total_amount))
    else out.sort((a, b) => byDate(b) - byDate(a))

    return out
  }, [rows, queue, search, sort, dateFrom, dateTo, amountMin, amountMax])

  const filtersActive = Boolean(
    search.trim() ||
      queue !== 'all' ||
      sort !== 'newest' ||
      dateFrom ||
      dateTo ||
      amountMin !== '' ||
      amountMax !== '',
  )

  const clearFilters = () => {
    setSearch('')
    setQueue('all')
    setSort('newest')
    setDateFrom('')
    setDateTo('')
    setAmountMin('')
    setAmountMax('')
    setPage(1)
  }

  // Any change to what is being shown returns to page 1: staying on page 4 of a
  // list that just became 2 pages long shows an empty screen that looks broken.
  useEffect(() => {
    setPage(1)
  }, [search, queue, sort, dateFrom, dateTo, amountMin, amountMax])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const safePage = Math.min(page, totalPages)
  const pageRows = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE)
  const rangeStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1
  const rangeEnd = Math.min(safePage * PAGE_SIZE, filtered.length)

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

      {/* ── Filters ──────────────────────────────────────────────── */}
      <section
        aria-label="Filter payments"
        className="rounded-xl border border-border bg-card p-3"
      >
        <div className="grid grid-cols-2 gap-2.5 xl:grid-cols-[minmax(280px,1.8fr)_210px_180px]">
          <label className="col-span-2 block xl:col-span-1">
            <span className="mb-1 block text-[12px] font-medium text-muted">Search</span>
            <span className="relative block">
              <Search
                size={14}
                strokeWidth={1.6}
                className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-muted"
                aria-hidden="true"
              />
              <Tooltip label="Searches reference, order code, customer, store and amount.">
                <input
                  ref={searchRef}
                  type="search"
                  placeholder="Reference, order code, customer, store, amount…"
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === 'Escape') setSearch('')
                  }}
                  className="h-9 w-full rounded-lg border border-border bg-card pl-8 pr-9 text-[12.5px] text-ink outline-none transition-colors placeholder:text-muted/70 focus:border-primary focus:ring-2 focus:ring-primary/15"
                />
              </Tooltip>
              {search ? (
                <Tooltip label="Clear the search.">
                <button
                  type="button"
                  onClick={() => setSearch('')}
                  aria-label="Clear search"
                  className="absolute right-1.5 top-1/2 inline-flex h-6 w-6 -translate-y-1/2 items-center justify-center rounded-md text-muted transition-colors hover:bg-canvas hover:text-ink"
                >
                  <X size={13} />
                </button>
                </Tooltip>
              ) : null}
            </span>
          </label>

          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">Show</span>
            <Tooltip label="Choose which proofs to list here.">
            <select
              value={queue}
              onChange={(event) => {
                setQueue(event.target.value)
                setPage(1)
              }}
              className={INPUT}
            >
              {QUEUES.map((item) => (
                <option key={item.key} value={item.key}>
                  {item.label} ({counts[item.key]})
                </option>
              ))}
            </select>
            </Tooltip>
          </label>

          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">Sort</span>
            <Tooltip label="Choose the order of the list.">
            <select
              value={sort}
              onChange={(event) => setSort(event.target.value)}
              className={INPUT}
            >
              {SORTS.map((item) => (
                <option key={item.key} value={item.key}>
                  {item.label}
                </option>
              ))}
            </select>
            </Tooltip>
          </label>
        </div>

        <div className="mt-2.5 grid grid-cols-2 gap-2.5 xl:grid-cols-[240px_150px_150px]">
          <div className="col-span-2 block xl:col-span-1">
            <span className="mb-1 block text-[12px] font-medium text-muted">Date</span>
            <DateRangePicker
              align="left"
              from={parseISODate(dateFrom)}
              to={parseISODate(dateTo)}
              onChange={(nextFrom, nextTo) => {
                setDateFrom(toISODate(nextFrom))
                setDateTo(toISODate(nextTo))
                setPage(1)
              }}
            />
          </div>
          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">Min ₱</span>
            <Tooltip label="Only payments at or above this amount.">
              <input
                type="number"
                min="0"
                step="0.01"
                inputMode="decimal"
                placeholder="0"
                value={amountMin}
                onChange={(event) => setAmountMin(event.target.value)}
                className={`${INPUT} font-mono tabular-nums`}
              />
            </Tooltip>
          </label>
          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">Max ₱</span>
            <Tooltip label="Only payments at or below this amount.">
              <input
                type="number"
                min="0"
                step="0.01"
                inputMode="decimal"
                placeholder="Any"
                value={amountMax}
                onChange={(event) => setAmountMax(event.target.value)}
                className={`${INPUT} font-mono tabular-nums`}
              />
            </Tooltip>
          </label>
        </div>

        <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
          <p className="text-[11.5px] text-muted" aria-live="polite">
            <span className="font-semibold text-ink">{filtered.length.toLocaleString('en-PH')}</span>{' '}
            matching of {rows.length.toLocaleString('en-PH')} order
            {rows.length === 1 ? '' : 's'}
          </p>
          {filtersActive ? (
            <Tooltip label="Clear the search, queue, dates and amounts.">
              <button
                type="button"
                onClick={clearFilters}
                className="inline-flex h-8 items-center gap-1 rounded-lg px-2.5 text-[12px] font-semibold text-muted transition-colors hover:bg-canvas hover:text-ink"
              >
                <X size={13} aria-hidden="true" />
                Clear filters
              </button>
            </Tooltip>
          ) : null}
        </div>
      </section>

      {/* ── Queue ────────────────────────────────────────────────── */}
      <section className="overflow-hidden rounded-xl border border-border bg-card">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3.5">
          <div>
            <h2 className="text-[15px] font-bold text-ink">Proofs and money</h2>
            <p className="mt-0.5 text-[12px] text-muted">
              {rows.length === 0
                ? 'Every manual-GCash order lands here.'
                : filtered.length === 0
                  ? 'No order matches the current filters.'
                  : `${filtered.length} order${filtered.length === 1 ? '' : 's'} · reference, sender and amount come from the customer's submission`}
            </p>
          </div>
          {rows.length ? (
            <div className="flex flex-wrap items-center gap-1.5">
              <Badge label={`${counts.review} awaiting store`} variant="pending" />
              {counts.gap ? (
                <Badge label={`${counts.gap} without proof`} variant="none" />
              ) : null}
              <Badge
                label={`${counts.funds} unreconciled`}
                variant={counts.funds ? 'failed' : 'approved'}
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
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center border-t border-border px-6 py-16 text-center">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-canvas">
              <SearchX size={18} strokeWidth={1.5} className="text-muted" aria-hidden="true" />
            </div>
            <p className="mt-3 text-[15px] font-semibold text-ink">No payments match these filters</p>
            <p className="mt-1 max-w-sm text-[12.5px] leading-relaxed text-muted">
              Try a shorter reference, another queue, or widen the date and amount range.
            </p>
            <button
              type="button"
              onClick={clearFilters}
              className="mt-3 inline-flex h-9 items-center rounded-lg bg-secondary px-3.5 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep"
            >
              Clear filters
            </button>
          </div>
        ) : (
          <ul className="divide-y divide-border">
            {pageRows.map((row) => {
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
              const legacyPaid = !proof && !gatewayPaid && !!row.payment_verified_at
              const reviewWithoutProof =
                !proof && !gatewayPaid && !legacyPaid && row.status === 'payment_under_review'
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
                      <p className="flex flex-wrap items-center gap-2 font-mono text-[11px] text-muted">
                        <span>#{shortId(row.id)}</span>
                        <span aria-hidden="true">·</span>
                        <span className="font-sans">{row.store_name}</span>
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
                          <Detail label="Reference">
                            <CopyValue value={proof.reference_number} label="reference" />
                          </Detail>
                          <Detail label="Sender">{proof.sender_name || '—'}</Detail>
                          <Detail label="Amount sent" tone={amountMatches ? 'ok' : 'danger'}>
                            {proof.amount_paid != null
                              ? formatCurrency(proof.amount_paid)
                              : '—'}
                          </Detail>
                          <Detail label="Order code">
                            {row.order_code ? (
                              <CopyValue value={row.order_code} label="order code" />
                            ) : (
                              '—'
                            )}
                          </Detail>
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
                            <Detail label="Order code">
                              {row.order_code ? (
                                <CopyValue value={row.order_code} label="order code" />
                              ) : (
                                '—'
                              )}
                            </Detail>
                            <Detail label="Order status">
                              {STATUS_LABEL[row.status] ?? row.status}
                            </Detail>
                            {row.gcash_reference_number ? (
                              <Detail label="Reference on order">
                                <CopyValue
                                  value={row.gcash_reference_number}
                                  label="reference"
                                />
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
                        <Tooltip label="See the receipt the customer uploaded.">
                          <button type="button" className={BTN} onClick={() => openProof(row)}>
                            <ImageIcon size={13} strokeWidth={1.7} aria-hidden="true" />
                            Screenshot
                          </button>
                        </Tooltip>
                      ) : null}
                      {row.status === 'payment_under_review' ? (
                        <Tooltip label="Accept the proof and mark the order paid for the store.">
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
                        </Tooltip>
                      ) : null}
                      {row.payment_status === 'paid' && !row.funds_reconciled_at ? (
                        <Tooltip label="Record that the money already shows in the platform account.">
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
                        </Tooltip>
                      ) : null}
                      {row.payment_flagged ? (
                        <Tooltip label="Remove the flag once the concern is resolved.">
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
                        </Tooltip>
                      ) : (
                        <Tooltip label="Mark this payment for investigation.">
                          <button
                            type="button"
                            className={BTN_DANGER}
                            disabled={busyId === row.id}
                            onClick={() => onFlag(row)}
                          >
                            <XCircle size={13} strokeWidth={1.7} aria-hidden="true" />
                            Flag
                          </button>
                        </Tooltip>
                      )}
                    </div>
                  </div>
                </li>
              )
            })}
          </ul>
        )}

        {filtered.length > PAGE_SIZE ? (
          <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-3">
            <p className="text-[12px] text-muted">
              <span className="font-semibold text-ink">
                {rangeStart}–{rangeEnd}
              </span>{' '}
              of {filtered.length.toLocaleString('en-PH')} orders
            </p>
            <div className="flex items-center gap-1">
              <Tooltip label="Show the previous page.">
                <button
                  type="button"
                  disabled={safePage <= 1}
                  onClick={() => setPage((current) => Math.max(1, current - 1))}
                  aria-label="Previous page"
                  className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-card text-muted transition-colors hover:border-primary/40 hover:text-ink disabled:cursor-not-allowed disabled:opacity-35"
                >
                  <ChevronLeft size={14} />
                </button>
              </Tooltip>
              <span className="px-2 font-mono text-[11px] text-muted">
                {safePage} / {totalPages}
              </span>
              <Tooltip label="Show the next page.">
                <button
                  type="button"
                  disabled={safePage >= totalPages}
                  onClick={() => setPage((current) => Math.min(totalPages, current + 1))}
                  aria-label="Next page"
                  className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-card text-muted transition-colors hover:border-primary/40 hover:text-ink disabled:cursor-not-allowed disabled:opacity-35"
                >
                  <ChevronRight size={14} />
                </button>
              </Tooltip>
            </div>
          </div>
        ) : null}
      </section>

      {proofView ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Proof screenshot"
          className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-secondary/80 p-4"
          onClick={() => setProofView(null)}
        >
          <div
            className="flex w-full max-w-4xl flex-wrap items-center justify-between gap-2 pb-3 text-surface"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="min-w-0">
              <p className="font-mono text-[13px] font-semibold">
                {proofView.reference || 'Reference not readable'}
                <span className="ml-3 text-[#C4A882]">{formatCurrency(proofView.amount)}</span>
              </p>
              <p className="mt-0.5 truncate text-[11.5px] text-[#C4A882]">
                {proofView.sender || 'Sender not readable'}
                {proofView.orderCode ? ` · ${proofView.orderCode}` : ''}
              </p>
            </div>
            <Tooltip label="Close the screenshot.">
            <button
              type="button"
              onClick={() => setProofView(null)}
              aria-label="Close screenshot"
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-white/10 transition-colors hover:bg-white/20"
            >
              <X size={16} />
            </button>
            </Tooltip>
          </div>
          {proofView.status === 'ready' ? (
            <img
              src={proofView.url}
              alt={`Proof screenshot ${proofView.reference ?? ''}`.trim()}
              className="max-h-[82vh] w-auto max-w-full rounded-lg bg-card object-contain shadow-pop"
              onClick={(e) => e.stopPropagation()}
              onError={failProofImage}
            />
          ) : (
            <div
              role={proofView.status === 'error' ? 'alert' : 'status'}
              className="flex w-full max-w-md flex-col items-center gap-3 rounded-xl bg-card px-6 py-8 text-center"
              onClick={(e) => e.stopPropagation()}
            >
              {proofView.status === 'error' ? (
                <>
                  <AlertTriangle size={22} strokeWidth={1.8} className="text-[#8A5D14]" />
                  <p className="text-[12.5px] leading-relaxed text-ink">{proofView.error}</p>
                  <Tooltip label="Sign a fresh link and load the screenshot again.">
                    <button type="button" className={BTN} onClick={retryProof}>
                      <RefreshCw size={13} strokeWidth={1.7} aria-hidden="true" />
                      Try again
                    </button>
                  </Tooltip>
                </>
              ) : (
                <>
                  <Loader2
                    size={22}
                    strokeWidth={1.8}
                    className="animate-spin text-primary"
                    aria-hidden="true"
                  />
                  <p className="text-[12.5px] text-muted">Loading the screenshot…</p>
                </>
              )}
            </div>
          )}
        </div>
      ) : null}
    </div>
  )
}
