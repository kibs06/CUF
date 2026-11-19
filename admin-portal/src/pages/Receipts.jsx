import { useMemo, useState } from 'react'
import {
  AlertTriangle,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Clock,
  Download,
  Printer,
  Receipt as ReceiptIcon,
  Search,
  SearchX,
  Send,
  X,
} from 'lucide-react'

import Badge from '../components/ui/Badge.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import { TableSkeleton } from '../components/ui/Skeleton.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import { useReceipts } from '../hooks/useReceipts.js'
import { downloadCsv } from '../lib/audit.js'
import { formatCurrency, formatDateTime } from '../lib/constants'
import { printReceipt } from '../lib/receipt.js'
import {
  RECEIPT_FILTERS,
  RECEIPT_STATE_META,
  matchesReceiptFilter,
  matchesReceiptSearch,
  receiptAddress,
  receiptCodeOf,
  receiptState,
  receiptSummary,
  receiptsCsv,
} from '../lib/receiptTrail.js'

const PAGE_SIZE = 25

function Tile({ icon: Icon, label, value, caption, tone }) {
  return (
    <div className="admin-3d-surface rounded-xl border border-border bg-card p-3.5">
      <div className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted">
        <Icon size={13} strokeWidth={2.2} aria-hidden="true" className={tone} />
        {label}
      </div>
      <p className="mt-1.5 font-mono text-[22px] font-semibold tracking-tight text-ink">{value}</p>
      <p className="mt-0.5 text-[11.5px] text-muted">{caption}</p>
    </div>
  )
}

/** The line under the receipt badge: who has it, or why nobody does yet. */
function ReceiptDetail({ order, state, now }) {
  if (state === 'sent') {
    const address = receiptAddress(order)
    return (
      <span className="text-[11.5px] text-muted">
        {address || 'Customer copy'} · {formatDateTime(order.receipt_emailed_at)}
      </span>
    )
  }
  if (state === 'sending') {
    return <span className="text-[11.5px] text-muted">A send is in flight right now.</span>
  }
  if (state === 'retrying') {
    const nextAt = Date.parse(order.receipt_email_next_attempt_at ?? '')
    return (
      <span className="text-[11.5px] text-muted">
        Next attempt {Number.isFinite(nextAt) ? formatDateTime(order.receipt_email_next_attempt_at) : 'queued'}
      </span>
    )
  }
  if (state === 'failed') {
    return (
      <span className="block max-w-[260px] truncate text-[11.5px] text-error" title={order.receipt_email_last_error ?? ''}>
        {order.receipt_email_last_error || 'The last send failed.'}
      </span>
    )
  }
  return (
    <span className="text-[11.5px] text-muted">
      {Number(order.receipt_email_attempts) > 0
        ? `${order.receipt_email_attempts} attempt${Number(order.receipt_email_attempts) === 1 ? '' : 's'} so far`
        : 'No receipt emailed yet.'}
    </span>
  )
}

/**
 * Receipts — whether the customer's copy actually left the building.
 *
 * Every row is a sale, and the state comes from the same columns the sender
 * writes: `receipt_emailed_at` only appears after SMTP accepted the message,
 * the attempt counter and last error explain a failure, and the next-attempt
 * time says whether the retry sweep will pick it up again. Read-only by
 * design — the monitor's job is to show the trail, not to mail customers.
 */
