import { useState } from 'react'
import {
  AreaChart,
  Area,
  LineChart,
  Line,
  PieChart,
  Pie,
  Cell,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
} from 'recharts'
import StatCard from '../components/ui/StatCard.jsx'
import { StatCardSkeleton, TableSkeleton } from '../components/ui/Skeleton.jsx'
import Badge from '../components/ui/Badge.jsx'
import AvatarInitials from '../components/ui/AvatarInitials.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import {
  useDashboardStats,
  useRecentPendingApplications,
  useRecentOrders,
  useOrdersSparkline,
  useApproveSeller,
  useRejectSeller,
} from '../hooks/useDashboard.js'
import { formatDate, formatCurrency, shortId } from '../lib/constants'
import { ShoppingCart, Package } from 'lucide-react'

export default function Dashboard() {
  const { showToast } = useToast()
  const { data: stats, isLoading: statsLoading } = useDashboardStats()
  const { data: pendingApps, isLoading: pendingLoading } = useRecentPendingApplications()
  const { data: recentOrders, isLoading: ordersLoading } = useRecentOrders()
  const { data: sparkline } = useOrdersSparkline()
  const approve = useApproveSeller()
  const reject = useRejectSeller()
  const [loadingId, setLoadingId] = useState(null)

  const handleApprove = async (userId) => {
    setLoadingId(userId)
    try {
      await approve.mutateAsync(userId)
      showToast('Seller approved successfully')
    } catch (err) {
      showToast(err.message ?? 'Approval failed', 'error')
    } finally {
      setLoadingId(null)
    }
  }

  const handleReject = async (userId) => {
    setLoadingId(userId)
    try {
      await reject.mutateAsync({ userId })
      showToast('Application rejected')
    } catch (err) {
      showToast(err.message ?? 'Rejection failed', 'error')
    } finally {
      setLoadingId(null)
    }
  }

  return (
    <div className="space-y-8">
      {/* Stat cards */}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {statsLoading ? (
          Array.from({ length: 4 }).map((_, i) => <StatCardSkeleton key={i} />)
        ) : (
          <>
            <StatCard
              icon="👥"
              label="Total Users"
              value={stats?.totalUsers ?? 0}
              iconBg="rgba(139,90,43,0.1)"
              iconColor="#8B5A2B"
            />
            <StatCard
              icon="🏪"
              label="Pending Sellers"
              value={stats?.pendingApplications ?? 0}
              highlight={(stats?.pendingApplications ?? 0) > 0}
              iconBg="rgba(232,160,32,0.1)"
              iconColor="#E8A020"
            />
            <StatCard
              icon="📦"
              label="Total Products"
              value={stats?.totalProducts ?? 0}
              iconBg="rgba(78,205,196,0.1)"
              iconColor="#4ECDC4"
            />
            <StatCard
              icon="🛒"
              label="Total Orders"
              value={stats?.totalOrders ?? 0}
              iconBg="rgba(59,35,20,0.1)"
              iconColor="#3B2314"
            />
          </>
        )}
      </div>

      <div className="grid gap-6 xl:grid-cols-2">
        {/* Recent Seller Applications */}
        <section className="rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
          <div className="border-b border-[#F5F0EB] px-6 py-4">
            <h2 className="font-display text-lg font-bold text-[#3B2314]">Recent Seller Applications</h2>
          </div>
          <div className="p-4">
            {pendingLoading ? (
              <TableSkeleton cols={4} rows={4} />
            ) : pendingApps?.length > 0 ? (
              <div className="space-y-3">
                {pendingApps.map((app) => (
                  <div
                    key={app.id}
                    className="flex items-center justify-between rounded-xl border border-[#D9D0C7] p-4 transition-shadow hover:shadow-sm"
                  >
                    <div className="flex items-center gap-3">
                      <AvatarInitials name={app.full_name} email={app.email} />
                      <div>
                        <p className="text-sm font-semibold text-[#3B2314]">{app.full_name}</p>
                        <p className="text-xs text-[#6B5C4E]">{app.email}</p>
                        <p className="text-xs text-[#6B5C4E] mt-0.5">Applied {formatDate(app.created_at)}</p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        disabled={loadingId === app.id}
                        onClick={() => handleApprove(app.id)}
                        className="rounded-lg bg-[#4ECDC4] px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-teal-600 disabled:opacity-50"
                      >
                        Approve
                      </button>
                      <button
                        type="button"
                        disabled={loadingId === app.id}
                        onClick={() => handleReject(app.id)}
                        className="rounded-lg border border-[#D64545] px-3 py-1.5 text-xs font-semibold text-[#D64545] transition-colors hover:bg-red-50 disabled:opacity-50"
                      >
                        Reject
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-12 text-[#6B5C4E]">
                <ShoppingCart size={32} className="mb-2 opacity-40" />
                <p className="text-sm">No pending applications</p>
              </div>
            )}
          </div>
        </section>

        {/* Recent Orders */}
        <section className="rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
          <div className="border-b border-[#F5F0EB] px-6 py-4">
            <h2 className="font-display text-lg font-bold text-[#3B2314]">Recent Orders</h2>
          </div>
          <div className="p-4">
            {ordersLoading ? (
              <TableSkeleton cols={4} rows={4} />
            ) : recentOrders?.length > 0 ? (
              <div className="overflow-hidden rounded-xl border border-[#D9D0C7]">
                <table className="w-full text-left text-sm">
                  <thead className="bg-[#F5F0EB]">
                    <tr>
                      <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Order</th>
                      <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Customer</th>
                      <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Total</th>
                      <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#F5F0EB]">
                    {recentOrders.map((order) => (
                      <tr key={order.id} className="transition-colors hover:bg-[#FBF8F5]">
                        <td className="px-4 py-3 font-mono text-xs">{shortId(order.id)}</td>
                        <td className="px-4 py-3">{order.profiles?.full_name ?? '—'}</td>
                        <td className="px-4 py-3 font-mono">{formatCurrency(order.total_amount)}</td>
                        <td className="px-4 py-3"><Badge label={order.status} variant={order.status} /></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="flex flex-col items-center justify-center py-12 text-[#6B5C4E]">
                <Package size={32} className="mb-2 opacity-40" />
                <p className="text-sm">No orders yet</p>
              </div>
            )}
          </div>
        </section>
      </div>

      {/* Orders sparkline */}
      <section className="rounded-2xl border border-[#D9D0C7] bg-white p-6 shadow-sm">
        <h2 className="mb-4 font-display text-lg font-bold text-[#3B2314]">Orders — Last 7 Days</h2>
        <div className="h-48">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={sparkline ?? []}>
              <defs>
                <linearGradient id="ordersGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#8B5A2B" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#8B5A2B" stopOpacity={0} />
                </linearGradient>
              </defs>
              <XAxis dataKey="date" tick={{ fontSize: 12, fill: '#6B5C4E' }} />
              <YAxis allowDecimals={false} tick={{ fontSize: 12, fill: '#6B5C4E' }} />
              <Tooltip contentStyle={{ fontFamily: 'DM Sans, sans-serif', borderRadius: '12px', border: '1px solid #D9D0C7' }} />
              <Area type="monotone" dataKey="count" stroke="#8B5A2B" strokeWidth={2} fill="url(#ordersGradient)" />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </section>
    </div>
  )
}
