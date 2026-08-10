import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { AnimatePresence, motion, useReducedMotion } from 'motion/react'
import {
  AlertTriangle,
  ArrowUpRight,
  Banknote,
  Download,
  Landmark,
  Receipt,
  Search,
  SearchX,
  Wallet,
  X,
} from 'lucide-react'
import { Area, AreaChart, ResponsiveContainer } from 'recharts'
import Badge from '../components/ui/Badge.jsx'
import Modal from '../components/ui/Modal.jsx'
import StatCard from '../components/ui/StatCard.jsx'
import { StatCardSkeleton, TableSkeleton } from '../components/ui/Skeleton.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import AvatarInitials from '../components/ui/AvatarInitials.jsx'
import DateRangePicker from '../components/ui/DateRangePicker.jsx'
import { useTransactions } from '../hooks/useTransactions.js'
import { formatCurrency, formatDateTime, shortId } from '../lib/constants'

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

const STATUS_SEGMENTS = [
  { value: 'all', label: 'All', dot: 'bg-secondary' },
  { value: 'succeeded', label: 'Paid', dot: 'bg-accent' },
  { value: 'pending', label: 'Pending', dot: 'bg-pending' },
  { value: 'failed', label: 'Failed', dot: 'bg-error' },
  { value: 'expired', label: 'Expired', dot: 'bg-gray-400' },
  { value: 'cancelled', label: 'Cancelled', dot: 'bg-gray-300' },
]

const ROW_HOVER_ACCENT = {
  succeeded: 'hover:shadow-[inset_3px_0_0_#4ECDC4]',
  pending: 'hover:shadow-[inset_3px_0_0_#E8A020]',
  failed: 'hover:shadow-[inset_3px_0_0_#D64545]',
  expired: 'hover:shadow-[inset_3px_0_0_#9CA3AF]',
  cancelled: 'hover:shadow-[inset_3px_0_0_#D64545]',
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

function timeAgo(dateStr) {
  const diff = Date.now() - new Date(dateStr).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  const days = Math.floor(hrs / 24)
  if (days < 7) return `${days}d ago`
  if (days < 30) return `${Math.floor(days / 7)}w ago`
  if (days < 365) return `${Math.floor(days / 30)}mo ago`
  return `${Math.floor(days / 365)}y ago`
}

function parseISODate(str) {
  if (!str) return null
  const [y, m, d] = str.split('-').map(Number)
  return new Date(y, m - 1, d)
}

function toISODate(date) {
  if (!date) return ''
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
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

// ── Tiny sparkline for the "Total paid" card ─────────────────────────
function Sparkline({ data }) {
  if (!data || data.length < 2) return null
  return (
    <div className="h-10 w-24 shrink-0">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 2, right: 0, bottom: 0, left: 0 }}>
          <defs>
            <linearGradient id="sparkFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#4ECDC4" stopOpacity={0.35} />
              <stop offset="100%" stopColor="#4ECDC4" stopOpacity={0} />
            </linearGradient>
          </defs>
          <Area
            type="monotone"
            dataKey="value"
            stroke="#4ECDC4"
            strokeWidth={2}
            fill="url(#sparkFill)"
            isAnimationActive={false}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  )
}

