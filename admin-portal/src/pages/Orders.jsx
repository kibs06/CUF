import { useEffect, useMemo, useRef, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import {
  ArrowRight,
  ArrowUpRight,
  ChevronLeft,
  ChevronRight,
  Copy,
  Eye,
  Mail,
  Package,
  Search,
  SearchX,
  ShoppingBag,
  X,
} from 'lucide-react'
import AvatarInitials from '../components/ui/AvatarInitials.jsx'
import Badge from '../components/ui/Badge.jsx'
import Modal from '../components/ui/Modal.jsx'
import { TableSkeleton } from '../components/ui/Skeleton.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import { useOrders, useUpdateOrderStatus } from '../hooks/useOrders.js'
import { formatDate, formatCurrency, formatDateTime, shortId, ORDER_STATUSES } from '../lib/constants'

const PAGE_SIZE = 20

// Dashboard pipeline slugs map onto the real order statuses, so a click on
// "Needs action" shows pending + placed + confirmed instead of just pending.
// Anything else filters by exact status; unknown values fall back to 'all'.
const STATUS_GROUPS = {
  pending: ['pending', 'placed', 'confirmed'],
  preparing: ['preparing', 'ready'],
  shipped: ['shipped'],
  delivered: ['received', 'delivered'],
}

const PIPELINE = [
  { key: 'all', label: 'All orders' },
  { key: 'pending', label: 'Needs action' },
  { key: 'preparing', label: 'Preparing' },
  { key: 'shipped', label: 'Shipped' },
  { key: 'delivered', label: 'Delivered' },
]

// The next meaningful step for a quick action. Exact in-between statuses
// remain available in the order modal; this is only the pipeline move.
const QUICK_NEXT_STATUS = {
  pending: { value: 'preparing', label: 'Move to preparing' },
  placed: { value: 'preparing', label: 'Move to preparing' },
  confirmed: { value: 'preparing', label: 'Move to preparing' },
  preparing: { value: 'shipped', label: 'Move to shipped' },
  ready: { value: 'shipped', label: 'Move to shipped' },
  shipped: { value: 'received', label: 'Mark as received' },
  received: { value: 'delivered', label: 'Mark as delivered' },
}

const KNOWN_STATUS_FILTERS = new Set([
  'all',
  ...Object.keys(STATUS_GROUPS),
  ...ORDER_STATUSES,
])

// Group filters take precedence over the individual status with the same name.
const EXACT_STATUSES = ORDER_STATUSES.filter((status) => !STATUS_GROUPS[status])

function matchesStatus(orderStatus, filter) {
  if (!filter || filter === 'all') return true
  const group = STATUS_GROUPS[filter]
  if (group) return group.includes(orderStatus)
  return orderStatus === filter
}

function humanizeStatus(value) {
  return String(value ?? '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase())
}

function nextStatusFor(status) {
  return QUICK_NEXT_STATUS[String(status ?? '').toLowerCase()] ?? null
}

function formatClock(value) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return date.toLocaleTimeString('en-PH', { hour: 'numeric', minute: '2-digit' })
}

function dateBoundary(value, endOfDay = false) {
  const [year, month, day] = String(value).split('-').map(Number)
  if (!year || !month || !day) return null
  return new Date(
    year,
    month - 1,
    day,
    endOfDay ? 23 : 0,
    endOfDay ? 59 : 0,
    endOfDay ? 59 : 0,
    endOfDay ? 999 : 0,
  )
}

function productThumb(item) {
  const images = item.products?.product_images ?? []
  return [...images].sort(
    (a, b) => (a.display_order ?? 0) - (b.display_order ?? 0),
  )[0]?.image_url ?? null
}

function PipelineSkeleton({ wide = false }) {
  return (
    <div className={`bg-card px-3.5 py-3.5 ${wide ? 'col-span-2 sm:col-span-1' : ''}`}>
      <div className="h-3 w-20 animate-pulse rounded bg-canvas" />
      <div className="mt-2 h-6 w-12 animate-pulse rounded bg-canvas" />
    </div>
  )
}

function ContextMenuItem({ icon: Icon, children, onClick }) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onClick}
      className="flex w-full items-center gap-2.5 px-3 py-2 text-left text-[12px] text-muted transition-colors hover:bg-canvas hover:text-ink"
    >
      <Icon size={14} strokeWidth={1.7} aria-hidden="true" />
      {children}
    </button>
  )
}

