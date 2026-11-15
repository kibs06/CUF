import { useState } from 'react'
import { Link } from 'react-router-dom'
import {
  AreaChart,
  Area,
  ResponsiveContainer,
} from 'recharts'
import StatCard from '../components/ui/StatCard.jsx'
import TrendPanel from '../components/ui/TrendPanel.jsx'
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
  PackageOpen,
  Store,
  Users,
  Wallet,
  ArrowRight,
  Clock,
  Truck,
  CheckCheck,
} from 'lucide-react'

const peso = String.fromCharCode(0x20B1)
const pesoTick = (v) => (v >= 1000 ? `${peso}${Math.round(v / 100) / 10}k` : `${peso}${v}`)

function MiniSpark({ data, color = '#8B5A2B', id = 'miniSpark' }) {
  if (!data?.length) return null
  return (
    <ResponsiveContainer width="100%" height="100%">
      <AreaChart data={data} margin={{ top: 4, right: 0, bottom: 0, left: 0 }}>
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.28} />
            <stop offset="100%" stopColor={color} stopOpacity={0.03} />
          </linearGradient>
        </defs>
        <Area
          type="monotone"
          dataKey="count"
          stroke={color}
          strokeWidth={2}
          fill={`url(#${id})`}
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

  const trend = (() => {
    const current = spark?.current ?? []
    const tail = (spark?.previous ?? []).slice(-current.length)
    const series = (key) => current.map((c, i) => ({ date: c.date, value: c[key] ?? 0, previous: tail[i]?.[key] ?? null }))
    return { orders: series('count'), revenue: series('revenue') }
  })()
  const chartTotal = spark?.total ?? 0
  const revenueTotal = spark?.totalRevenue ?? 0

  const pipe = [
    { label: 'Needs action', value: pipeline?.needsAction ?? 0, Icon: Clock, to: '/orders?status=pending', tile: 'bg-pendingSoft text-pending' },
    { label: 'In preparation', value: pipeline?.inKitchen ?? 0, Icon: PackageOpen, to: '/orders?status=preparing', tile: 'bg-[#E4EBFF] text-[#2B4BCB]' },
    { label: 'Shipped', value: pipeline?.onTheWay ?? 0, Icon: Truck, to: '/orders?status=shipped', tile: 'bg-[#E9E4FB] text-[#5B3DF0]' },
    { label: 'Delivered', value: pipeline?.done ?? 0, Icon: CheckCheck, to: '/orders?status=delivered', tile: 'bg-accentSoft text-accent' },
  ]

  const pipeTotal = pipe.reduce((s, p) => s + p.value, 0)

  return (
    <div className="dashboard-enter space-y-6" key="dashboard-v3">
      {/* Summary row: what happened + where to go */}
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="max-w-xl">
          <p className="mb-1.5 inline-flex items-center gap-1.5 rounded-full bg-accentSoft px-2.5 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-accent">
            <span className="relative flex h-1.5 w-1.5" aria-hidden="true">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-accent opacity-60" />
              <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-accent" />
            </span>
            Live storefront
          </p>
          <p className="text-sm text-muted">
            {chartTotal === 0
              ? 'A quiet week. Check seller applications below, then review the order pipeline.'
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

      {/* KPI strip: one unified card with hairline dividers */}
      <section aria-label="Key metrics" className="grid grid-cols-2 gap-px overflow-hidden rounded-2xl border border-border bg-border shadow-card xl:grid-cols-4">
        {statsLoading ? (
          Array.from({ length: 4 }).map((_, i) => <StatCardSkeleton key={i} />)
        ) : (
          <>
            <StatCard
              bare
              tone="primary"
              Icon={ShoppingCart}
              label="Orders, last 7 days"
              value={stats?.orders7d ?? 0}
              delta={stats?.ordersDelta ?? null}
              formatDelta={(n) => (n === 0 ? 'No change' : `${n > 0 ? '+' : ''}${n}`)}
              caption={`${stats?.totalOrders ?? 0} all time · vs last week`}
              sparkline={<MiniSpark data={spark?.current} color="#8B5A2B" id="miniOrders" />}
            />
            <StatCard
              bare
              tone="teal"
              Icon={Wallet}
              label="Revenue, last 7 days"
              value={formatCurrency(stats?.revenue7d ?? 0)}
              delta={stats?.revenueDelta ?? null}
              formatDelta={(n) => {
                if (n === 0) return 'No change'
                return `${n > 0 ? '+' : '−'}${formatCurrency(Math.abs(Math.round(n)))}`
              }}
              caption="Paid + pending · vs last week"
              sparkline={<MiniSpark data={spark?.current?.map((d) => ({ ...d, count: d.revenue }))} color="#0E7C7B" id="miniRevenue" />}
            />
            <StatCard
              bare
              tone="cocoa"
              Icon={Package}
              label="Live products"
              value={stats?.totalProducts ?? 0}
              caption="Across all stores"
            />
            <StatCard
              bare
              tone={stats?.pendingApplications > 0 ? 'amber' : 'neutral'}
              Icon={Store}
              label="Seller applications"
              value={stats?.pendingApplications ?? 0}
              highlight={(stats?.pendingApplications ?? 0) > 0}
              caption={
                (stats?.pendingApplications ?? 0) > 0
                  ? 'Waiting for review'
                  : 'Queue is clear'
              }
            />
          </>
        )}
      </section>

      {/* Operations strip: order pipeline */}
      <section className="rounded-2xl border border-border bg-white shadow-card ring-1 ring-black/[0.02]">
        <div className="flex items-center justify-between px-5 pb-1 pt-4">
          <h2 className="text-[15px] font-bold text-ink">Order pipeline</h2>
          <Link to="/orders" className="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-[13px] font-semibold text-primary hover:bg-canvas">
            Open orders <ArrowRight size={14} />
          </Link>
        </div>
        <div className="grid grid-cols-2 gap-2 px-3 pb-3 sm:grid-cols-4">
          {pipe.map((p) => {
            const share = pipeTotal > 0 ? Math.round((p.value / pipeTotal) * 100) : 0
            return (
            <Link
              key={p.label}
              to={p.to}
              aria-label={`${p.label}: ${p.value} orders`}
              className="group rounded-xl border border-border/70 px-4 py-3 transition-all hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-card"
            >
              <span className={`flex h-10 w-10 items-center justify-center rounded-xl ${p.tile ?? 'bg-faint text-secondary'}`}>
                <p.Icon size={17} strokeWidth={2} aria-hidden="true" />
              </span>
              <span className="tnum mt-3 block font-mono text-2xl font-semibold leading-none text-ink">
                {p.value}
              </span>
              <span className="mt-1 block text-[13px] font-medium text-muted group-hover:text-ink">{p.label}</span>
              <span className="mt-2 block h-1 overflow-hidden rounded-full bg-canvas" aria-hidden="true">
                <span className="block h-full rounded-full bg-current opacity-30" style={{ width: `${share}%` }} />
              </span>
            </Link>
            )
          })}
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
                      <th className="px-4 py-2.5 text-[11px] font-bold uppercase tracking-[0.08em] text-muted">Order</th>
                      <th className="px-4 py-2.5 text-[11px] font-bold uppercase tracking-[0.08em] text-muted">Customer</th>
                      <th className="px-4 py-2.5 text-right text-[11px] font-bold uppercase tracking-[0.08em] text-muted">Total</th>
                      <th className="px-4 py-2.5 text-[11px] font-bold uppercase tracking-[0.08em] text-muted">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-canvas">
                    {recentOrders.map((order) => (
                      <tr key={order.id} className="transition-colors hover:bg-canvas/70">
                        <td className="px-4 py-3">
                          <span className="tnum block font-mono text-xs font-semibold text-ink">#{shortId(order.id)}</span>
                          <span className="tnum block text-[11px] text-muted">{formatDate(order.created_at)}</span>
                        </td>
                        <td className="max-w-[180px] px-4 py-3">
                          <span className="block truncate text-sm font-medium text-ink">{order.stores?.name ?? order.profiles?.full_name ?? 'Walk-in'}</span>
                          {order.stores?.name && order.profiles?.full_name && (
                            <span className="block truncate text-xs text-muted">{order.profiles.full_name}</span>
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
                  Orders from the storefront will appear here.
                </p>
                <Link
                  to="/products"
                  className="mt-4 rounded-lg bg-secondary px-3.5 py-2 text-[13px] font-semibold text-white hover:bg-primaryDeep"
                >
                  View products
                </Link>
              </div>
            )}
          </div>
        </section>

        {/* Attention queue */}
        <section className="rounded-2xl border border-border bg-white shadow-card xl:col-span-2">
          <div className="flex items-center justify-between px-5 py-4">
            <h2 className="text-[15px] font-bold text-ink">
              Seller applications
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
                <span className="mb-3 flex h-11 w-11 items-center justify-center rounded-xl bg-faint text-secondary">
                  <Users size={20} strokeWidth={1.75} />
                </span>
                <p className="text-sm font-semibold text-ink">No pending applications</p>
                <p className="mt-1 max-w-xs text-[13px] text-muted">
                  New applications show up here. You can approve or decline without leaving this page.
                </p>
              </div>
            )}
          </div>
        </section>
      </div>

      {/* Trend charts */}
      <div className="grid gap-6 xl:grid-cols-2">
        <TrendPanel
          title="Orders, last 7 days"
          lead={`${chartTotal} orders total`}
          total={`${formatCurrency(spark?.totalRevenue ?? 0)} revenue`}
          data={trend.orders}
          stroke="#8B5A2B"
          gradientId="ordersFill"
          isEmpty={chartTotal === 0}
          emptyTitle="Nothing to plot yet"
          emptyBody="This chart fills in once storefront orders arrive."
          integerAxis
        />
        <TrendPanel
          title="Revenue, last 7 days"
          total={`${formatCurrency(revenueTotal)} total`}
          data={trend.revenue}
          stroke="#0E7C7B"
          gradientId="revenueFill"
          isEmpty={revenueTotal === 0}
          emptyTitle="No revenue yet"
          emptyBody="Paid orders will appear here."
          yAxisWidth={52}
          yTickFormatter={pesoTick}
          tooltipFormatter={(v) => [formatCurrency(v), 'Revenue']}
        />
      </div>
    </div>
  )
}
