import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { AnimatePresence, motion, useReducedMotion } from 'motion/react'
import {
  ArrowUpRight,
  Banknote,
  CalendarDays,
  Copy,
  Download,
  Globe,
  Printer,
  Receipt,
  Search,
  SearchX,
  Store,
  Wallet,
  X,
} from 'lucide-react'
import { Area, AreaChart, ResponsiveContainer } from 'recharts'

import SaleReceiptModal from '../components/payments/SaleReceiptModal.jsx'
import ReceiptDelivery from './Receipts.jsx'
import AnimatedNumber from '../components/ui/AnimatedNumber.jsx'
import AvatarInitials from '../components/ui/AvatarInitials.jsx'
import Badge from '../components/ui/Badge.jsx'
import ContextMenu from '../components/ui/ContextMenu.jsx'
import DateRangePicker from '../components/ui/DateRangePicker.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import Skeleton, { TableSkeleton } from '../components/ui/Skeleton.jsx'
import StatCard from '../components/ui/StatCard.jsx'
import Tooltip from '../components/ui/Tooltip.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import { useTransactions } from '../hooks/useTransactions.js'
import { formatCurrency, formatDateTime, shortId } from '../lib/constants'
import { asReceiptOrder, printReceipt } from '../lib/receipt.js'
import { receiptAddress, receiptRowState } from '../lib/receiptTrail.js'
import { channelLabel, matchesSaleSearch, methodLabel } from '../lib/saleFields.js'

const PAGE_SIZE = 20

/**
 * Did the customer get their copy? The row says it in one line — the badge is
 * the state, the line underneath is the address and time (or the reason it has
 * not gone out), using the same states as the Receipt delivery tab so the two
 * views can never disagree.
 */
function receiptCell(sale, now) {
  const { state, meta } = receiptRowState(sale, now)

  if (state === 'no_email') {
    return { meta, text: 'no address to send a copy to' }
  }

  if (state === 'sent') {
    const to = receiptAddress(sale)
    const at = formatDateTime(sale.receipt_emailed_at)
    return { meta, text: to ? `to ${to} · ${at}` : `emailed ${at}`, title: `${to || 'Customer'} · ${at}` }
  }
  if (state === 'retrying') {
    return {
      meta,
      text: sale.receipt_email_next_attempt_at
        ? `next try ${formatDateTime(sale.receipt_email_next_attempt_at)}`
        : 'retry queued',
    }
  }
  if (state === 'failed') {
    return {
      meta,
      text: sale.receipt_email_last_error || 'The last send failed',
      title: sale.receipt_email_last_error || 'The last send failed',
    }
  }
  if (state === 'sending') return { meta, text: 'a send is in flight now' }
  return { meta, text: 'no receipt has gone out yet' }
}

