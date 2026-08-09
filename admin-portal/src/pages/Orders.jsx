import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import Badge from '../components/ui/Badge.jsx'
import Modal from '../components/ui/Modal.jsx'
import { TableSkeleton } from '../components/ui/Skeleton.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import { useOrders, useUpdateOrderStatus } from '../hooks/useOrders.js'
import { formatDate, formatCurrency, formatDateTime, shortId, ORDER_STATUSES } from '../lib/constants'
import EmptyState from '../components/ui/EmptyState.jsx'
import { Search } from 'lucide-react'

const PAGE_SIZE = 20

export default function Orders() {
  const { showToast } = useToast()
  const { data, isLoading, isError, error } = useOrders()
  const updateStatus = useUpdateOrderStatus()

  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [page, setPage] = useState(1)
  const [selectedOrder, setSelectedOrder] = useState(null)
  const [newStatus, setNewStatus] = useState('')
  const [saving, setSaving] = useState(false)

  const filtered = useMemo(() => {
    let rows = data ?? []
    const q = search.trim().toLowerCase()
    if (q) {
      rows = rows.filter(
        (o) =>
          String(o.id).toLowerCase().includes(q) ||
          o.customer_name?.toLowerCase().includes(q),
      )
    }
    if (statusFilter !== 'all') rows = rows.filter((o) => o.status === statusFilter)
    if (dateFrom) {
      const from = new Date(dateFrom)
      rows = rows.filter((o) => new Date(o.created_at) >= from)
    }
    if (dateTo) {
      const to = new Date(dateTo)
      to.setHours(23, 59, 59, 999)
      rows = rows.filter((o) => new Date(o.created_at) <= to)
    }
    return rows
  }, [data, search, statusFilter, dateFrom, dateTo])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const pageRows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const openOrder = (order) => {
    setSelectedOrder(order)
    setNewStatus(order.status)
  }

  const handleStatusUpdate = async () => {
    if (!selectedOrder || !newStatus) return
    setSaving(true)
    try {
      await updateStatus.mutateAsync({ orderId: selectedOrder.id, status: newStatus })
      showToast('Order status updated')
      setSelectedOrder({ ...selectedOrder, status: newStatus })
    } catch (err) {
      showToast(err.message ?? 'Update failed', 'error')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-4">
      {/* Search & filter bar */}
      <div className="flex gap-3">
        <div className="relative flex-1">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#6B5C4E]" />
          <input
            type="search"
            placeholder="Search order ID or customer…"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value)
              setPage(1)
            }}
            className="w-full rounded-xl border border-[#D9D0C7] bg-white py-2.5 pl-9 pr-4 text-sm text-[#3B2314] placeholder-[#6B5C4E] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => {
            setStatusFilter(e.target.value)
            setPage(1)
          }}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
        >
          <option value="all">All statuses</option>
          {ORDER_STATUSES.map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </select>
        <input
          type="date"
          value={dateFrom}
          onChange={(e) => {
            setDateFrom(e.target.value)
            setPage(1)
          }}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
        />
        <input
          type="date"
          value={dateTo}
          onChange={(e) => {
            setDateTo(e.target.value)
            setPage(1)
          }}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
        />
      </div>

      {isLoading && <TableSkeleton cols={7} rows={8} />}
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
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Order ID</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Customer</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Store</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Items</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Total</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Status</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#F5F0EB]">
                {pageRows.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="p-0">
                      <EmptyState
                        icon="🛒"
                        title="No orders found"
                        description="Try adjusting your search or filters."
                      />
                    </td>
                  </tr>
                ) : (
                  pageRows.map((row) => (
                    <tr
                      key={row.id}
                      onClick={() => openOrder(row)}
                      className="cursor-pointer transition-colors hover:bg-[#FBF8F5]"
                    >
                      <td className="px-6 py-4 font-mono text-xs">{shortId(row.id)}</td>
                      <td className="px-6 py-4 text-[#3B2314]">{row.customer_name}</td>
                      <td className="px-6 py-4 text-[#6B5C4E]">{row.store_name}</td>
                      <td className="px-6 py-4 text-[#6B5C4E]">{row.items_count}</td>
                      <td className="px-6 py-4 font-mono">{formatCurrency(row.total_amount)}</td>
                      <td className="px-6 py-4"><Badge label={row.status} variant={row.status} /></td>
                      <td className="px-6 py-4 text-[#6B5C4E]">{formatDate(row.created_at)}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>

          <div className="flex items-center justify-between text-sm">
            <span className="text-[#6B5C4E]">
              {filtered.length} orders · Page {page} of {totalPages}
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

      <Modal
        open={!!selectedOrder}
        onClose={() => setSelectedOrder(null)}
        title={`Order ${shortId(selectedOrder?.id)}`}
        footer={
          <>
            <select
              value={newStatus}
              onChange={(e) => setNewStatus(e.target.value)}
              className="rounded-xl border border-[#D9D0C7] bg-white px-3 py-2 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
            >
              {ORDER_STATUSES.map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
            <button
              type="button"
              onClick={handleStatusUpdate}
              disabled={saving}
              className="rounded-xl bg-[#8B5A2B] px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-[#6B4520] disabled:opacity-50"
            >
              Update Status
            </button>
          </>
        }
      >
        {selectedOrder && (
          <div className="space-y-4 text-sm">
            <div>
              <p className="font-semibold text-[#3B2314]">{selectedOrder.customer_name}</p>
              <p className="text-[#6B5C4E]">{selectedOrder.customer_email}</p>
              <p className="text-[#6B5C4E]">{formatDateTime(selectedOrder.created_at)}</p>
              {selectedOrder.payment_method === 'gcash' && selectedOrder.source === 'online' && (
                <Link
                  to={`/transactions?order=${selectedOrder.id}`}
                  className="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-[#8B5A2B] px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-[#6B4520]"
                >
                  View Payment
                </Link>
              )}
            </div>

            <div>
              <h3 className="mb-2 font-semibold text-[#3B2314]">Items</h3>
              <ul className="space-y-2">
                {(selectedOrder.order_items ?? []).map((item, i) => (
                  <li key={i} className="flex justify-between rounded-xl border border-[#D9D0C7] px-3 py-2">
                    <span className="text-[#6B5C4E]">{item.product_name} × {item.quantity}</span>
                    <span className="font-mono">{formatCurrency(item.unit_price * item.quantity)}</span>
                  </li>
                ))}
              </ul>
            </div>

            <div className="flex justify-between border-t border-[#D9D0C7] pt-3 font-semibold text-[#3B2314]">
              <span>Total</span>
              <span className="font-mono">{formatCurrency(selectedOrder.total_amount)}</span>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}