export default function Receipts() {
  const { showToast } = useToast()
  const { data, isLoading, isError, error } = useReceipts()
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState('all')
  const [page, setPage] = useState(1)

  // One clock for the whole render, so two rows cannot disagree about whether
  // a lease is still alive.
  const now = Date.now()
  const rows = data ?? []
  const summary = useMemo(() => receiptSummary(rows, now), [rows, now])
  const filtered = useMemo(
    () =>
      rows.filter(
        (order) =>
          matchesReceiptFilter(order, filter, now) && matchesReceiptSearch(order, query),
      ),
    [rows, filter, query, now],
  )
  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const current = Math.min(page, pageCount)
  const visible = filtered.slice((current - 1) * PAGE_SIZE, current * PAGE_SIZE)

  const handlePrint = (order) => {
    if (!printReceipt(order)) {
      showToast('Allow pop-ups for this site to print the receipt', 'error')
    }
  }

  const handleExport = () => {
    downloadCsv(`receipts-${new Date().toISOString().slice(0, 10)}.csv`, receiptsCsv(filtered, now))
    showToast(`${filtered.length} receipt${filtered.length === 1 ? '' : 's'} exported`)
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Tile
          icon={ReceiptIcon}
          label="Sales in view"
          value={summary.total}
          caption="Most recent 500, both channels"
          tone="text-primary"
        />
        <Tile
          icon={CheckCircle2}
          label="Sent"
          value={summary.sent}
          caption="Customer copy delivered"
          tone="text-accent"
        />
        <Tile
          icon={Clock}
          label="Waiting"
          value={summary.waiting}
          caption="Not sent, sending, or retrying"
          tone="text-info"
        />
        <Tile
          icon={AlertTriangle}
          label="Failed"
          value={summary.failed}
          caption="No retry scheduled"
          tone="text-error"
        />
      </div>

      <div className="admin-3d-surface overflow-hidden rounded-xl border border-border bg-card">
        <div className="flex flex-wrap items-center gap-2 border-b border-border px-3 py-2.5">
          <div className="relative min-w-[190px] flex-1">
            <Search
              size={13}
              aria-hidden="true"
              className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-muted"
            />
            <input
              value={query}
              onChange={(event) => {
                setQuery(event.target.value)
                setPage(1)
              }}
              placeholder="Search receipt code, store, customer, or email"
              aria-label="Search receipts"
              className="h-9 w-full rounded-lg border border-border bg-canvas pl-8 pr-8 text-[12px] text-ink outline-none transition-colors placeholder:text-muted/70 focus:border-primary focus:ring-2 focus:ring-primary/15"
            />
            {query && (
              <button
                type="button"
                onClick={() => {
                  setQuery('')
                  setPage(1)
                }}
                aria-label="Clear search"
                className="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-muted transition-colors hover:text-ink"
              >
                <X size={12} aria-hidden="true" />
              </button>
            )}
          </div>

          <div className="flex flex-wrap items-center gap-1">
            {RECEIPT_FILTERS.map((option) => {
              const active = filter === option.key
              return (
                <button
                  key={option.key}
                  type="button"
                  onClick={() => {
                    setFilter(option.key)
                    setPage(1)
                  }}
                  aria-pressed={active}
                  className={`h-8 rounded-lg px-2.5 text-[11.5px] font-semibold transition-colors ${
                    active
                      ? 'bg-secondary text-white'
                      : 'bg-canvas text-muted hover:text-ink'
                  }`}
                >
                  {option.label}
                </button>
              )
            })}
          </div>

          <button
            type="button"
            onClick={handleExport}
            disabled={filtered.length === 0}
            className="inline-flex h-9 items-center gap-1.5 rounded-lg border border-border bg-card px-3 text-[12px] font-semibold text-ink transition-colors hover:border-primary hover:text-primary disabled:cursor-not-allowed disabled:opacity-40"
          >
            <Download size={13} aria-hidden="true" />
            Export CSV
          </button>
        </div>

        {isLoading ? (
          <div className="p-3">
            <TableSkeleton rows={6} cols={5} />
          </div>
        ) : isError ? (
          <div className="px-4 py-14 text-center">
            <p className="text-[13px] font-semibold text-ink">Could not load the receipt trail</p>
            <p className="mt-1 text-[12px] text-muted">{error?.message ?? 'Unknown error'}</p>
          </div>
        ) : filtered.length === 0 ? (
          <div className="p-3">
            <EmptyState
              Icon={query || filter !== 'all' ? SearchX : Send}
              title={query || filter !== 'all' ? 'No receipts match' : 'No sales yet'}
              description={
                query || filter !== 'all'
                  ? 'Try a different code, store, or email — or clear the filters.'
                  : 'Receipts appear here as soon as an order or a till sale exists.'
              }
              action={
                query || filter !== 'all' ? (
                  <button
                    type="button"
                    onClick={() => {
                      setQuery('')
                      setFilter('all')
                      setPage(1)
                    }}
                    className="mt-3 inline-flex h-8 items-center rounded-lg bg-secondary px-3 text-[11.5px] font-semibold text-white transition-colors hover:bg-primaryDeep"
                  >
                    Clear filters
                  </button>
                ) : null
              }
            />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[880px] text-left">
              <thead>
                <tr className="border-b border-border text-[11px] uppercase tracking-wide text-muted">
                  <th className="px-3 py-2 font-semibold">Receipt</th>
                  <th className="px-3 py-2 font-semibold">Store</th>
                  <th className="px-3 py-2 font-semibold">Customer</th>
                  <th className="px-3 py-2 font-semibold">Sale</th>
                  <th className="px-3 py-2 font-semibold">Receipt</th>
                  <th className="px-3 py-2 text-right font-semibold">Copy</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {visible.map((order) => {
                  const state = receiptState(order, now)
                  const meta = RECEIPT_STATE_META[state]
                  return (
                    <tr key={order.id} className="align-top hover:bg-canvas/50">
                      <td className="px-3 py-2.5">
                        <p className="font-mono text-[12px] font-semibold text-ink">
                          #{receiptCodeOf(order)}
                        </p>
                        <p className="mt-0.5 text-[11px] text-muted">
                          {formatDateTime(order.created_at)}
                        </p>
                      </td>
                      <td className="px-3 py-2.5">
                        <p className="max-w-[180px] truncate text-[12px] font-medium text-ink">
                          {order.store_name}
                        </p>
                        <p className="mt-0.5 text-[11px] text-muted">
                          {order.source === 'pos' ? 'Walk-in' : 'Online'}
                        </p>
                      </td>
                      <td className="px-3 py-2.5">
                        <p className="max-w-[170px] truncate text-[12px] font-medium text-ink">
                          {order.customer_name}
                        </p>
                        <p className="mt-0.5 max-w-[170px] truncate text-[11px] text-muted">
                          {receiptAddress(order) || 'No email on file'}
                        </p>
                      </td>
                      <td className="px-3 py-2.5">
                        <p className="font-mono text-[12px] font-semibold text-ink">
                          {formatCurrency(order.total_amount)}
                        </p>
                        <p className="mt-0.5 text-[11px] text-muted">
                          {order.status ?? '—'}
                        </p>
                      </td>
                      <td className="px-3 py-2.5">
                        <Badge label={meta.label} variant={meta.tone} dot />
                        <div className="mt-1">
                          <ReceiptDetail order={order} state={state} now={now} />
                        </div>
                      </td>
                      <td className="px-3 py-2.5 text-right">
                        <button
                          type="button"
                          onClick={() => handlePrint(order)}
                          title="Print this receipt"
                          className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-card px-2.5 text-[11.5px] font-semibold text-ink transition-colors hover:border-primary hover:text-primary"
                        >
                          <Printer size={12} aria-hidden="true" />
                          Print
                        </button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}

        {!isLoading && !isError && filtered.length > 0 && (
          <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border px-3 py-2">
            <p className="text-[11.5px] text-muted">
              {filtered.length} receipt{filtered.length === 1 ? '' : 's'} · page {current} of {pageCount}
            </p>
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={() => setPage(Math.max(1, current - 1))}
                disabled={current <= 1}
                aria-label="Previous page"
                className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-border text-muted transition-colors hover:text-ink disabled:opacity-40"
              >
                <ChevronLeft size={13} aria-hidden="true" />
              </button>
              <button
                type="button"
                onClick={() => setPage(Math.min(pageCount, current + 1))}
                disabled={current >= pageCount}
                aria-label="Next page"
                className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-border text-muted transition-colors hover:text-ink disabled:opacity-40"
              >
                <ChevronRight size={13} aria-hidden="true" />
              </button>
            </div>
          </div>
        )}
      </div>

      <p className="text-[11.5px] text-muted">
        A receipt counts as sent only after the mail server accepted it; a failed one
        keeps its reason and, when the retry sweep is armed, its next attempt time.
      </p>
    </div>
  )
}