export default function Orders() {
  const { showToast } = useToast()
  const { data, isLoading, isError, error } = useOrders()
  const updateStatus = useUpdateOrderStatus()
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()

  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState(() => {
    const initial = searchParams.get('status') ?? 'all'
    return KNOWN_STATUS_FILTERS.has(initial) ? initial : 'all'
  })
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [page, setPage] = useState(1)
  const [selectedOrder, setSelectedOrder] = useState(null)
  const [newStatus, setNewStatus] = useState('')
  const [saving, setSaving] = useState(false)
  const [contextMenu, setContextMenu] = useState(null)
  const contextMenuRef = useRef(null)

  // Stay in sync when arriving via a dashboard pipeline link (or back/forward)
  // while already on this page — the URL is the source of truth for status.
  useEffect(() => {
    const fromUrl = searchParams.get('status') ?? 'all'
    const next = KNOWN_STATUS_FILTERS.has(fromUrl) ? fromUrl : 'all'
    setStatusFilter((previous) => (previous === next ? previous : next))
    setPage(1)
  }, [searchParams])

  useEffect(() => {
    if (!contextMenu) return undefined

    const closeOnOutsidePointer = (event) => {
      if (!contextMenuRef.current?.contains(event.target)) setContextMenu(null)
    }
    const closeOnEscape = (event) => {
      if (event.key === 'Escape') setContextMenu(null)
    }
    const closeOnViewportChange = () => setContextMenu(null)

    document.addEventListener('pointerdown', closeOnOutsidePointer)
    document.addEventListener('keydown', closeOnEscape)
    window.addEventListener('scroll', closeOnViewportChange, true)
    window.addEventListener('resize', closeOnViewportChange)

    return () => {
      document.removeEventListener('pointerdown', closeOnOutsidePointer)
      document.removeEventListener('keydown', closeOnEscape)
      window.removeEventListener('scroll', closeOnViewportChange, true)
      window.removeEventListener('resize', closeOnViewportChange)
    }
  }, [contextMenu])

  const applyStatus = (value) => {
    const next = KNOWN_STATUS_FILTERS.has(value) ? value : 'all'
    setStatusFilter(next)
    setPage(1)
    setSearchParams(next === 'all' ? {} : { status: next }, { replace: true })
  }

  // Search and date filters form the visible base; the status filter narrows
  // that base without changing the pipeline counts beside it.
  const baseRows = useMemo(() => {
    let rows = data ?? []
    const query = search.trim().toLowerCase()

    if (query) {
      rows = rows.filter((order) => {
        const itemNames = (order.order_items ?? [])
          .map((item) => item.product_name ?? '')
          .join(' ')
          .toLowerCase()

        return [
          String(order.id),
          order.customer_name,
          order.customer_email,
          order.store_name,
          itemNames,
        ].some((value) => String(value ?? '').toLowerCase().includes(query))
      })
    }

    if (dateFrom) {
      const from = dateBoundary(dateFrom)
      if (from) rows = rows.filter((order) => new Date(order.created_at) >= from)
    }

    if (dateTo) {
      const to = dateBoundary(dateTo, true)
      if (to) rows = rows.filter((order) => new Date(order.created_at) <= to)
    }

    return rows
  }, [data, search, dateFrom, dateTo])

  const filtered = useMemo(() => {
    if (statusFilter === 'all') return baseRows
    return baseRows.filter((order) => matchesStatus(order.status, statusFilter))
  }, [baseRows, statusFilter])

  const summary = useMemo(
    () => ({
      total: baseRows.length,
      pending: baseRows.filter((order) => matchesStatus(order.status, 'pending')).length,
      preparing: baseRows.filter((order) => matchesStatus(order.status, 'preparing')).length,
      shipped: baseRows.filter((order) => matchesStatus(order.status, 'shipped')).length,
      delivered: baseRows.filter((order) => matchesStatus(order.status, 'delivered')).length,
    }),
    [baseRows],
  )

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const pageRows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)
  const rangeStart = filtered.length === 0 ? 0 : (page - 1) * PAGE_SIZE + 1
  const rangeEnd = Math.min(page * PAGE_SIZE, filtered.length)

  const filtersActive = Boolean(
    search.trim() || statusFilter !== 'all' || dateFrom || dateTo,
  )

  const clearFilters = () => {
    setSearch('')
    setDateFrom('')
    setDateTo('')
    setStatusFilter('all')
    setPage(1)
    setSearchParams({}, { replace: true })
  }

  const openOrder = (order) => {
    setSelectedOrder(order)
    setNewStatus(order.status)
  }

  const closeOrder = () => {
    setSelectedOrder(null)
    setNewStatus('')
  }

  const openContextMenu = (event, order) => {
    event.preventDefault()
    const width = 232
    const height = 260
    const x = Math.max(8, Math.min(event.clientX, window.innerWidth - width - 8))
    const y = Math.max(8, Math.min(event.clientY, window.innerHeight - height - 8))
    setContextMenu({ order, x, y })
  }

  const copyValue = async (value, label) => {
    if (!value) return
    setContextMenu(null)
    try {
      await navigator.clipboard.writeText(String(value))
      showToast(`${label} copied`)
    } catch {
      showToast(`Could not copy ${label.toLowerCase()}`, 'error')
    }
  }

  const handleQuickStatus = async (order, next) => {
    setContextMenu(null)
    try {
      await updateStatus.mutateAsync({ orderId: order.id, status: next.value })
      showToast(`Order moved to ${next.value}`)
    } catch (err) {
      showToast(err.message ?? 'Update failed', 'error')
    }
  }

  const viewPayment = (order) => {
    setContextMenu(null)
    navigate(`/transactions?order=${order.id}`)
  }

  const handleStatusUpdate = async () => {
    if (!selectedOrder || !newStatus) return
    setSaving(true)
    try {
      await updateStatus.mutateAsync({ orderId: selectedOrder.id, status: newStatus })
      showToast('Order status updated')
      setSelectedOrder((current) =>
        current ? { ...current, status: newStatus } : current,
      )
    } catch (err) {
      showToast(err.message ?? 'Update failed', 'error')
    } finally {
      setSaving(false)
    }
  }

  const statusChanged = Boolean(
    selectedOrder && newStatus && newStatus !== selectedOrder.status,
  )
  const contextNextStatus = contextMenu ? nextStatusFor(contextMenu.order.status) : null

  return (
    <div className="space-y-4">
      {!isError && (
        <section
          aria-label="Order pipeline"
          className="grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-border bg-border sm:grid-cols-5"
        >
          {isLoading
            ? PIPELINE.map((stage, index) => (
                <PipelineSkeleton key={stage.key} wide={index === 0} />
              ))
            : PIPELINE.map((stage, index) => {
                const active = statusFilter === stage.key
                const count = stage.key === 'all' ? summary.total : summary[stage.key]

                return (
                  <button
                    key={stage.key}
                    type="button"
                    onClick={() => applyStatus(stage.key)}
                    aria-pressed={active}
                    aria-label={`Filter orders by ${stage.label}`}
                    className={`group bg-card px-3.5 py-3.5 text-left transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary/30 ${
                      index === 0 ? 'col-span-2 sm:col-span-1' : ''
                    } ${active ? 'bg-primary/[0.045]' : 'hover:bg-canvas/60'}`}
                  >
                    <span className="flex items-center justify-between gap-2">
                      <span
                        className={`truncate text-[12px] font-medium ${
                          active ? 'text-primary' : 'text-muted'
                        }`}
                      >
                        {stage.label}
                      </span>
                      {active && (
                        <span
                          aria-hidden="true"
                          className="h-1.5 w-1.5 shrink-0 rounded-full bg-primary"
                        />
                      )}
                    </span>
                    <span className="mt-1.5 block font-mono text-[24px] font-semibold leading-none tracking-tight text-ink tnum">
                      {count.toLocaleString('en-PH')}
                    </span>
                  </button>
                )
              })}
        </section>
      )}

      <section aria-label="Filter orders" className="rounded-xl border border-border bg-card p-3">
        <div className="grid grid-cols-2 gap-2.5 xl:grid-cols-[minmax(260px,1.6fr)_190px_145px_145px]">
          <label className="col-span-2 block xl:col-span-1">
            <span className="mb-1 block text-[12px] font-medium text-muted">Search</span>
            <span className="relative block">
              <Search
                size={14}
                strokeWidth={1.6}
                className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-muted"
                aria-hidden="true"
              />
              <input
                type="search"
                placeholder="Search order, customer, store, product…"
                value={search}
                onChange={(event) => {
                  setSearch(event.target.value)
                  setPage(1)
                }}
                className="h-9 w-full rounded-lg border border-border bg-card pl-8 pr-9 text-[12.5px] text-ink outline-none transition-colors placeholder:text-muted/70 focus:border-primary focus:ring-2 focus:ring-primary/15"
              />
              {search && (
                <button
                  type="button"
                  onClick={() => {
                    setSearch('')
                    setPage(1)
                  }}
                  aria-label="Clear search"
                  className="absolute right-1.5 top-1/2 inline-flex h-6 w-6 -translate-y-1/2 items-center justify-center rounded-md text-muted transition-colors hover:bg-canvas hover:text-ink"
                >
                  <X size={13} />
                </button>
              )}
            </span>
          </label>

          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">Status</span>
            <select
              value={statusFilter}
              onChange={(event) => applyStatus(event.target.value)}
              className="h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12.5px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
            >
              <option value="all">All statuses</option>
              <optgroup label="Queues">
                {PIPELINE.slice(1).map((stage) => (
                  <option key={stage.key} value={stage.key}>
                    {stage.label}
                  </option>
                ))}
              </optgroup>
              <optgroup label="Exact status">
                {EXACT_STATUSES.map((status) => (
                  <option key={status} value={status}>
                    {humanizeStatus(status)}
                  </option>
                ))}
              </optgroup>
            </select>
          </label>

          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">From</span>
            <input
              type="date"
              value={dateFrom}
              onChange={(event) => {
                setDateFrom(event.target.value)
                setPage(1)
              }}
              className="h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
            />
          </label>

          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">To</span>
            <input
              type="date"
              value={dateTo}
              onChange={(event) => {
                setDateTo(event.target.value)
                setPage(1)
              }}
              className="h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
            />
          </label>
        </div>

        <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
          <p className="text-[11.5px] text-muted" aria-live="polite">
            <span className="font-semibold text-ink">{filtered.length.toLocaleString('en-PH')}</span>{' '}
            matching of {(data?.length ?? 0).toLocaleString('en-PH')} orders
          </p>
          {filtersActive && (
            <button
              type="button"
              onClick={clearFilters}
              className="inline-flex h-8 items-center gap-1 rounded-lg px-2.5 text-[12px] font-semibold text-muted transition-colors hover:bg-canvas hover:text-ink"
            >
              <X size={13} aria-hidden="true" />
              Clear filters
            </button>
          )}
        </div>
      </section>

      {isLoading && <TableSkeleton cols={7} rows={8} />}

      {isError && (
        <section className="rounded-xl border border-error/20 bg-card px-6 py-10 text-center">
          <p className="text-[14px] font-semibold text-ink">Could not load orders</p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted">
            {error?.message ?? 'The orders service did not respond.'}
          </p>
        </section>
      )}

      {!isLoading && !isError && (
        <section className="overflow-hidden rounded-xl border border-border bg-card">
          <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3.5">
            <div>
              <h2 className="text-[15px] font-bold text-ink">Orders</h2>
              <p className="mt-0.5 text-[12px] text-muted">
                {filtered.length === 0
                  ? filtersActive
                    ? 'No orders match the current filters'
                    : 'No orders yet'
                  : `${filtered.length.toLocaleString('en-PH')} order${
                      filtered.length === 1 ? '' : 's'
                    } · newest first`}
              </p>
            </div>
            {filtersActive && (
              <span className="rounded-full bg-canvas px-2.5 py-1 text-[11px] font-medium text-muted">
                Filtered
              </span>
            )}
          </div>

          {filtered.length === 0 ? (
            <div className="flex flex-col items-center border-t border-border px-6 py-16 text-center">
              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-canvas">
                {filtersActive ? (
                  <SearchX size={18} strokeWidth={1.5} className="text-muted" aria-hidden="true" />
                ) : (
                  <ShoppingBag size={18} strokeWidth={1.5} className="text-muted" aria-hidden="true" />
                )}
              </div>
              <p className="mt-3 text-[15px] font-semibold text-ink">
                {filtersActive ? 'No orders match these filters' : 'No orders yet'}
              </p>
              <p className="mt-1 max-w-sm text-[12.5px] leading-relaxed text-muted">
                {filtersActive
                  ? 'Try a different queue, clear the search, or widen the date range.'
                  : 'New customer orders will appear here as soon as they are placed.'}
              </p>
              {filtersActive && (
                <button
                  type="button"
                  onClick={clearFilters}
                  className="mt-3 inline-flex h-9 items-center rounded-lg bg-secondary px-3.5 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep"
                >
                  Clear filters
                </button>
              )}
            </div>
          ) : (
            <>
              <div className="hidden overflow-x-auto lg:block">
                <table className="w-full min-w-[860px] table-fixed text-left">
                  <caption className="sr-only">
                    Orders with order ID, customer, store, item count, total, status, and date
                  </caption>
                  <colgroup>
                    <col style={{ width: '104px' }} />
                    <col style={{ width: '210px' }} />
                    <col style={{ width: '106px' }} />
                    <col style={{ width: '54px' }} />
                    <col style={{ width: '116px' }} />
                    <col style={{ width: '126px' }} />
                    <col style={{ width: '108px' }} />
                    <col style={{ width: '36px' }} />
                  </colgroup>
                  <thead className="border-y border-border bg-canvas/60">
                    <tr>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Order</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Customer</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Store</th>
                      <th className="px-4 py-2 text-right text-[12px] font-semibold text-muted">Items</th>
                      <th className="px-4 py-2 text-right text-[12px] font-semibold text-muted">Total</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Status</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Date</th>
                      <th className="px-2 py-2">
                        <span className="sr-only">Open order</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {pageRows.map((row) => (
                      <tr
                        key={row.id}
                        onClick={() => openOrder(row)}
                        onContextMenu={(event) => openContextMenu(event, row)}
                        className="group cursor-pointer admin-list-item admin-list-row"
                      >
                        <td className="px-4 py-3">
                          <span className="font-mono text-[11.5px] text-muted transition-colors group-hover:text-primary">
                            {shortId(row.id)}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          <div className="flex min-w-0 items-center gap-2.5">
                            <AvatarInitials
                              name={row.customer_name}
                              email={row.customer_email}
                              src={row.customer_avatar_url}
                              size="sm"
                            />
                            <div className="min-w-0">
                              <p className="truncate text-[12.5px] font-semibold text-ink">
                                {row.customer_name}
                              </p>
                              <p className="truncate text-[11.5px] text-muted">
                                {row.customer_email || 'No email'}
                              </p>
                            </div>
                          </div>
                        </td>
                        <td className="px-4 py-3">
                          <p className="truncate text-[12.5px] text-muted" title={row.store_name}>
                            {row.store_name}
                          </p>
                        </td>
                        <td className="px-4 py-3 text-right">
                          <span className="font-mono text-[12.5px] text-ink">{row.items_count}</span>
                        </td>
                        <td className="px-4 py-3 text-right">
                          <span className="whitespace-nowrap font-mono text-[12px] font-semibold text-ink">
                            {formatCurrency(row.total_amount)}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          <Badge label={row.status} variant={row.status} dot />
                        </td>
                        <td className="px-4 py-3">
                          <p className="whitespace-nowrap text-[12px] text-ink">
                            {formatDate(row.created_at)}
                          </p>
                          <p className="mt-0.5 text-[11px] text-muted">
                            {formatClock(row.created_at)}
                          </p>
                        </td>
                        <td className="px-2 py-3 text-right">
                          <button
                            type="button"
                            onClick={(event) => {
                              event.stopPropagation()
                              openOrder(row)
                            }}
                            aria-label={`Open order ${shortId(row.id)}`}
                            className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-muted/60 transition-colors group-hover:text-primary hover:bg-canvas hover:text-ink"
                          >
                            <ChevronRight size={15} aria-hidden="true" />
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div className="divide-y divide-border border-t border-border lg:hidden">
                {pageRows.map((row) => (
                  <button
                    key={row.id}
                    type="button"
                    onClick={() => openOrder(row)}
                    onContextMenu={(event) => openContextMenu(event, row)}
                    className="admin-list-item admin-list-card block w-full px-4 py-3.5 text-left active:bg-canvas"
                  >
                    <span className="flex items-center justify-between gap-2">
                      <span className="font-mono text-[11px] text-muted">{shortId(row.id)}</span>
                      <Badge label={row.status} variant={row.status} dot />
                    </span>
                    <span className="mt-2 flex items-center gap-2.5">
                      <AvatarInitials
                        name={row.customer_name}
                        email={row.customer_email}
                        src={row.customer_avatar_url}
                        size="sm"
                      />
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-[13px] font-semibold text-ink">
                          {row.customer_name}
                        </span>
                        <span className="block truncate text-[11.5px] text-muted">
                          {row.store_name}
                        </span>
                      </span>
                      <span className="shrink-0 font-mono text-[12.5px] font-semibold text-ink">
                        {formatCurrency(row.total_amount)}
                      </span>
                    </span>
                    <span className="mt-2 flex items-center justify-between gap-2 text-[11.5px] text-muted">
                      <span>
                        {row.items_count} item{row.items_count === 1 ? '' : 's'} ·{' '}
                        {formatDate(row.created_at)}
                      </span>
                      <span className="inline-flex items-center gap-0.5 text-primary">
                        View
                        <ChevronRight size={12} aria-hidden="true" />
                      </span>
                    </span>
                  </button>
                ))}
              </div>

              <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-3">
                <p className="text-[12px] text-muted">
                  <span className="font-semibold text-ink">
                    {rangeStart}–{rangeEnd}
                  </span>{' '}
                  of {filtered.length.toLocaleString('en-PH')} orders
                </p>
                <div className="flex items-center gap-1">
                  <button
                    type="button"
                    disabled={page <= 1}
                    onClick={() => setPage((current) => Math.max(1, current - 1))}
                    aria-label="Previous page"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-card text-muted transition-colors hover:border-primary/40 hover:text-ink disabled:cursor-not-allowed disabled:opacity-35"
                  >
                    <ChevronLeft size={14} />
                  </button>
                  <span className="px-2 font-mono text-[11px] text-muted">
                    {page} / {totalPages}
                  </span>
                  <button
                    type="button"
                    disabled={page >= totalPages}
                    onClick={() => setPage((current) => Math.min(totalPages, current + 1))}
                    aria-label="Next page"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-card text-muted transition-colors hover:border-primary/40 hover:text-ink disabled:cursor-not-allowed disabled:opacity-35"
                  >
                    <ChevronRight size={14} />
                  </button>
                </div>
              </div>
            </>
          )}
        </section>
      )}

      {contextMenu && (
        <div
          ref={contextMenuRef}
          role="menu"
          aria-label={`Order ${shortId(contextMenu.order.id)} actions`}
          style={{ left: contextMenu.x, top: contextMenu.y }}
          className="fixed z-[60] w-56 overflow-hidden rounded-xl border border-border bg-card py-1 shadow-pop"
        >
          <div className="border-b border-border px-3 py-2">
            <p className="font-mono text-[10.5px] text-muted">
              Order {shortId(contextMenu.order.id)}
            </p>
            <p className="mt-0.5 truncate text-[12px] font-semibold text-ink">
              {contextMenu.order.customer_name}
            </p>
          </div>

          <ContextMenuItem
            icon={Eye}
            onClick={() => {
              setContextMenu(null)
              openOrder(contextMenu.order)
            }}
          >
            Open order details
          </ContextMenuItem>

          {contextNextStatus && (
            <ContextMenuItem
              icon={ArrowRight}
              onClick={() => handleQuickStatus(contextMenu.order, contextNextStatus)}
            >
              {contextNextStatus.label}
            </ContextMenuItem>
          )}

          <div className="my-1 h-px bg-border" />

          <ContextMenuItem
            icon={Copy}
            onClick={() => copyValue(contextMenu.order.id, 'Order ID')}
          >
            Copy order ID
          </ContextMenuItem>

          {contextMenu.order.customer_email && (
            <ContextMenuItem
              icon={Mail}
              onClick={() => copyValue(contextMenu.order.customer_email, 'Customer email')}
            >
              Copy customer email
            </ContextMenuItem>
          )}

          {contextMenu.order.payment_method === 'gcash' &&
            contextMenu.order.source === 'online' && (
              <ContextMenuItem
                icon={ArrowUpRight}
                onClick={() => viewPayment(contextMenu.order)}
              >
                View payment
              </ContextMenuItem>
            )}
        </div>
      )}

      <Modal
        open={!!selectedOrder}
        onClose={closeOrder}
        title={`Order ${shortId(selectedOrder?.id)}`}
        size="xl"
        footer={
          <>
            <span className="mr-auto hidden self-center text-[11.5px] text-muted sm:block">
              Change status
            </span>
            <select
              value={newStatus}
              onChange={(event) => setNewStatus(event.target.value)}
              aria-label="New order status"
              className="h-9 rounded-lg border border-border bg-card px-2.5 text-[12px] font-medium text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
            >
              {ORDER_STATUSES.map((status) => (
                <option key={status} value={status}>
                  {humanizeStatus(status)}
                </option>
              ))}
            </select>
            <button
              type="button"
              onClick={handleStatusUpdate}
              disabled={saving || !statusChanged}
              className="inline-flex h-9 items-center rounded-lg bg-secondary px-3.5 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep disabled:cursor-not-allowed disabled:opacity-40"
            >
              {saving ? 'Saving…' : 'Update status'}
            </button>
          </>
        }
      >
        {selectedOrder && (
          <div className="space-y-4">
            <div className="rounded-xl border border-border bg-canvas/40 p-4">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="flex min-w-0 items-start gap-3">
                  <AvatarInitials
                    name={selectedOrder.customer_name}
                    email={selectedOrder.customer_email}
                    src={selectedOrder.customer_avatar_url}
                    size="lg"
                  />
                  <div className="min-w-0">
                    <p className="text-[14px] font-semibold text-ink">
                      {selectedOrder.customer_name}
                    </p>
                    <p className="truncate text-[12px] text-muted">
                      {selectedOrder.customer_email || 'No email on file'}
                    </p>
                    <p className="mt-1 text-[11.5px] text-muted">
                      {formatDateTime(selectedOrder.created_at)}
                    </p>
                  </div>
                </div>
                <div className="flex flex-col items-end gap-1.5">
                  <Badge label={selectedOrder.status} variant={selectedOrder.status} dot />
                  <p className="text-[11.5px] text-muted">{selectedOrder.store_name}</p>
                </div>
              </div>

              <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-border/80 pt-3">
                {selectedOrder.payment_method && (
                  <span className="rounded-md bg-card px-2 py-1 text-[11px] font-medium text-muted ring-1 ring-border">
                    Payment ·{' '}
                    {selectedOrder.payment_method.toLowerCase() === 'gcash'
                      ? 'GCash'
                      : humanizeStatus(selectedOrder.payment_method)}
                  </span>
                )}
                {selectedOrder.source && (
                  <span className="rounded-md bg-card px-2 py-1 text-[11px] font-medium text-muted ring-1 ring-border">
                    Source · {humanizeStatus(selectedOrder.source)}
                  </span>
                )}
                {selectedOrder.payment_method === 'gcash' &&
                  selectedOrder.source === 'online' && (
                    <Link
                      to={`/transactions?order=${selectedOrder.id}`}
                      className="inline-flex h-7 items-center gap-1 rounded-md bg-secondary px-2.5 text-[11px] font-semibold text-white transition-colors hover:bg-primaryDeep"
                    >
                      View payment
                      <ArrowUpRight size={12} aria-hidden="true" />
                    </Link>
                  )}
              </div>
            </div>

            <div>
              <h3 className="text-[13px] font-semibold text-ink">
                Items{' '}
                <span className="font-normal text-muted">
                  ({selectedOrder.items_count})
                </span>
              </h3>
              <div className="mt-2 overflow-hidden rounded-xl border border-border">
                {(selectedOrder.order_items ?? []).length === 0 ? (
                  <p className="px-4 py-6 text-center text-[12px] text-muted">
                    No item lines were recorded for this order.
                  </p>
                ) : (
                  <div className="divide-y divide-border">
                    {selectedOrder.order_items.map((item, index) => {
                      const image = productThumb(item)
                      const quantity = Number(item.quantity) || 0
                      const unitPrice = Number(item.unit_price) || 0

                      return (
                        <div key={item.id ?? index} className="flex items-center gap-3 px-3 py-2.5">
                          {image ? (
                            <img
                              src={image}
                              alt={item.product_name}
                              className="h-10 w-10 shrink-0 rounded-lg object-cover"
                            />
                          ) : (
                            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-canvas">
                              <Package size={14} className="text-muted" aria-hidden="true" />
                            </div>
                          )}
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-[12.5px] font-medium text-ink">
                              {item.product_name}
                            </p>
                            <p className="mt-0.5 text-[11.5px] text-muted">
                              {quantity} × {formatCurrency(unitPrice)}
                            </p>
                          </div>
                          <span className="shrink-0 font-mono text-[12px] font-semibold text-ink">
                            {formatCurrency(quantity * unitPrice)}
                          </span>
                        </div>
                      )
                    })}
                  </div>
                )}
              </div>
            </div>

            <div className="flex items-center justify-between rounded-xl bg-canvas px-4 py-3">
              <span className="text-[12px] text-muted">Order total</span>
              <span className="font-mono text-[18px] font-semibold tracking-tight text-ink">
                {formatCurrency(selectedOrder.total_amount)}
              </span>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}
