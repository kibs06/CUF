import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { AnimatePresence, motion, useReducedMotion } from 'motion/react'
import { Search, Download, ArrowUpRight } from 'lucide-react'
import Badge from '../components/ui/Badge.jsx'
import Modal from '../components/ui/Modal.jsx'
import StatCard from '../components/ui/StatCard.jsx'
import { StatCardSkeleton, TableSkeleton } from '../components/ui/Skeleton.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import { useTransactions } from '../hooks/useTransactions.js'
import {
  formatCurrency,
  formatDateTime,
  shortId,
  PAYMENT_INTENT_STATUSES,
} from '../lib/constants'

const PAGE_SIZE = 20

const EVENT_STATUS_VARIANTS = {
  processed: 'processed',
  processing: 'processing',
  received: 'processing',
  amount_mismatch: 'amount_mismatch',
  stock_conflict: 'stock_conflict',
  rejected_signature: 'rejected_signature',
  failed: 'failed',
}

function humanize(value) {
  return String(value ?? '')
    .replace(/[._]/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase())
}

function escCsv(value) {
  const s = String(value ?? '')
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

function exportCsv(rows) {
  const header = [
    'Order ID', 'Store', 'Customer', 'Amount (PHP)', 'Model B Fee (PHP)',
    'PayMongo Fee (PHP)', 'Net (PHP)', 'Status', 'GCash Ref',
    'Checkout Session', 'PayMongo Payment ID', 'Created At', 'Updated At',
  ]
  const lines = rows.map((r) =>
    [
      r.order_id, r.store_name, r.customer_name, r.amount, r.fee_amount,
      r.paymongo_fee_amount ?? '', r.net_amount ?? '', r.status,
      r.gcash_reference_number ?? '', r.checkout_session_id ?? '',
      r.paymongo_payment_intent_id ?? '', r.created_at, r.updated_at,
    ]
      .map(escCsv)
      .join(','),
  )
  const csv = `\uFEFF${[header.join(','), ...lines].join('\n')}`
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `transactions-${new Date().toISOString().slice(0, 10)}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

// ── Count-up number for stat cards (numeric tween only; <800ms) ──────
function AnimatedNumber({ value, format = (v) => v }) {
  const reduce = useReducedMotion()
  const [display, setDisplay] = useState(value)
  const prevRef = useRef(value)

  useEffect(() => {
    const from = prevRef.current
    if (reduce || from === value) {
      prevRef.current = value
      setDisplay(value)
      return
    }
    const start = performance.now()
    const duration = 700
    let raf
    const tick = (now) => {
      const t = Math.min(1, (now - start) / duration)
      const eased = 1 - Math.pow(1 - t, 3)
      setDisplay(from + (value - from) * eased)
      if (t < 1) raf = requestAnimationFrame(tick)
      else prevRef.current = value
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [value, reduce])

  return <>{format(display)}</>
}

const moneyFormat = (v) => formatCurrency(Math.round(v * 100) / 100)

// ── Status badge that pulses only when the status actually changes ───
function StatusBadge({ rowId, status }) {
  const reduce = useReducedMotion()
  const seen = useRef(new Map())
  const wasSeen = seen.current.has(rowId)
  const changed = wasSeen && seen.current.get(rowId) !== status
  seen.current.set(rowId, status)

  if (reduce || !changed) return <Badge label={status} variant={status} />

  return (
    <motion.span
      key={status}
      initial={{ scale: 1.18, opacity: 0.5 }}
      animate={{ scale: 1, opacity: 1 }}
      transition={{ type: 'spring', bounce: 0.1, duration: 0.45 }}
    >
      <Badge label={status} variant={status} />
    </motion.span>
  )
}

function EventTimeline({ events }) {
  const reduce = useReducedMotion()
  const [openPayload, setOpenPayload] = useState(null)

  if (!events?.length) {
    return <p className="text-sm text-[#6B5C4E]">No webhook events recorded for this transaction.</p>
  }

  return (
    <ol className="relative space-y-4 border-l border-[#D9D0C7] pl-5">
      <AnimatePresence initial={false}>
        {events.map((e, i) => (
          <motion.li
            key={e.id}
            initial={reduce ? false : { opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.25, delay: i * 0.05 }}
          >
            <span className="absolute -left-[5px] mt-1.5 h-2.5 w-2.5 rounded-full border-2 border-white bg-[#8B5A2B]" />
            <div className="flex flex-wrap items-center gap-2">
              <p className="text-sm font-semibold text-[#3B2314]">{humanize(e.event_type)}</p>
              <Badge label={e.status} variant={EVENT_STATUS_VARIANTS[e.status] ?? e.status} />
            </div>
            <p className="mt-0.5 text-xs text-[#6B5C4E]">
              {formatDateTime(e.received_at)}
              {e.processed_at ? ` · processed ${formatDateTime(e.processed_at)}` : ''}
              {e.amount != null ? ` · ${formatCurrency(e.amount)}` : ''}
            </p>
            {e.redacted_payload && (
              <div>
                <button
                  type="button"
                  onClick={() => setOpenPayload(openPayload === e.id ? null : e.id)}
                  className="mt-1 text-xs font-semibold text-[#8B5A2B] hover:underline"
                >
                  {openPayload === e.id ? 'Hide raw event' : 'View raw event'}
                </button>
                {openPayload === e.id && (
                  <pre className="mt-2 max-h-48 overflow-auto rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] p-3 text-[11px] leading-relaxed text-[#6B5C4E]">
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

function TransactionDetail({ transaction, feeColumnsAvailable, onClose }) {
  const reduce = useReducedMotion()
  const orderStatus = transaction?.order_status
  return (
    <Modal open={!!transaction} onClose={onClose} title={transaction ? `Transaction ${shortId(transaction.id)}` : ''} size="xl">
      {transaction && (
        <div className="space-y-6 text-sm">
          {/* Amount summary */}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
              <p className="text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Amount charged</p>
              <p className="mt-1 font-mono text-lg font-bold text-[#3B2314]">{formatCurrency(transaction.amount)}</p>
            </div>
            <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
              <p className="text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Model B fee</p>
              <p className="mt-1 font-mono text-lg font-bold text-[#3B2314]">{formatCurrency(transaction.fee_amount)}</p>
            </div>
            <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
              <p className="text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">PayMongo fee</p>
              <p className="mt-1 font-mono text-lg font-bold text-[#3B2314]">
                {transaction.paymongo_fee_amount != null
                  ? formatCurrency(transaction.paymongo_fee_amount)
                  : '—'}
              </p>
            </div>
            <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
              <p className="text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Net</p>
              <p className="mt-1 font-mono text-lg font-bold text-[#3B2314]">
                {transaction.net_amount != null ? formatCurrency(transaction.net_amount) : '—'}
              </p>
            </div>
          </div>

          {!feeColumnsAvailable && (
            <p className="rounded-xl border border-[#E8A020]/40 bg-[#E8A020]/10 px-4 py-2.5 text-xs text-[#8a6100]">
              Fee and net columns are not in the database yet — apply the admin-transactions
              migration (20260810000000_admin_transactions_view.sql) to populate them.
            </p>
          )}

          {/* Order context */}
          <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <p className="font-semibold text-[#3B2314]">{transaction.customer_name}</p>
                <p className="text-xs text-[#6B5C4E]">{transaction.customer_email}</p>
                <p className="mt-1 text-xs text-[#6B5C4E]">
                  {transaction.store_name} · Order {shortId(transaction.order_id)} ·{' '}
                  {formatDateTime(transaction.created_at)}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <Badge label={`order: ${orderStatus ?? '—'}`} variant={orderStatus} />
                <Badge
                  label={`payment: ${transaction.order_payment_status ?? '—'}`}
                  variant={transaction.order_payment_status}
                />
              </div>
            </div>
            <div className="mt-3 grid grid-cols-2 gap-x-6 gap-y-1.5 border-t border-[#F5F0EB] pt-3 text-xs sm:grid-cols-3">
              <div><span className="text-[#6B5C4E]">Order total </span><span className="font-mono text-[#3B2314]">{formatCurrency(transaction.order_total_amount)}</span></div>
              <div><span className="text-[#6B5C4E]">Order GCash fee </span><span className="font-mono text-[#3B2314]">{formatCurrency(transaction.order_gcash_fee_amount)}</span></div>
              <div><span className="text-[#6B5C4E]">Expires </span><span className="font-mono text-[#3B2314]">{formatDateTime(transaction.expires_at)}</span></div>
              <div><span className="text-[#6B5C4E]">Paid at </span><span className="font-mono text-[#3B2314]">{transaction.paid_at ? formatDateTime(transaction.paid_at) : '—'}</span></div>
              <div><span className="text-[#6B5C4E]">Verified at </span><span className="font-mono text-[#3B2314]">{transaction.payment_verified_at ? formatDateTime(transaction.payment_verified_at) : '—'}</span></div>
              <div><span className="text-[#6B5C4E]">Livemode </span><span className="font-mono text-[#3B2314]">{transaction.livemode ? 'yes' : 'no'}</span></div>
            </div>
          </div>

          {/* References */}
          <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">References</h3>
            <div className="grid grid-cols-1 gap-1.5 text-xs sm:grid-cols-2">
              <div className="flex justify-between gap-3"><span className="text-[#6B5C4E]">PayMongo payment</span><span className="font-mono text-[#3B2314]">{transaction.paymongo_payment_intent_id ?? '—'}</span></div>
              <div className="flex justify-between gap-3"><span className="text-[#6B5C4E]">Checkout session</span><span className="font-mono text-[#3B2314]">{transaction.checkout_session_id ?? '—'}</span></div>
              <div className="flex justify-between gap-3"><span className="text-[#6B5C4E]">GCash reference</span><span className="font-mono text-[#3B2314]">{transaction.gcash_reference_number ?? '—'}</span></div>
              <div className="flex justify-between gap-3"><span className="text-[#6B5C4E]">GCash transaction id</span><span className="font-mono text-[#3B2314]">{transaction.gcash_transaction_id ?? '—'}</span></div>
            </div>
          </div>

          {/* Event timeline */}
          <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
            <h3 className="mb-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              Webhook event timeline ({transaction.events_count})
            </h3>
            <EventTimeline events={transaction.events} />
          </div>
        </div>
      )}
    </Modal>
  )
}

export default function Transactions() {
  const reduce = useReducedMotion()
  const [searchParams, setSearchParams] = useSearchParams()
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [storeFilter, setStoreFilter] = useState('all')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [page, setPage] = useState(1)
  const [selected, setSelected] = useState(null)

  const { data, isLoading, isError, error } = useTransactions({
    status: statusFilter,
    dateFrom,
    dateTo,
  })

  const rows = data?.rows ?? []
  const feeColumnsAvailable = data?.feeColumnsAvailable ?? false
  const stores = data?.stores ?? []

  const filtered = useMemo(() => {
    let result = rows
    const q = search.trim().toLowerCase()
    if (q) {
      result = result.filter(
        (t) =>
          String(t.order_id).toLowerCase().includes(q) ||
          t.customer_name?.toLowerCase().includes(q) ||
          t.store_name?.toLowerCase().includes(q) ||
          (t.checkout_session_id ?? '').toLowerCase().includes(q) ||
          (t.gcash_reference_number ?? '').toLowerCase().includes(q),
      )
    }
    if (storeFilter !== 'all') {
      result = result.filter((t) => t.store_id === storeFilter)
    }
    return result
  }, [rows, search, storeFilter])

  const stats = useMemo(() => {
    const succeeded = filtered.filter((t) => t.status === 'succeeded')
    const totalPaid = succeeded.reduce((sum, t) => sum + (Number(t.amount) || 0), 0)
    let feeData = 0
    let feeCount = 0
    for (const t of filtered) {
      if (t.paymongo_fee_amount != null) {
        feeData += Number(t.paymongo_fee_amount)
        feeCount += 1
      }
    }
    const attention = filtered.filter(
      (t) => t.status === 'failed' || t.status === 'expired',
    ).length
    return {
      total: filtered.length,
      totalPaid,
      fees: feeCount > 0 ? feeData : null,
      attention,
    }
  }, [filtered])

  const cards = useMemo(
    () => [
      {
        key: 'total',
        icon: '💳',
        label: 'Transactions',
        iconBg: 'rgba(139,90,43,0.1)',
        iconColor: '#8B5A2B',
        value: <AnimatedNumber value={stats.total} format={(v) => Math.round(v).toLocaleString()} />,
      },
      {
        key: 'paid',
        icon: '💰',
        label: 'Total paid amount',
        iconBg: 'rgba(78,205,196,0.1)',
        iconColor: '#4ECDC4',
        value: <AnimatedNumber value={stats.totalPaid} format={moneyFormat} />,
      },
      {
        key: 'fees',
        icon: '🏦',
        label: 'PayMongo fees',
        iconBg: 'rgba(139,90,43,0.08)',
        iconColor: '#3B2314',
        value:
          stats.fees != null ? (
            <AnimatedNumber value={stats.fees} format={moneyFormat} />
          ) : (
            '—'
          ),
      },
      {
        key: 'attention',
        icon: '⚠️',
        label: 'Failed / expired',
        iconBg: 'rgba(214,69,69,0.1)',
        iconColor: '#D64545',
        highlight: stats.attention > 0,
        value: <AnimatedNumber value={stats.attention} format={(v) => Math.round(v).toLocaleString()} />,
      },
    ],
    [stats],
  )

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const pageRows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  // Deep link from Orders: /transactions?order=<orderId> opens that transaction.
  useEffect(() => {
    const orderId = searchParams.get('order')
    if (!orderId || isLoading || !rows.length) return
    const match = rows.find((t) => t.order_id === orderId)
    if (match) {
      setSelected(match)
      setSearchParams({}, { replace: true })
    }
  }, [searchParams, isLoading, rows, setSearchParams])

  useEffect(() => {
    setPage(1)
  }, [statusFilter, storeFilter, dateFrom, dateTo, search])

  const handleExport = () => {
    if (!filtered.length) return
    exportCsv(filtered)
  }

  const rowAnim = (i) => ({
    initial: reduce ? false : { opacity: 0, y: 6 },
    animate: { opacity: 1, y: 0 },
    exit: reduce ? undefined : { opacity: 0, y: 4 },
    transition: { duration: 0.18, delay: Math.min(i, 10) * 0.03, ease: 'easeOut' },
  })

  return (
    <div className="space-y-6">
      {/* Summary cards */}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {isLoading ? (
          Array.from({ length: 4 }).map((_, i) => (
            <motion.div
              key={i}
              initial={reduce ? false : { opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, delay: i * 0.05 }}
            >
              <StatCardSkeleton />
            </motion.div>
          ))
        ) : (
          cards.map((card, i) => (
            <motion.div
              key={card.key}
              initial={reduce ? false : { opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, delay: i * 0.06 }}
            >
              <StatCard
                icon={card.icon}
                label={card.label}
                highlight={card.highlight}
                iconBg={card.iconBg}
                iconColor={card.iconColor}
              >
                {card.value}
              </StatCard>
            </motion.div>
          ))
        )}
      </div>

      {/* Search & filter bar */}
      <div className="flex flex-wrap gap-3">
        <div className="relative min-w-52 flex-1">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#6B5C4E]" />
          <input
            type="search"
            placeholder="Search order, customer, store, ref…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-xl border border-[#D9D0C7] bg-white py-2.5 pl-9 pr-4 text-sm text-[#3B2314] placeholder-[#6B5C4E] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
        >
          <option value="all">All statuses</option>
          {PAYMENT_INTENT_STATUSES.map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </select>
        <select
          value={storeFilter}
          onChange={(e) => setStoreFilter(e.target.value)}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
        >
          <option value="all">All stores</option>
          {stores.map((s) => (
            <option key={s.id} value={s.id}>{s.name}</option>
          ))}
        </select>
        <input
          type="date"
          value={dateFrom}
          onChange={(e) => setDateFrom(e.target.value)}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
        />
        <input
          type="date"
          value={dateTo}
          onChange={(e) => setDateTo(e.target.value)}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
        />
        <button
          type="button"
          onClick={handleExport}
          disabled={!filtered.length}
          className="inline-flex items-center gap-2 rounded-xl border border-[#8B5A2B] px-4 py-2.5 text-sm font-semibold text-[#8B5A2B] transition-colors hover:bg-[#8B5A2B]/10 disabled:opacity-40"
        >
          <Download size={16} />
          Export CSV
        </button>
      </div>

      {isLoading && (
        <motion.div
          initial={reduce ? false : { opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.25 }}
        >
          <TableSkeleton cols={5} rows={8} />
        </motion.div>
      )}
      {isError && (
        <div className="rounded-2xl border border-[#D9D0C7] bg-white p-8 text-center">
          <p className="text-sm text-[#D64545]">{error.message}</p>
        </div>
      )}

      {!isLoading && !isError && (
        <>
          <div className="overflow-x-auto rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
            <table className="min-w-full text-left text-sm">
              <thead className="bg-[#F5F0EB]">
                <tr>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Date</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Order</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Customer</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Amount</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#F5F0EB]">
                {pageRows.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="p-0">
                      <EmptyState
                        icon="💳"
                        title="No transactions found"
                        description="Try adjusting your search or filters."
                      />
                    </td>
                  </tr>
                ) : (
                  <AnimatePresence initial={false}>
                    {pageRows.map((row, i) => (
                      <motion.tr
                        key={row.id}
                        {...rowAnim(i)}
                        whileHover={reduce ? undefined : { x: 3 }}
                        onClick={() => setSelected(row)}
                        className="group cursor-pointer transition-colors hover:bg-[#FBF8F5]"
                      >
                        <td className="px-6 py-4 text-[#6B5C4E]">
                          {formatDateTime(row.created_at)}
                        </td>
                        <td className="px-6 py-4 font-mono text-xs text-[#3B2314]">
                          {shortId(row.order_id)}
                        </td>
                        <td className="px-6 py-4">
                          <p className="text-[#3B2314]">{row.customer_name}</p>
                          <p className="text-xs text-[#6B5C4E]">{row.store_name}</p>
                        </td>
                        <td className="px-6 py-4">
                          <p className="font-mono text-base font-bold text-[#3B2314]">
                            {formatCurrency(row.amount)}
                          </p>
                          {row.paymongo_fee_amount != null && (
                            <p className="text-xs text-[#6B5C4E]">
                              net {formatCurrency(row.net_amount)}
                            </p>
                          )}
                        </td>
                        <td className="px-6 py-4">
                          <div className="flex items-center gap-1.5">
                            <StatusBadge rowId={row.id} status={row.status} />
                            <ArrowUpRight size={14} className="text-[#6B5C4E] opacity-0 transition-opacity group-hover:opacity-100" />
                          </div>
                        </td>
                      </motion.tr>
                    ))}
                  </AnimatePresence>
                )}
              </tbody>
            </table>
          </div>

          <div className="flex items-center justify-between text-sm">
            <span className="text-[#6B5C4E]">
              {filtered.length} transactions · Page {page} of {totalPages}
            </span>
            <div className="flex gap-2">
              <button
                type="button"
                disabled={page <= 1}
                onClick={() => setPage((p) => p - 1)}
                className="rounded-xl border border-[#D9D0C7] px-3 py-1 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] disabled:opacity-40"
              >
                Previous
              </button>
              <button
                type="button"
                disabled={page >= totalPages}
                onClick={() => setPage((p) => p + 1)}
                className="rounded-xl border border-[#D9D0C7] px-3 py-1 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] disabled:opacity-40"
              >
                Next
              </button>
            </div>
          </div>
        </>
      )}

      <TransactionDetail
        transaction={selected}
        feeColumnsAvailable={feeColumnsAvailable}
        onClose={() => setSelected(null)}
      />
    </div>
  )
}
