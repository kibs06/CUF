import { useMemo, useState } from 'react'
import { Download, Search, SearchX, ShoppingBag, X } from 'lucide-react'

import Badge from '../components/ui/Badge.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import StatCard from '../components/ui/StatCard.jsx'
import { TableSkeleton } from '../components/ui/Skeleton.jsx'
import Tooltip from '../components/ui/Tooltip.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import { useBulkReservations } from '../hooks/useBulkReservations.js'
import { formatCurrency, formatDateTime, shortId } from '../lib/constants'

const PAGE_SIZE = 25

// Reservation status → the Badge palette that already exists in the portal, so
// a hold reads the same colour here as a seller/refund state does elsewhere.
const STATUS_VARIANT = {
  pending: 'pending',
  awaiting_deposit: 'placed',
  approved: 'approved',
  fulfilled: 'fulfilled',
  rejected: 'rejected',
  cancelled: 'cancelled',
  expired: 'expired',
}

// The deposit is the only money this flow takes up front, so its state — not
// the reservation's — is what an admin is reconciling here.
const DEPOSIT_BADGE = {
  paid: { label: 'Deposit paid', variant: 'approved' },
  unpaid: { label: 'Deposit unpaid', variant: 'pending' },
  forfeited: { label: 'Deposit forfeited', variant: 'rejected' },
  refunded: { label: 'Deposit refunded', variant: 'dismissed' },
  not_required: { label: 'No deposit', variant: 'none' },
}

function depositBadge(reservation) {
  return DEPOSIT_BADGE[reservation.deposit_status] ?? DEPOSIT_BADGE.not_required
}