// ── Status badge that pulses only when the status actually changes ───
function StatusBadge({ rowId, status }) {
  const reduce = useReducedMotion()
  const seen = useRef(new Map())
  const wasSeen = seen.current.has(rowId)
  const changed = wasSeen && seen.current.get(rowId) !== status
  seen.current.set(rowId, status)

  if (reduce || !changed) return <Badge label={status} variant={status} dot />

  return (
    <motion.span
      key={status}
      initial={{ scale: 1.18, opacity: 0.5 }}
      animate={{ scale: 1, opacity: 1 }}
      transition={{ type: 'spring', bounce: 0.1, duration: 0.45 }}
    >
      <Badge label={status} variant={status} dot />
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

  // Daily succeeded-amount series over the current filter period, for the
  // "Total paid" sparkline.
  const sparkData = useMemo(() => {
    const buckets = new Map()
    for (const t of filtered) {
      if (t.status !== 'succeeded' || !Number(t.amount)) continue
      const d = new Date(t.created_at)
      const key = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
      buckets.set(key, (buckets.get(key) ?? 0) + Number(t.amount))
    }
    return [...buckets.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([, value]) => ({ value: Math.round(value) }))
  }, [filtered])

  const cards = useMemo(
    () => [
      {
        key: 'total',
        label: 'Transactions',
        tone: 'primary',
        Icon: Wallet,
        value: <AnimatedNumber value={stats.total} format={(v) => Math.round(v).toLocaleString()} />,
      },
      {
        key: 'paid',
        label: 'Total paid amount',
        tone: 'accent',
        Icon: Banknote,
        sparkline: <Sparkline data={sparkData} />,
        value: <AnimatedNumber value={stats.totalPaid} format={moneyFormat} />,
      },
      {
        key: 'fees',
        label: 'PayMongo fees',
        tone: 'neutral',
        Icon: Landmark,
        value:
          stats.fees != null ? (
            <AnimatedNumber value={stats.fees} format={moneyFormat} />
          ) : (
            '—'
          ),
      },
      {
        key: 'attention',
        label: 'Failed / expired',
        tone: 'error',
        Icon: AlertTriangle,
        highlight: stats.attention > 0,
        value: <AnimatedNumber value={stats.attention} format={(v) => Math.round(v).toLocaleString()} />,
      },
    ],
    [stats, sparkData],
  )

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const pageRows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const filtersActive = Boolean(
    search.trim() || statusFilter !== 'all' || storeFilter !== 'all' || dateFrom || dateTo,
  )

  const clearAllFilters = () => {
    setSearch('')
    setStatusFilter('all')
    setStoreFilter('all')
    setDateFrom('')
    setDateTo('')
  }

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
                label={card.label}
                tone={card.tone}
                Icon={card.Icon}
                highlight={card.highlight}
                sparkline={card.sparkline}
              >
                {card.value}
              </StatCard>
            </motion.div>
          ))
        )}
      </div>

      {/* Filter panel */}
      <div className="rounded-2xl border border-[#D9D0C7] bg-white p-4 shadow-sm">
        <div className="flex flex-wrap items-center gap-3">
          {/* Status segmented control */}
          <div className="flex items-center gap-1 rounded-full border border-[#D9D0C7] bg-[#F5F0EB] p-1">
            {STATUS_SEGMENTS.map((s) => {
              const active = statusFilter === s.value
              return (
                <button
                  key={s.value}
                  type="button"
                  onClick={() => setStatusFilter(s.value)}
                  className={`flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold transition-all ${
                    active
                      ? 'bg-white text-secondary shadow-sm'
                      : 'text-[#6B5C4E] hover:text-secondary'
                  }`}
                >
                  <span className={`h-1.5 w-1.5 rounded-full ${s.dot} ${active ? '' : 'opacity-50'}`} />
                  {s.label}
                </button>
              )
            })}
          </div>

          <div className="ml-auto flex flex-wrap items-center gap-3">
            <select
              value={storeFilter}
              onChange={(e) => setStoreFilter(e.target.value)}
              className="rounded-full border border-[#D9D0C7] bg-white px-4 py-2 text-sm font-medium text-[#3B2314] outline-none transition-colors focus:border-primary"
            >
              <option value="all">All stores</option>
              {stores.map((s) => (
                <option key={s.id} value={s.id}>{s.name}</option>
              ))}
            </select>
            <DateRangePicker
              from={parseISODate(dateFrom)}
              to={parseISODate(dateTo)}
              onChange={(from, to) => {
                setDateFrom(toISODate(from))
                setDateTo(toISODate(to))
              }}
            />
            <button
              type="button"
              onClick={handleExport}
              disabled={!filtered.length}
              className="inline-flex items-center gap-2 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-white shadow-sm transition-all hover:bg-secondary hover:shadow-md disabled:opacity-40"
            >
              <Download size={16} />
              Export CSV
            </button>
          </div>
        </div>

        {/* Search */}
        <div className="relative mt-3">
          <Search size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-[#6B5C4E]" />
          <input
            type="search"
            placeholder="Search order, customer, store, ref…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-xl border border-[#D9D0C7] bg-[#FBF8F5] py-2.5 pl-10 pr-10 text-sm text-[#3B2314] placeholder-[#6B5C4E] outline-none transition-all focus:border-primary focus:bg-white focus:ring-2 focus:ring-primary/20"
          />
          {search && (
            <button
              type="button"
              onClick={() => setSearch('')}
              className="absolute right-3 top-1/2 -translate-y-1/2 rounded-full p-1 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] hover:text-[#3B2314]"
            >
              <X size={14} />
            </button>
          )}
        </div>
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
              <thead className="bg-[#FBF8F5]">
                <tr>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Date</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Customer</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Order</th>
                  <th className="px-6 py-4 text-right text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Amount</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#F5F0EB]">
                {pageRows.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="p-0">
                      <EmptyState
                        Icon={rows.length === 0 && !filtersActive ? Receipt : SearchX}
                        title={
                          rows.length === 0 && !filtersActive
                            ? 'No transactions yet'
                            : 'No matches'
                        }
                        description={
                          rows.length === 0 && !filtersActive
                            ? 'GCash payments will show up here as customers place orders online.'
                            : 'No transactions match the current search and filters.'
                        }
                        action={
                          filtersActive ? (
                            <button
                              type="button"
                              onClick={clearAllFilters}
                              className="mt-4 rounded-full bg-primary px-4 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-secondary"
                            >
                              Clear filters
                            </button>
                          ) : undefined
                        }
                      />
                    </td>
                  </tr>
                ) : (
                  <AnimatePresence initial={false}>
                    {pageRows.map((row, i) => (
                      <motion.tr
                        key={row.id}
                        {...rowAnim(i)}
                        onClick={() => setSelected(row)}
                        className={`group cursor-pointer transition-all hover:bg-[#FBF8F5] ${
                          ROW_HOVER_ACCENT[row.status] ?? 'hover:shadow-[inset_3px_0_0_#8B5A2B]'
                        }`}
                      >
                        <td className="px-6 py-4 align-middle">
                          <p className="text-sm font-medium text-[#3B2314]">{timeAgo(row.created_at)}</p>
                          <p className="text-xs text-[#6B5C4E]" title={formatDateTime(row.created_at)}>
                            {formatDateTime(row.created_at)}
                          </p>
                        </td>
                        <td className="px-6 py-4 align-middle">
                          <div className="flex items-center gap-3">
                            <AvatarInitials name={row.customer_name} email={row.customer_email} />
                            <div>
                              <p className="font-medium text-[#3B2314]">{row.customer_name}</p>
                              <p className="text-xs text-[#6B5C4E]">{row.store_name}</p>
                            </div>
                          </div>
                        </td>
                        <td className="px-6 py-4 align-middle font-mono text-xs text-[#6B5C4E]">
                          {shortId(row.order_id)}
                        </td>
                        <td className="px-6 py-4 text-right align-middle">
                          <p className="font-mono text-base font-bold text-[#3B2314]">
                            {formatCurrency(row.amount)}
                          </p>
                          {row.paymongo_fee_amount != null && (
                            <p className="text-xs text-[#6B5C4E]">
                              net {formatCurrency(row.net_amount)}
                            </p>
                          )}
                        </td>
                        <td className="px-6 py-4 align-middle">
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
