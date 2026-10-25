import { useState } from 'react'
import { Link } from 'react-router-dom'
import {
  AreaChart,
  Area,
  Line,
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
  useOrderPipeline,
  useApproveSeller,
  useRejectSeller,
} from '../hooks/useDashboard.js'
import { formatDate, formatCurrency, shortId } from '../lib/constants'
import {
  ShoppingCart,
  Package,
  Store,
  Users,
  Wallet,
  ArrowRight,
  Clock,
  Flame,
  Truck,
  CheckCheck,
} from 'lucide-react'

function MiniSpark({ data, color = '#8B5A2B' }) {
  if (!data?.length) return null
  return (
    <ResponsiveContainer width="100%" height="100%">
      <AreaChart data={data} margin={{ top: 2, right: 0, bottom: 0, left: 0 }}>
        <Area
          type="monotone"
          dataKey="count"
          stroke={color}
          strokeWidth={1.75}
          fill={color}
          fillOpacity={0.12}
          isAnimationActive={false}
          dot={false}
        />
      </AreaChart>
    </ResponsiveContainer>
  )
}

export default function Dashboard() {
  const { showToast } = useToast()
  const { data: stats, isLoading: statsLoading } = useDashboardStats()
  const { data: pendingApps, isLoading: pendingLoading } = useRecentPendingApplications(4)
  const { data: recentOrders, isLoading: ordersLoading } = useRecentOrders(6)
  const { data: spark } = useOrdersSparkline(14)
  const { data: pipeline } = useOrderPipeline()
  const approve = useApproveSeller()
  const reject = useRejectSeller()
  const [loadingId, setLoadingId] = useState(null)

  const handleApprove = async (userId) => {
    setLoadingId(userId)
    try {
      await approve.mutateAsync(userId)
      showToast('Seller approved')
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
      showToast('Application declined')
    } catch (err) {
      showToast(err.message ?? 'Action failed', 'error')
    } finally {
      setLoadingId(null)
    }
  }

  const chartData = (() => {
    if (!spark?.current?.length) return []
    const prev = spark.previous ?? []
    const half = spark.current.length
    const prevTail = prev.slice(-half)
    return spark.current.map((c, i) => ({
      date: c.date,
      count: c.count,
      previous: prevTail[i]?.count ?? null,
    }))
  })()
  const chartTotal = spark?.total ?? 0

  const pipe = [
    { label: 'Needs action', value: pipeline?.needsAction ?? 0, Icon: Clock, to: '/orders?status=pending' },
    { label: 'In preparation', value: pipeline?.inKitchen ?? 0, Icon: Flame, to: '/orders?status=preparing' },
    { label: 'Shipped', value: pipeline?.onTheWay ?? 0, Icon: Truck, to: '/orders?status=shipped' },
    { label: 'Delivered', value: pipeline?.done ?? 0, Icon: CheckCheck, to: '/orders?status=delivered' },
  ]

  return (
    <div className="space-y-6">
      {/* Summary row: what happened + where to go */}
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="max-w-xl">
          <p className="text-sm text-muted">
            {chartTotal === 0
              ? 'A quiet week on the shelf. Review sellers waiting below, then check the order queue.'
              : `${chartTotal} orders in the last 7 days, worth ${formatCurrency(spark?.totalRevenue ?? stats?.revenue7d ?? 0)}.`}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            to="/seller-applications"
            className="rounded-xl border border-border bg-white px-3.5 py-2 text-sm font-semibold text-secondary shadow-card transition-colors hover:border-primary/60"
          >
            Review applications{stats?.pendingApplications ? ` (${stats.pendingApplications})` : ''}
          </Link>
          <Link
            to="/orders"
            className="inline-flex items-center gap-1.5 rounded-xl bg-secondary px-3.5 py-2 text-sm font-semibold text-white transition-colors hover:bg-primaryDeep"
          >
            View orders <ArrowRight size={15} />
          </Link>
        </div>
      </div>

      {/* KPI row */}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {statsLoading ? (
          Array.from({ length: 4 }).map((_, i) => <StatCardSkeleton key={i} />)
        ) : (
          <>
            <StatCard
              tone="primary"
              Icon={ShoppingCart}
              label="Orders, last 7 days"
              value={stats?.orders7d ?? 0}
              delta={stats?.ordersDelta ?? null}
              caption={`${stats?.totalOrders ?? 0} all time`}
              sparkline={<MiniSpark data={spark?.current} color="#8B5A2B" />}
            />
            <StatCard
              tone="teal"
              Icon={Wallet}
              label="Revenue, last 7 days"
              value={formatCurrency(stats?.revenue7d ?? 0)}
              delta={stats?.revenueDelta ?? null}
              formatDelta={(n) => {
                if (n === 0) return 'No change from last week'
                const arrow = n > 0 ? 'Up' : 'Down'
                return `${arrow} ${formatCurrency(Math.abs(Math.round(n)))} from last week`
              }}
              caption="Paid + pending orders"
            />
            <StatCard
              tone="cocoa"
              Icon={Package}
              label="Live products"
              value={stats?.totalProducts ?? 0}
              caption="Across all stores"
            />
            <StatCard
              tone={stats?.pendingApplications > 0 ? 'amber' : 'neutral'}
              Icon={Store}
              label="Sellers waiting"
              value={stats?.pendingApplications ?? 0}
              highlight={(stats?.pendingApplications ?? 0) > 0}
              caption={
                (stats?.pendingApplications ?? 0) > 0
                  ? 'Needs a decision'
                  : 'Queue is clear'
              }
            />
          </>
        )}
      </div>

      {/* Operations strip: shelf to doorstep */}
      <section className="rounded-2xl border border-border bg-white shadow-card">
        <div className="flex items-center justify-between px-5 pb-1 pt-4">
          <h2 className="text-[15px] font-bold text-ink">From shelf to doorstep</h2>
          <Link to="/orders" className="inline-flex items-center gap-1 text-[13px] font-semibold text-primary hover:underline">
            Open order queue <ArrowRight size={14} />
          </Link>
        </div>
        <div className="grid grid-cols-2 divide-border px-2 pb-2 sm:grid-cols-4 sm:divide-x">
          {pipe.map((p) => (
            <Link
              key={p.label}
              to={p.to}
              className="group flex items-center gap-3 rounded-xl px-4 py-3 transition-colors hover:bg-canvas"
            >
              <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-faint text-secondary">
                <p.Icon size={17} strokeWidth={2} />
              </span>
              <span>
                <span className="tnum block font-mono text-xl font-semibold leading-none text-ink">
                  {p.value}
                </span>
                <span className="mt-1 block text-[13px] text-muted group-hover:text-ink">{p.label}</span>
              </span>
            </Link>
          ))}
        </div>
      </section>

      <div className="grid gap-6 xl:grid-cols-5">
        {/* Recent orders: the wider column */}
        <section className="rounded-2xl border border-border bg-white shadow-card xl:col-span-3">
          <div className="flex items-center justify-between px-5 py-4">
            <h2 className="text-[15px] font-bold text-ink">Latest orders</h2>
            <Link to="/orders" className="inline-flex items-center gap-1 text-[13px] font-semibold text-primary hover:underline">
              View all <ArrowRight size={14} />
            </Link>
          </div>
          <div className="px-3 pb-3">
            {ordersLoading ? (
              <TableSkeleton cols={4} rows={5} />
            ) : recentOrders?.length > 0 ? (
              <div className="overflow-hidden rounded-xl border border-border">
                <table className="w-full text-left text-sm">
                  <thead className="bg-canvas">
                    <tr>
                      <th className="px-4 py-2.5 text-[13px] font-semibold text-muted">Order</th>
                      <th className="px-4 py-2.5 text-[13px] font-semibold text-muted">Customer</th>
                      <th className="px-4 py-2.5 text-right text-[13px] font-semibold text-muted">Total</th>
                      <th className="px-4 py-2.5 text-[13px] font-semibold text-muted">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-canvas">
                    {recentOrders.map((order) => (
                      <tr key={order.id} className="transition-colors hover:bg-canvas/70">
                        <td className="tnum px-4 py-3 font-mono text-xs text-muted">{shortId(order.id)}</td>
                        <td className="max-w-[160px] truncate px-4 py-3 text-ink">
                          {order.profiles?.full_name ?? 'Walk-in'}
                          {order.stores?.name && (
                            <span className="block truncate text-xs text-muted">{order.stores.name}</span>
                          )}
                        </td>
                        <td className="tnum px-4 py-3 text-right font-mono text-[13px] text-ink">
                          {formatCurrency(order.total_amount)}
                        </td>
                        <td className="px-4 py-3">
                          <Badge label={order.status} variant={order.status} dot />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="flex flex-col items-center rounded-xl border border-dashed border-border bg-canvas px-6 py-12 text-center">
                <span className="mb-3 flex h-11 w-11 items-center justify-center rounded-xl bg-faint text-secondary">
                  <Package size={20} strokeWidth={1.75} />
                </span>
                <p className="text-sm font-semibold text-ink">No orders yet</p>
                <p className="mt-1 max-w-xs text-[13px] text-muted">
                  Orders from the storefront land here. Share a product link to get the first sale.
                </p>
                <Link
                  to="/products"
                  className="mt-4 rounded-lg bg-secondary px-3.5 py-2 text-[13px] font-semibold text-white hover:bg-primaryDeep"
                >
                  Check products
                </Link>
              </div>
            )}
          </div>
        </section>

        {/* Attention queue */}
        <section className="rounded-2xl border border-border bg-white shadow-card xl:col-span-2">
          <div className="flex items-center justify-between px-5 py-4">
            <h2 className="text-[15px] font-bold text-ink">
              Needs a decision
              {(pendingApps?.length ?? 0) > 0 && (
                <span className="ml-2 rounded-full bg-pendingSoft px-2 py-0.5 text-xs font-bold text-pending">
                  {pendingApps.length}
                </span>
              )}
            </h2>
            <Link to="/seller-applications" className="inline-flex items-center gap-1 text-[13px] font-semibold text-primary hover:underline">
              View all <ArrowRight size={14} />
            </Link>
          </div>
          <div className="px-3 pb-3">
            {pendingLoading ? (
              <TableSkeleton cols={2} rows={3} />
            ) : pendingApps?.length > 0 ? (
              <ul className="space-y-2">
                {pendingApps.map((app) => (
                  <li
                    key={app.id}
                    className="flex items-center justify-between gap-3 rounded-xl border border-border px-3.5 py-3 transition-colors hover:border-primary/40"
                  >
                    <div className="flex min-w-0 items-center gap-3">
                      <AvatarInitials name={app.full_name} email={app.email} />
                      <div className="min-w-0">
                        <p className="truncate text-sm font-semibold text-ink">{app.full_name}</p>
                        <p className="truncate text-xs text-muted">{app.email}</p>
                        <p className="mt-0.5 text-xs text-muted">Applied {formatDate(app.created_at)}</p>
                      </div>
                    </div>
                    <div className="flex shrink-0 items-center gap-1.5">
                      <button
                        type="button"
                        disabled={loadingId === app.id}
                        onClick={() => handleApprove(app.id)}
                        className="rounded-lg bg-accent px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:brightness-110 disabled:opacity-50"
                      >
                        Approve
                      </button>
                      <button
                        type="button"
                        disabled={loadingId === app.id}
                        onClick={() => handleReject(app.id)}
                        className="rounded-lg border border-error/40 px-3 py-1.5 text-xs font-semibold text-error transition-colors hover:bg-errorSoft disabled:opacity-50"
                      >
                        Decline
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            ) : (
              <div className="flex flex-col items-center rounded-xl bg-canvas px-6 py-12 text-center">
                <span className="mb-3 flex h-11 w-11 items-center justify-center rounded-xl bg-[#E0F2F1] text-accent">
                  <Users size={20} strokeWidth={1.75} />
                </span>
                <p className="text-sm font-semibold text-ink">Queue is clear</p>
                <p className="mt-1 max-w-xs text-[13px] text-muted">
                  New seller applications will appear here with approve and decline actions.
                </p>
              </div>
            )}
          </div>
        </section>
      </div>

      {/* Trend chart */}
      <section className="rounded-2xl border border-border bg-white p-5 shadow-card">
        <div className="mb-1 flex flex-wrap items-baseline justify-between gap-2">
          <div>
            <h2 className="text-[15px] font-bold text-ink">Orders, last 7 days</h2>
            <p className="mt-0.5 text-[13px] text-muted">
              {chartTotal} orders total
              {chartData.some((d) => d.previous) ? ' (dashed line shows the week before)' : ' (not enough history yet for a comparison)'}
            </p>
          </div>
          <span className="tnum font-mono text-sm font-semibold text-ink">
            {formatCurrency(spark?.totalRevenue ?? 0)} revenue
          </span>
        </div>
        <div className="h-52">
          {chartTotal === 0 ? (
            <div className="flex h-full flex-col items-center justify-center rounded-xl bg-canvas px-6 text-center">
              <p className="text-sm font-semibold text-ink">Nothing to plot yet</p>
              <p className="mt-1 max-w-sm text-[13px] text-muted">
                This chart fills in once storefront orders arrive. The pipeline above stays useful even on quiet days.
              </p>
            </div>
          ) : (
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={chartData} margin={{ top: 8, right: 8, bottom: 0, left: -12 }}>
                <defs>
                  <linearGradient id="ordersFill" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#8B5A2B" stopOpacity={0.22} />
                    <stop offset="100%" stopColor="#8B5A2B" stopOpacity={0.02} />
                  </linearGradient>
                </defs>
                <XAxis dataKey="date" tick={{ fontSize: 12, fill: '#6B5C4E' }} tickLine={false} axisLine={{ stroke: '#EDE5DB' }} />
                <YAxis allowDecimals={false} tick={{ fontSize: 12, fill: '#6B5C4E' }} tickLine={false} axisLine={false} width={36} />
                <Tooltip
                  contentStyle={{ fontFamily: 'DM Sans, sans-serif', borderRadius: '12px', border: '1px solid #D9D0C7', fontSize: 13 }}
                  labelFormatter={(v) => `Oct ${v}`}
                />
                {chartData.some((d) => d.previous != null) && (
                  <Line type="monotone" dataKey="previous" stroke="#B9AE9F" strokeDasharray="5 4" strokeWidth={1.5} dot={false} />
                )}
                <Area type="monotone" dataKey="count" stroke="#8B5A2B" strokeWidth={2.25} fill="url(#ordersFill)" dot={false} />
              </AreaChart>
            </ResponsiveContainer>
          )}
        </div>
      </section>
    </div>
  )
}