function escCsv(value) {
  const s = String(value ?? '')
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

function exportCsv(rows) {
  const header = [
    'Reservation', 'Requested at', 'Customer', 'Customer email', 'Store',
    'Product', 'Units', 'Sizes', 'Unit price (PHP)', 'Estimated value (PHP)',
    'Reservation status', 'Deposit (PHP)', 'Deposit status', 'GCash reference',
    'Deposit deadline', 'Hold ends', 'Fulfilled at', 'Note', 'Rejection reason',
  ]
  const lines = rows.map((r) =>
    [
      shortId(r.id), r.created_at, r.customer_name, r.customer_email, r.store_name,
      r.product_name, r.quantity, r.sizes_text, r.unit_price, r.estimated_value,
      r.status, r.deposit_amount ?? '', r.deposit_status,
      r.deposit_reference ?? '', r.deposit_deadline ?? '', r.expires_at ?? '',
      r.fulfilled_at ?? '', r.note ?? '', r.rejection_reason ?? '',
    ]
      .map(escCsv)
      .join(','),
  )
  const csv = `\uFEFF${[header.join(','), ...lines].join('\n')}`
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `bulk-buying-${new Date().toISOString().slice(0, 10)}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

function matchesSearch(reservation, search) {
  const haystack = [
    reservation.id,
    reservation.customer_name,
    reservation.customer_email,
    reservation.store_name,
    reservation.product_name,
    reservation.sizes_text,
    reservation.deposit_reference,
    reservation.status,
    reservation.deposit_status,
    reservation.note,
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase()
  return haystack.includes(search.toLowerCase())
}

/**
 * Bulk buying — reseller holds requested from product pages, and the deposits
 * that secure them.
 *
 * A different ledger from Paid sales: no order exists, no stock moves until the
 * seller approves, and the only money received is the non-refundable GCash
 * deposit. That deposit is what this view reconciles — the reservation itself is
 * a promise, so its "estimated value" is shown as a separate figure and never
 * added to a money total.
 */
export default function BulkBuying() {
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const { showToast } = useToast()

  const { data, isLoading, isError, error } = useBulkReservations()

  const rows = data?.rows ?? []

  const filtered = useMemo(() => {
    const term = search.trim()
    return term ? rows.filter((row) => matchesSearch(row, term)) : rows
  }, [rows, search])

  const stats = useMemo(() => {
    let depositsReceived = 0
    let depositsPending = 0
    let unitsHeld = 0
    for (const row of filtered) {
      if (row.deposit_status === 'paid') depositsReceived += row.deposit_amount ?? 0
      if (row.status === 'awaiting_deposit' && row.deposit_status === 'unpaid') {
        depositsPending += row.deposit_amount ?? 0
      }
      if (row.status === 'approved') unitsHeld += row.quantity
    }
    return { requests: filtered.length, depositsReceived, depositsPending, unitsHeld }
  }, [filtered])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const safePage = Math.min(page, totalPages)
  const pageRows = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE)

  const handleExport = () => {
    if (!filtered.length) {
      showToast('Nothing to export in the current filters', 'error')
      return
    }
    exportCsv(filtered)
    showToast(`Exported ${filtered.length} reservation${filtered.length === 1 ? '' : 's'}`)
  }

  const cards = [
    {
      key: 'requests',
      label: 'Bulk requests',
      value: stats.requests.toLocaleString(),
      caption: 'in the current filters',
    },
    {
      key: 'received',
      label: 'Deposits received',
      value: formatCurrency(stats.depositsReceived),
      caption: 'non-refundable, counted when paid',
    },
    {
      key: 'pending',
      label: 'Deposits awaited',
      value: formatCurrency(stats.depositsPending),
      caption: 'approved holds still unpaid',
    },
    {
      key: 'units',
      label: 'Units on hold',
      value: stats.unitsHeld.toLocaleString(),
      caption: 'stock reserved by paid holds',
    },
  ]

  return (
    <div className="space-y-4">
      <section
        aria-label="Bulk buying summaries"
        className="grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-border bg-border xl:grid-cols-4"
      >
        {isLoading
          ? Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="bg-card p-5">
                <div className="mb-3 h-3 w-24 animate-pulse rounded bg-canvas" />
                <div className="h-7 w-20 animate-pulse rounded bg-canvas" />
              </div>
            ))
          : cards.map((card) => (
              <div key={card.key} className="bg-card">
                <StatCard bare label={card.label} value={card.value} caption={card.caption} />
              </div>
            ))}
      </section>

      <div className="rounded-xl border border-border bg-card p-4">
        <div className="flex flex-wrap items-center gap-3">
          <p className="max-w-xl text-[12.5px] font-medium text-muted">
            Reseller holds requested from product pages. Nothing was sold: approval
            moves stock into a hold, and the deposit is the only money taken up front.
            Bulk holds are store pickup only — nothing is shipped.
          </p>
          <div className="ml-auto flex flex-wrap items-center gap-3">
            <Tooltip label="Download every reservation currently in view as a CSV file.">
              <button
                type="button"
                onClick={handleExport}
                disabled={!filtered.length}
                className="inline-flex items-center gap-2 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-white transition-all hover:bg-secondary disabled:opacity-40"
              >
                <Download size={16} />
                Export CSV
              </button>
            </Tooltip>
          </div>
        </div>

        <div className="relative mt-3">
          <Search size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted" />
          <input
            type="search"
            placeholder="Search customer, store, product, size, status or GCash reference…"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value)
              setPage(1)
            }}
            className="w-full rounded-xl border border-border bg-canvas py-2.5 pl-10 pr-10 text-sm text-ink placeholder-muted outline-none transition-all focus:border-primary focus:bg-card focus:ring-2 focus:ring-primary/20"
          />
          {search && (
            <button
              type="button"
              onClick={() => setSearch('')}
              aria-label="Clear search"
              className="absolute right-3 top-1/2 -translate-y-1/2 rounded-full p-1 text-muted transition-colors hover:bg-canvas hover:text-ink"
            >
              <X size={14} />
            </button>
          )}
        </div>

        {search && (
          <div className="mt-3 text-xs text-muted">
            <span className="tnum">
              {filtered.length} of {rows.length} match
            </span>
          </div>
        )}
      </div>

      {isLoading && <TableSkeleton cols={5} rows={6} />}
      {isError && (
        <div className="rounded-xl border border-border bg-card p-8 text-center">
          <p className="text-sm text-error">{error.message}</p>
        </div>
      )}

      {!isLoading && !isError && (
        <>
          <div className="overflow-x-auto rounded-xl border border-border bg-card">
            <table className="min-w-full text-left text-sm">
              <caption className="sr-only">
                Bulk reservations with date, customer, what was requested, the deposit
                received and how long the stock is held
              </caption>
              <thead className="bg-canvas">
                <tr>
                  <th scope="col" className="px-6 py-4 text-[12px] font-medium text-muted">
                    <Tooltip label="When the customer asked for the hold.">Date</Tooltip>
                  </th>
                  <th scope="col" className="px-6 py-4 text-[12px] font-medium text-muted">
                    <Tooltip label="Who asked, and the store that has to decide.">Customer</Tooltip>
                  </th>
                  <th scope="col" className="px-6 py-4 text-[12px] font-medium text-muted">
                    <Tooltip label="Product, units and the size split the customer asked for.">
                      Requested
                    </Tooltip>
                  </th>
                  <th scope="col" className="px-6 py-4 text-right text-[12px] font-medium text-muted">
                    <Tooltip label="The non-refundable GCash deposit and its GCash reference.">
                      Deposit
                    </Tooltip>
                  </th>
                  <th scope="col" className="px-6 py-4 text-[12px] font-medium text-muted">
                    <Tooltip label="Where the reservation stands, and when the hold ends.">
                      Hold
                    </Tooltip>
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-canvas">
                {pageRows.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="p-0">
                      <EmptyState
                        Icon={rows.length === 0 && !search ? ShoppingBag : SearchX}
                        title={rows.length === 0 && !search ? 'No bulk buying yet' : 'No matches'}
                        description={
                          rows.length === 0 && !search
                            ? 'Reseller holds appear here as soon as a customer requests one from a product page.'
                            : 'Nothing matches that search. Try a customer, store, product, size or GCash reference.'
                        }
                      />
                    </td>
                  </tr>
                ) : (
                  pageRows.map((row) => {
                    const badge = depositBadge(row)
                    return (
                      <tr key={row.id} className="transition-colors hover:bg-canvas/60">
                        <td className="whitespace-nowrap px-6 py-4 text-[12.5px] text-muted">
                          {formatDateTime(row.created_at)}
                        </td>
                        <td className="px-6 py-4">
                          <div className="font-medium text-ink">{row.customer_name}</div>
                          <div className="truncate text-[12px] text-muted">
                            {row.store_name}
                          </div>
                        </td>
                        <td className="px-6 py-4">
                          <div className="font-medium text-ink">{row.product_name}</div>
                          <div className="text-[12px] text-muted">
                            {row.quantity} unit{row.quantity === 1 ? '' : 's'}
                            {row.sizes_text ? ` · ${row.sizes_text}` : ''}
                          </div>
                          <div className="tnum text-[11.5px] text-muted/80">
                            ≈ {formatCurrency(row.estimated_value)} at pickup
                          </div>
                        </td>
                        <td className="whitespace-nowrap px-6 py-4 text-right">
                          <div className="tnum font-semibold text-ink">
                            {row.deposit_amount == null
                              ? '—'
                              : formatCurrency(row.deposit_amount)}
                          </div>
                          <div className="mt-1 flex justify-end">
                            <Badge label={badge.label} variant={badge.variant} dot />
                          </div>
                          {row.deposit_reference && (
                            <div className="tnum mt-1 text-[11.5px] text-muted">
                              ref {row.deposit_reference}
                            </div>
                          )}
                        </td>
                        <td className="px-6 py-4">
                          <Badge
                            label={String(row.status).replace(/_/g, ' ')}
                            variant={STATUS_VARIANT[row.status] ?? 'none'}
                          />
                          <div className="mt-1 text-[11.5px] text-muted">
                            {row.fulfilled_at
                              ? `picked up ${formatDateTime(row.fulfilled_at)}`
                              : row.expires_at
                                ? `hold ends ${formatDateTime(row.expires_at)}`
                                : 'not held yet'}
                          </div>
                        </td>
                      </tr>
                    )
                  })
                )}
              </tbody>
            </table>
          </div>

          {totalPages > 1 && (
            <div className="flex items-center justify-between rounded-xl border border-border bg-card px-4 py-3 text-[12.5px] text-muted">
              <span className="tnum">
                Page {safePage} of {totalPages} · {filtered.length} reservations
              </span>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={safePage === 1}
                  className="rounded-full border border-border px-3 py-1.5 font-semibold text-ink transition-colors hover:bg-canvas disabled:opacity-40"
                >
                  Previous
                </button>
                <button
                  type="button"
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                  disabled={safePage === totalPages}
                  className="rounded-full border border-border px-3 py-1.5 font-semibold text-ink transition-colors hover:bg-canvas disabled:opacity-40"
                >
                  Next
                </button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  )
}