function escCsv(value) {
  const s = String(value ?? '')
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

function exportCsv(rows) {
  const header = [
    'Order code', 'Store', 'Customer', 'Customer email', 'Amount (PHP)',
    'Payment method', 'Channel', 'Order status', 'Paid at', 'GCash reference',
    'GCash transaction', 'PayMongo payment', 'Receipt', 'Receipt emailed at',
    'Receipt sent to', 'Created at',
  ]
  const lines = rows.map((r) =>
    [
      r.order_code || shortId(r.order_id), r.store_name, r.customer_name,
      r.customer_email, r.amount, methodLabel(r.method), channelLabel(r.source),
      r.order_status, r.paid_at ?? '', r.gcash_reference_number ?? '',
      r.gcash_transaction_id ?? '', r.intent?.paymongo_payment_intent_id ?? '',
      receiptRowState(r).meta?.label ?? '', r.receipt_emailed_at ?? '',
      r.receipt_email_to ?? '', r.created_at,
    ]
      .map(escCsv)
      .join(','),
  )
  const csv = `\uFEFF${[header.join(','), ...lines].join('\n')}`
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `paid-sales-${new Date().toISOString().slice(0, 10)}.csv`
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

/**
 * Transactions — every sale whose money actually arrived.
 *
 * One row per paid order, whichever channel took the payment: a counter sale is
 * here the moment the cashier closes it, and an online order is here once its
 * payment is confirmed. Unpaid, pending and abandoned checkouts are not sales,
 * so they are not on this page — the status filters that used to live here only
 * existed to hide them.
 */
export default function Transactions() {
  const reduce = useReducedMotion()
  const [searchParams, setSearchParams] = useSearchParams()
  const [search, setSearch] = useState('')
  const [storeFilter, setStoreFilter] = useState('all')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [page, setPage] = useState(1)
  const [selected, setSelected] = useState(null)
  const [menu, setMenu] = useState(null)
  const { showToast } = useToast()

  const { data, isLoading, isError, error } = useTransactions({ dateFrom, dateTo })

  const rows = data?.rows ?? []
  const stores = data?.stores ?? []

  const filtered = useMemo(() => {
    const searched = search.trim()
      ? rows.filter((sale) => matchesSaleSearch(sale, search))
      : rows
    if (storeFilter === 'all') return searched
    return searched.filter((sale) => sale.store_id === storeFilter)
  }, [rows, search, storeFilter])

  const stats = useMemo(() => {
    const totalPaid = filtered.reduce((sum, sale) => sum + (Number(sale.amount) || 0), 0)
    const walkIn = filtered.filter((sale) => (sale.source ?? '') === 'pos').length
    const online = filtered.length - walkIn
    return { total: filtered.length, totalPaid, walkIn, online }
  }, [filtered])

  // Daily paid-amount series over the current period, for the sparkline.
  const sparkData = useMemo(() => {
    const buckets = new Map()
    for (const sale of filtered) {
      if (!Number(sale.amount)) continue
      const d = new Date(sale.created_at)
      const key = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
      buckets.set(key, (buckets.get(key) ?? 0) + Number(sale.amount))
    }
    return [...buckets.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([, value]) => ({ value: Math.round(value) }))
  }, [filtered])

  const cards = useMemo(
    () => [
      {
        key: 'total',
        label: 'Paid sales',
        value: (
          <AnimatedNumber value={stats.total} format={(v) => Math.round(v).toLocaleString()} />
        ),
        caption: 'POS and online, in current filters',
      },
      {
        key: 'paid',
        label: 'Total paid amount',
        sparkline: <Sparkline data={sparkData} />,
        value: <AnimatedNumber value={stats.totalPaid} format={moneyFormat} />,
        caption: 'money that actually arrived',
      },
      {
        key: 'walkin',
        label: 'Walk-in',
        value: (
          <AnimatedNumber value={stats.walkIn} format={(v) => Math.round(v).toLocaleString()} />
        ),
        caption: 'rung up at the POS',
      },
      {
        key: 'online',
        label: 'Online',
        value: (
          <AnimatedNumber value={stats.online} format={(v) => Math.round(v).toLocaleString()} />
        ),
        caption: 'paid through the app',
      },
    ],
    [stats, sparkData],
  )

  // One clock for the whole render, so two rows cannot disagree about whether a
  // send is still in flight.
  const now = Date.now()

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const pageRows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const filtersActive = Boolean(search.trim() || storeFilter !== 'all' || dateFrom || dateTo)

  const clearAllFilters = () => {
    setSearch('')
    setStoreFilter('all')
    setDateFrom('')
    setDateTo('')
  }

  // Deep link from Orders: /transactions?order=<orderId> opens that sale.
  useEffect(() => {
    const orderId = searchParams.get('order')
    if (!orderId || isLoading || !rows.length) return
    if (searchParams.get('tab') === 'delivery') return
    const match = rows.find((sale) => sale.order_id === orderId || sale.order_code === orderId)
    if (match) {
      setSelected(match)
      setSearchParams({}, { replace: true })
    }
  }, [searchParams, isLoading, rows, setSearchParams])

  useEffect(() => {
    setPage(1)
  }, [storeFilter, dateFrom, dateTo, search])

  const handleExport = () => {
    if (!filtered.length) return
    exportCsv(filtered)
  }

  // ── Row actions (right-click) ──────────────────────────────────────
  // The same three ways into a receipt the modal offers, plus the two things
  // an admin does with a row while reading it: take its identifiers, or narrow
  // the ledger to this shop or this day.
  const copyText = async (text, what) => {
    try {
      await navigator.clipboard.writeText(String(text))
      showToast(`${what} copied`)
    } catch {
      showToast('Could not copy to the clipboard', 'error')
    }
  }

  const printSale = (sale) => {
    if (!printReceipt(asReceiptOrder(sale))) {
      showToast('Allow pop-ups for this site to print the receipt', 'error')
    }
  }

  const downloadSale = async (sale) => {
    try {
      const { downloadReceiptPdf } = await import('../lib/receiptPdf.js')
      showToast(`Saved ${downloadReceiptPdf(asReceiptOrder(sale))}`)
    } catch (err) {
      showToast(err?.message ?? 'Could not build the receipt PDF', 'error')
    }
  }

  const openMenu = (event, sale) => {
    event.preventDefault()
    setMenu({ x: event.clientX, y: event.clientY, sale })
  }

  const menuItems = menu
    ? [
        { label: 'Open sale details', icon: Receipt, onSelect: () => setSelected(menu.sale) },
        { label: 'Print receipt', icon: Printer, onSelect: () => printSale(menu.sale) },
        { label: 'Download PDF', icon: Download, onSelect: () => downloadSale(menu.sale) },
        { separator: true },
        {
          label: 'Copy order code',
          icon: Copy,
          onSelect: () =>
            copyText(menu.sale.order_code || shortId(menu.sale.order_id), 'Order code'),
        },
        menu.sale.customer_email
          ? {
              label: 'Copy customer email',
              icon: Copy,
              onSelect: () => copyText(menu.sale.customer_email, 'Customer email'),
            }
          : null,
        menu.sale.proof?.reference_number || menu.sale.gcash_reference_number
          ? {
              label: 'Copy GCash reference',
              icon: Copy,
              onSelect: () =>
                copyText(
                  menu.sale.proof?.reference_number ?? menu.sale.gcash_reference_number,
                  'GCash reference',
                ),
            }
          : null,
        { separator: true },
        stores.some((store) => store.id === menu.sale.store_id)
          ? {
              label: 'Show only this store',
              icon: Store,
              onSelect: () => setStoreFilter(menu.sale.store_id),
            }
          : null,
        {
          label: 'Show only this day',
          icon: CalendarDays,
          onSelect: () => {
            const day = toISODate(new Date(menu.sale.created_at))
            setDateFrom(day)
            setDateTo(day)
          },
        },
      ].filter(Boolean)
    : []

  const rowAnim = (i) => ({
    initial: reduce ? false : { opacity: 0, y: 6 },
    animate: { opacity: 1, y: 0 },
    exit: reduce ? undefined : { opacity: 0, y: 4 },
    transition: { duration: 0.18, delay: Math.min(i, 10) * 0.03, ease: 'easeOut' },
  })

  // One page, two questions: what we sold (the ledger) and whether each
  // customer actually has their receipt (the delivery trail, which used to be
  // its own page). Both read sales, so they belong behind one nav entry.
  const tab = searchParams.get('tab') === 'delivery' ? 'delivery' : 'sales'
  const switchTab = (next) => {
    const params = new URLSearchParams(searchParams)
    if (next === 'delivery') params.set('tab', 'delivery')
    else params.delete('tab')
    setSearchParams(params, { replace: true })
    setPage(1)
  }

  return (
    <div className="space-y-4">
      <div
        role="tablist"
        aria-label="Transactions views"
        className="flex w-fit flex-wrap items-center gap-1 rounded-xl border border-border bg-card p-1"
      >
        {[
          {
            key: 'sales',
            label: 'Paid sales',
            count: rows.length || null,
            hint: 'One row per sale whose money actually arrived — POS and online.',
          },
          {
            key: 'delivery',
            label: 'Receipt delivery',
            hint: 'Whether each customer got their emailed copy, and any send still retrying.',
          },
        ].map((option) => {
          const active = tab === option.key
          return (
            <Tooltip key={option.key} label={option.hint}>
              <button
                type="button"
                role="tab"
                aria-selected={active}
                onClick={() => switchTab(option.key)}
                className={`inline-flex h-9 items-center gap-2 rounded-lg px-3.5 text-[12.5px] font-semibold transition-colors ${
                  active ? 'bg-secondary text-white' : 'text-muted hover:text-ink'
                }`}
              >
                {option.label}
                {option.count != null && (
                  <span
                    className={`tnum rounded-full px-1.5 py-0.5 text-[10.5px] ${
                      active ? 'bg-white/15 text-white' : 'bg-canvas text-muted'
                    }`}
                  >
                    {option.count}
                  </span>
                )}
              </button>
            </Tooltip>
          )
        })}
      </div>

      {tab === 'delivery' ? (
        <ReceiptDelivery />
      ) : (
        <>
      <section
        aria-label="Paid sale summaries"
        className="grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-border bg-border xl:grid-cols-4"
      >
        {isLoading ? (
          Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="bg-card p-5">
              <Skeleton className="mb-3 h-9 w-9 rounded-xl" />
              <Skeleton className="mb-2 h-8 w-20" />
              <Skeleton className="h-4 w-28" />
            </div>
          ))
        ) : (
          cards.map((card, i) => (
            <motion.div
              key={card.key}
              className="bg-card"
              initial={reduce ? false : { opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, delay: i * 0.06 }}
            >
              <StatCard
                bare
                label={card.label}
                value={card.value}
                caption={card.caption}
                sparkline={card.sparkline}
              />
            </motion.div>
          ))
        )}
      </section>

      <div className="rounded-xl border border-border bg-card p-4">
        <div className="flex flex-wrap items-center gap-3">
          <p className="text-[12.5px] font-medium text-muted">
            Showing paid sales only — pending, unpaid and abandoned checkouts stay out
            of this list.
          </p>
          <div className="ml-auto flex flex-wrap items-center gap-3">
            <Tooltip label="Show one store only.">
              <select
                value={storeFilter}
                onChange={(e) => setStoreFilter(e.target.value)}
                aria-label="Filter by store"
                className="rounded-full border border-border bg-card px-4 py-2 text-sm font-medium text-ink outline-none transition-colors focus:border-primary"
              >
                <option value="all">All stores</option>
                {stores.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </Tooltip>
            <Tooltip label="Limit the ledger to sales placed in this date range.">
              <DateRangePicker
                from={parseISODate(dateFrom)}
                to={parseISODate(dateTo)}
                onChange={(from, to) => {
                  setDateFrom(toISODate(from))
                  setDateTo(toISODate(to))
                }}
              />
            </Tooltip>
            <Tooltip label="Download every sale currently in view as a CSV file.">
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
            placeholder="Search anything — code, customer, store, item, size, amount, GCash ref, date…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
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

        {filtersActive && (
          <div className="mt-3 flex items-center justify-between text-xs text-muted">
            <span className="tnum">
              {filtered.length} of {rows.length} match
            </span>
            <Tooltip label="Clear the search, store and date filters.">
              <button
                type="button"
                onClick={clearAllFilters}
                className="rounded-full px-2 py-1 font-semibold text-primary transition-colors hover:bg-canvas"
              >
                Reset filters
              </button>
            </Tooltip>
          </div>
        )}
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
        <div className="rounded-xl border border-border bg-card p-8 text-center">
          <p className="text-sm text-error">{error.message}</p>
        </div>
      )}

      {!isLoading && !isError && (
        <>
          <div className="overflow-x-auto rounded-xl border border-border bg-card">
            <table className="min-w-full text-left text-sm">
              <caption className="sr-only">
                Paid sales with date, customer, order, amount and whether the customer received the receipt email
              </caption>
              <thead className="bg-canvas">
                <tr>
                  <th scope="col" className="px-6 py-4 text-[12px] font-medium text-muted">
                    <Tooltip label="When the sale was placed, not when the money arrived.">Date</Tooltip>
                  </th>
                  <th scope="col" className="px-6 py-4 text-[12px] font-medium text-muted">
                    <Tooltip label="Who bought it, and the store that sold it.">Customer</Tooltip>
                  </th>
                  <th scope="col" className="px-6 py-4 text-[12px] font-medium text-muted">
                    <Tooltip label="Order code, and whether it was rung up at the counter or paid in the app.">Order</Tooltip>
                  </th>
                  <th scope="col" className="px-6 py-4 text-right text-[12px] font-medium text-muted">
                    <Tooltip label="Total paid, and how it was paid.">Amount</Tooltip>
                  </th>
                  <th scope="col" className="px-6 py-4 text-[12px] font-medium text-muted">
                    <Tooltip label="Whether the customer's emailed copy actually went out.">Receipt</Tooltip>
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-canvas">
                {pageRows.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="p-0">
                      <EmptyState
                        Icon={rows.length === 0 && !filtersActive ? Receipt : SearchX}
                        title={rows.length === 0 && !filtersActive ? 'No paid sales yet' : 'No matches'}
                        description={
                          rows.length === 0 && !filtersActive
                            ? 'A sale appears here once its money has arrived — a POS sale as soon as the cashier closes it, an online order once its payment is confirmed. Pending and unpaid orders stay in Orders.'
                            : 'No paid sales match the current search and filters.'
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
                    {pageRows.map((row, i) => {
                      const receipt = receiptCell(row, now)
                      return (
                      <motion.tr
                        key={row.id}
                        {...rowAnim(i)}
                        onClick={() => setSelected(row)}
                        onContextMenu={(event) => openMenu(event, row)}
                        className="admin-list-item admin-list-row group cursor-pointer"
                      >
                        <td className="px-6 py-4 align-middle">
                          <p className="text-sm font-medium text-ink">{timeAgo(row.created_at)}</p>
                          <p className="text-xs text-muted" title={formatDateTime(row.created_at)}>
                            {formatDateTime(row.created_at)}
                          </p>
                        </td>
                        <td className="px-6 py-4 align-middle">
                          <div className="flex items-center gap-3">
                            <AvatarInitials
                              name={row.customer_name}
                              email={row.customer_email}
                              src={row.customer_avatar_url}
                            />
                            <div>
                              <p className="font-medium text-ink">{row.customer_name}</p>
                              <p className="text-xs text-muted">{row.store_name}</p>
                            </div>
                          </div>
                        </td>
                        <td className="px-6 py-4 align-middle">
                          <Tooltip label={`Order ${row.order_id}`}>
                            <p className="tnum font-mono text-xs text-muted">
                              {row.order_code || shortId(row.order_id)}
                            </p>
                          </Tooltip>
                          <p className="mt-0.5 text-xs text-muted">
                            {channelLabel(row.source)}
                          </p>
                        </td>
                        <td className="px-6 py-4 text-right align-middle">
                          <p className="tnum font-mono text-base font-bold text-ink">
                            {formatCurrency(row.amount)}
                          </p>
                          <p className="text-xs text-muted">{methodLabel(row.method)}</p>
                        </td>
                        <td className="px-6 py-4 align-middle">
                          <div className="flex items-start gap-1.5">
                            <div className="min-w-0">
                              <Tooltip label={receipt.meta.hint}>
                                <Badge label={receipt.meta.label} variant={receipt.meta.tone} dot />
                              </Tooltip>
                              <p
                                className="mt-1 max-w-[210px] truncate text-[11.5px] text-muted"
                                title={receipt.title || receipt.text}
                              >
                                {receipt.text}
                              </p>
                            </div>
                            <ArrowUpRight
                              size={14}
                              className="mt-1 shrink-0 text-muted opacity-0 transition-opacity group-hover:opacity-100"
                            />
                          </div>
                        </td>
                      </motion.tr>
                      )
                    })}
                  </AnimatePresence>
                )}
              </tbody>
            </table>
          </div>

          <div className="flex items-center justify-between text-sm">
            <span className="tnum text-muted">
              {filtered.length} paid sale{filtered.length === 1 ? '' : 's'} · Page {page} of{' '}
              {totalPages}
            </span>
            <div className="flex gap-2">
              <button
                type="button"
                disabled={page <= 1}
                onClick={() => setPage((p) => p - 1)}
                className="rounded-xl border border-border px-3 py-1 text-muted transition-colors hover:bg-canvas disabled:opacity-40"
              >
                Previous
              </button>
              <button
                type="button"
                disabled={page >= totalPages}
                onClick={() => setPage((p) => p + 1)}
                className="rounded-xl border border-border px-3 py-1 text-muted transition-colors hover:bg-canvas disabled:opacity-40"
              >
                Next
              </button>
            </div>
          </div>
        </>
      )}

      <ContextMenu
        position={menu ? { x: menu.x, y: menu.y } : null}
        items={menuItems}
        onClose={() => setMenu(null)}
        label="Sale actions"
      />

      <SaleReceiptModal sale={selected} onClose={() => setSelected(null)} />
        </>
      )}
    </div>
  )
}
