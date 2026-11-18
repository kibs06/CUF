import { useState } from 'react'
import { Link } from 'react-router-dom'
import TrendPanel from '../components/ui/TrendPanel.jsx'
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
import { formatDate, formatCurrency, getInitials, shortId } from '../lib/constants'
import { AlertTriangle, ArrowRight, Package, ShieldCheck } from 'lucide-react'

const peso = String.fromCharCode(0x20B1)
const pesoTick = (v) => (v >= 1000 ? `${peso}${Math.round(v / 100) / 10}k` : `${peso}${v}`)

function signedNumber(value) {
  if (value == null) return null
  if (value === 0) return 'No change'
  return `${value > 0 ? '+' : '\u2212'}${Math.abs(value)}`
}

function signedCurrency(value) {
  if (value == null) return null
  if (value === 0) return 'No change'
  return `${value > 0 ? '+' : '\u2212'}${formatCurrency(Math.abs(Math.round(value)))}`
}

function Delta({ value, children }) {
  if (value == null) return null
  const tone = value === 0 ? 'text-muted' : value > 0 ? 'text-accent' : 'text-error'
  return <span className={`font-semibold ${tone}`}>{children}</span>
}

function Metric({ label, value, footer, loading = false }) {
  return (
    <div className="bg-card p-4">
      <p className="text-[12px] font-medium text-muted">{label}</p>
      {loading ? (
        <div className="mt-2 h-6 w-20 animate-pulse rounded bg-canvas" />
      ) : (
        <p className="mt-1.5 font-mono text-[24px] font-semibold leading-none tracking-tight text-ink tnum">
          {value}
        </p>
      )}
      <div className="mt-2 min-h-[18px] text-[12px] leading-relaxed text-muted">
        {loading ? <div className="h-3 w-32 animate-pulse rounded bg-canvas" /> : footer}
      </div>
    </div>
  )
}

function CustomerAvatar({ name, email }) {
  return (
    <span
      aria-hidden="true"
      className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-canvas text-[10px] font-bold text-secondary ring-1 ring-border"
    >
      {getInitials(name, email)}
    </span>
  )
}

function OrdersSkeleton() {
  return (
    <div className="divide-y divide-border border-t border-border">
      {Array.from({ length: 5 }).map((_, index) => (
        <div key={index} className="flex items-center gap-3 px-4 py-3">
          <div className="h-8 w-8 animate-pulse rounded-full bg-canvas" />
          <div className="flex-1 space-y-1.5">
            <div className="h-3 w-32 animate-pulse rounded bg-canvas" />
            <div className="h-2.5 w-24 animate-pulse rounded bg-canvas" />
          </div>
          <div className="h-5 w-20 animate-pulse rounded bg-canvas" />
        </div>
      ))}
    </div>
  )
}

function ApplicationsSkeleton() {
  return (
    <div className="space-y-4 px-4 pb-4">
      {Array.from({ length: 2 }).map((_, index) => (
        <div key={index} className="space-y-2">
          <div className="flex items-center gap-2.5">
            <div className="h-8 w-8 animate-pulse rounded-full bg-canvas" />
            <div className="space-y-1.5">
              <div className="h-3 w-28 animate-pulse rounded bg-canvas" />
              <div className="h-2.5 w-36 animate-pulse rounded bg-canvas" />
            </div>
          </div>
          <div className="h-8 animate-pulse rounded-lg bg-canvas" />
        </div>
      ))}
    </div>
  )
}

export default function Dashboard() {
  const { showToast } = useToast()
  const { data: stats, isLoading: statsLoading } = useDashboardStats()
  const { data: pendingApps, isLoading: pendingLoading } = useRecentPendingApplications(4)
  const { data: recentOrders, isLoading: ordersLoading } = useRecentOrders(6)
  const { data: spark } = useOrdersSparkline(14)
  const { data: pipeline, isLoading: pipelineLoading } = useOrderPipeline()
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
    const series = (key) =>
      current.map((entry, index) => ({
        date: entry.date,
        value: entry[key] ?? 0,
        previous: tail[index]?.[key] ?? null,
      }))
    return { orders: series('count'), revenue: series('revenue') }
  })()

  const chartTotal = spark?.total ?? 0
  const revenueTotal = spark?.totalRevenue ?? 0
  const orders7d = stats?.orders7d ?? chartTotal
  const revenue7d = stats?.revenue7d ?? revenueTotal
  const avgOrder = orders7d > 0 ? revenue7d / orders7d : 0
  const pending = Math.max(stats?.pendingApplications ?? 0, pendingApps?.length ?? 0)
  const needsAction = pipeline?.needsAction ?? 0

  const pipe = [
    {
      key: 'needsAction',
      label: 'Needs action',
      value: pipeline?.needsAction ?? 0,
      caption: 'Awaiting confirmation',
      to: '/orders?status=pending',
      hex: '#9A6B0A',
      alert: true,
    },
    {
      key: 'inKitchen',
      label: 'In preparation',
      value: pipeline?.inKitchen ?? 0,
      caption: 'Packing or ready',
      to: '/orders?status=preparing',
      hex: '#8B5A2B',
    },
    {
      key: 'onTheWay',
      label: 'Shipped',
      value: pipeline?.onTheWay ?? 0,
      caption: 'On the way',
      to: '/orders?status=shipped',
      hex: '#4E6E8E',
    },
    {
      key: 'done',
      label: 'Delivered',
      value: pipeline?.done ?? 0,
      caption: 'Completed',
      to: '/orders?status=delivered',
      hex: '#0E7C7B',
    },
  ]
  const pipeTotal = pipe.reduce((sum, stage) => sum + stage.value, 0)
  const openCount = pipe.slice(0, 3).reduce((sum, stage) => sum + stage.value, 0)

  const hasAttention = needsAction > 0 || pending > 0
  const hasSellerQueue = pending > 0 || (pendingApps?.length ?? 0) > 0
  const attentionTitle =
    needsAction > 0
      ? `${needsAction} order${needsAction === 1 ? '' : 's'} need confirmation`
      : `${pending} seller application${pending === 1 ? '' : 's'} need review`
  const attentionBody =
    needsAction > 0 && pending > 0
      ? `${pending} seller application${pending === 1 ? '' : 's'} also waiting for review.`
      : needsAction > 0
        ? 'Confirm or cancel them from the order queue.'
        : 'Review the application before approving access.'
  const attentionHref = needsAction > 0 ? '/orders?status=pending' : '/seller-applications'
  const attentionLabel = needsAction > 0 ? 'Review orders' : 'Review applications'

  const ordersFooter =
    stats?.ordersDelta == null ? (
      `${stats?.totalOrders ?? 0} all time`
    ) : (
      <>
        <Delta value={stats.ordersDelta}>{signedNumber(stats.ordersDelta)}</Delta> vs prior ·{' '}
        {stats?.totalOrders ?? 0} all time
      </>
    )

  const revenueFooter =
    stats?.revenueDelta == null ? (
      `${orders7d} orders`
    ) : (
      <>
        <Delta value={stats.revenueDelta}>{signedCurrency(stats.revenueDelta)}</Delta> vs prior ·{' '}
        {formatCurrency(avgOrder)} avg.
      </>
    )

  return (
    <div className="space-y-4">
      {hasAttention && (
        <section
          aria-label="Needs attention"
          className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-pending/30 bg-pendingSoft/45 px-4 py-3"
        >
          <div className="flex min-w-0 items-start gap-2.5">
            <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-pending/10 text-pending">
              <AlertTriangle size={15} aria-hidden="true" />
            </span>
            <div className="min-w-0">
              <p className="text-[13px] font-semibold text-ink">{attentionTitle}</p>
              <p className="mt-0.5 text-[12px] leading-relaxed text-muted">{attentionBody}</p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            {needsAction > 0 && pending > 0 && (
              <Link
                to="/seller-applications"
                className="text-[12px] font-semibold text-secondary hover:underline"
              >
                Seller applications
              </Link>
            )}
            <Link
              to={attentionHref}
              className="inline-flex h-9 w-full items-center justify-center gap-1.5 rounded-lg bg-secondary px-3.5 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep sm:w-auto"
            >
              {attentionLabel} <ArrowRight size={13} aria-hidden="true" />
            </Link>
          </div>
        </section>
      )}

      <section
        aria-label="Marketplace summary"
        className="grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-border bg-border lg:grid-cols-4"
      >
        <Metric label="Orders, 7 days" value={orders7d} footer={ordersFooter} loading={statsLoading} />
        <Metric
          label="Revenue, 7 days"
          value={formatCurrency(revenue7d)}
          footer={revenueFooter}
          loading={statsLoading}
        />
        <Metric
          label="Open orders"
          value={openCount}
          loading={pipelineLoading}
          footer={
            needsAction > 0 ? (
              <>
                <span className="font-semibold text-pending">{needsAction}</span> awaiting confirmation
              </>
            ) : (
              'Nothing awaiting confirmation'
            )
          }
        />
        <Metric
          label="Live products"
          value={stats?.totalProducts ?? 0}
          loading={statsLoading}
          footer="Across all stores"
        />
      </section>

      <section className="overflow-hidden rounded-xl border border-border bg-card">
        <div className="flex flex-wrap items-start justify-between gap-2 px-4 py-3.5">
          <div>
            <h2 className="text-[15px] font-bold text-ink">Order workflow</h2>
            <p className="mt-0.5 text-[12px] text-muted">
              {pipelineLoading
                ? 'Loading the pipeline…'
                : `${pipeTotal} orders · ${openCount} open · ${pipeline?.done ?? 0} delivered`}
            </p>
          </div>
          <Link
            to="/orders"
            className="inline-flex h-9 items-center gap-1 text-[12px] font-semibold text-primary hover:underline"
          >
            Open orders <ArrowRight size={13} aria-hidden="true" />
          </Link>
        </div>

        <div className="px-4">
          <div className="flex h-1.5 overflow-hidden rounded-full bg-canvas" aria-hidden="true">
            {!pipelineLoading &&
              pipe.map((stage) => {
                const share = pipeTotal > 0 ? (stage.value / pipeTotal) * 100 : 0
                return share > 0 ? (
                  <span
                    key={stage.key}
                    className="h-full first:rounded-l-full last:rounded-r-full"
                    style={{ width: `${share}%`, backgroundColor: stage.hex }}
                  />
                ) : null
              })}
          </div>
        </div>

        <div className="grid grid-cols-2 gap-x-3 px-2 pb-2 pt-1 sm:grid-cols-4">
          {pipe.map((stage) => (
            <Link
              key={stage.key}
              to={stage.to}
              aria-label={`${stage.label}: ${stage.value} orders`}
              className="group flex min-h-11 items-start justify-between gap-2 rounded-lg px-2 py-2.5 transition-colors hover:bg-canvas"
            >
              <span className="min-w-0">
                <span className="flex items-center gap-1.5 text-[12px] font-semibold text-secondary">
                  <span
                    className="h-1.5 w-1.5 shrink-0 rounded-full"
                    style={{ backgroundColor: stage.hex }}
                    aria-hidden="true"
                  />
                  {stage.label}
                </span>
                <span className="mt-0.5 block text-[12px] text-muted">{stage.caption}</span>
              </span>
              <span
                className={`shrink-0 font-mono text-[17px] font-semibold leading-none tnum ${
                  stage.alert && stage.value > 0 ? 'text-pending' : 'text-ink'
                }`}
              >
                {pipelineLoading ? (
                  <span className="inline-block h-4 w-6 animate-pulse rounded bg-canvas" />
                ) : (
                  stage.value
                )}
              </span>
            </Link>
          ))}
        </div>
      </section>

      <div
        className={`grid gap-4 ${
          hasSellerQueue ? 'xl:grid-cols-[minmax(0,1.65fr)_minmax(310px,1fr)]' : ''
        }`}
      >
        <section className="overflow-hidden rounded-xl border border-border bg-card">
          <div className="flex items-center justify-between gap-3 px-4 py-3.5">
            <div>
              <h2 className="text-[15px] font-bold text-ink">Latest orders</h2>
              <p className="mt-0.5 text-[12px] text-muted">Newest first</p>
            </div>
            <Link
              to="/orders"
              className="inline-flex h-9 items-center gap-1 text-[12px] font-semibold text-primary hover:underline"
            >
              All orders <ArrowRight size={13} aria-hidden="true" />
            </Link>
          </div>

          {ordersLoading ? (
            <OrdersSkeleton />
          ) : recentOrders?.length > 0 ? (
            <>
              <div className="hidden md:block">
                <table className="w-full text-left">
                  <thead className="border-y border-border bg-canvas/60">
                    <tr>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Order</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Customer</th>
                      <th className="px-4 py-2 text-right text-[12px] font-semibold text-muted">
                        Total
                      </th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {recentOrders.map((order) => {
                      const customer = order.profiles?.full_name ?? 'Walk-in customer'
                      return (
                        <tr key={order.id} className="admin-list-item admin-list-row">
                          <td className="px-4 py-3">
                            <span className="tnum block font-mono text-[12px] font-semibold text-ink">
                              #{shortId(order.id)}
                            </span>
                            <span className="tnum mt-0.5 block text-[12px] text-muted">
                              {formatDate(order.created_at)}
                            </span>
                          </td>
                          <td className="max-w-[240px] px-4 py-3">
                            <div className="flex min-w-0 items-center gap-2.5">
                              <CustomerAvatar
                                name={order.profiles?.full_name}
                                email={order.profiles?.email}
                              />
                              <div className="min-w-0">
                                <p className="truncate text-[12.5px] font-semibold text-ink">
                                  {customer}
                                </p>
                                <p className="truncate text-[12px] text-muted">
                                  {order.stores?.name ?? 'Store unavailable'}
                                </p>
                              </div>
                            </div>
                          </td>
                          <td className="tnum px-4 py-3 text-right font-mono text-[12.5px] text-ink">
                            {formatCurrency(order.total_amount)}
                          </td>
                          <td className="px-4 py-3">
                            <Badge label={order.status} variant={order.status} />
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>

              <div className="divide-y divide-border border-t border-border md:hidden">
                {recentOrders.map((order) => {
                  const customer = order.profiles?.full_name ?? 'Walk-in customer'
                  return (
                    <div key={order.id} className="admin-list-item admin-list-card px-4 py-3">
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex min-w-0 items-center gap-2.5">
                          <CustomerAvatar
                            name={order.profiles?.full_name}
                            email={order.profiles?.email}
                          />
                          <div className="min-w-0">
                            <p className="truncate text-[12.5px] font-semibold text-ink">
                              {customer}
                            </p>
                            <p className="truncate text-[12px] text-muted">
                              {order.stores?.name ?? 'Store unavailable'}
                            </p>
                          </div>
                        </div>
                        <p className="tnum shrink-0 font-mono text-[12.5px] text-ink">
                          {formatCurrency(order.total_amount)}
                        </p>
                      </div>
                      <div className="mt-2 flex items-center justify-between gap-2 text-[12px] text-muted">
                        <span className="tnum font-mono">
                          #{shortId(order.id)} · {formatDate(order.created_at)}
                        </span>
                        <Badge label={order.status} variant={order.status} />
                      </div>
                    </div>
                  )
                })}
              </div>
            </>
          ) : (
            <div className="border-t border-border px-5 py-12 text-center">
              <Package size={20} className="mx-auto text-muted" aria-hidden="true" />
              <p className="mt-2 text-[13px] font-semibold text-ink">No orders yet</p>
              <p className="mt-1 text-[12px] text-muted">
                Orders from the storefront will appear here.
              </p>
              <Link
                to="/products"
                className="mt-3 inline-flex h-8 items-center rounded-lg bg-secondary px-3 text-[12px] font-semibold text-white hover:bg-primaryDeep"
              >
                View products
              </Link>
            </div>
          )}
        </section>

        {hasSellerQueue && (
          <aside className="overflow-hidden rounded-xl border border-border bg-card">
            <div className="flex items-center justify-between gap-3 px-4 py-3.5">
            <div>
              <h2 className="flex items-center gap-1.5 text-[15px] font-bold text-ink">
                Seller applications
                {(pendingApps?.length ?? 0) > 0 && (
                  <span className="font-mono text-[12px] font-semibold text-muted">
                    {pendingApps.length}
                  </span>
                )}
              </h2>
              <p className="mt-0.5 text-[12px] text-muted">
                {pendingLoading
                  ? 'Loading applications…'
                  : pendingApps?.length > 0
                    ? 'Newest first'
                    : 'Nothing waiting'}
              </p>
            </div>
            <Link
              to="/seller-applications"
              className="inline-flex h-9 items-center gap-1 text-[12px] font-semibold text-primary hover:underline"
            >
              View all <ArrowRight size={13} aria-hidden="true" />
            </Link>
          </div>

          {pendingLoading ? (
            <ApplicationsSkeleton />
          ) : pendingApps?.length > 0 ? (
            <ul className="divide-y divide-border border-t border-border">
              {pendingApps.slice(0, 3).map((app) => (
                <li key={app.id} className="admin-list-item admin-list-card px-4 py-3">
                  <div className="flex items-start gap-2.5">
                    <AvatarInitials name={app.full_name} email={app.email} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[12.5px] font-semibold text-ink">
                        {app.full_name}
                      </p>
                      <p className="truncate text-[12px] text-muted">{app.email}</p>
                      <p className="mt-0.5 text-[12px] text-muted">
                        Applied {formatDate(app.created_at)}
                      </p>
                    </div>
                  </div>
                  <div className="mt-2.5 flex gap-2">
                    <button
                      type="button"
                      disabled={loadingId === app.id}
                      onClick={() => handleApprove(app.id)}
                      className="h-8 flex-1 rounded-lg bg-accent px-3 text-[12px] font-semibold text-white transition-colors hover:brightness-110 disabled:opacity-50"
                    >
                      Approve
                    </button>
                    <button
                      type="button"
                      disabled={loadingId === app.id}
                      onClick={() => handleReject(app.id)}
                      className="h-8 flex-1 rounded-lg border border-error/35 px-3 text-[12px] font-semibold text-error transition-colors hover:bg-errorSoft disabled:opacity-50"
                    >
                      Decline
                    </button>
                  </div>
                </li>
              ))}
            </ul>
            ) : (
              <div className="border-t border-border px-5 py-8 text-center">
                <ShieldCheck size={19} className="mx-auto text-muted" aria-hidden="true" />
                <p className="mt-2 text-[13px] font-semibold text-ink">No pending applications</p>
                <p className="mt-1 text-[12px] text-muted">
                  New seller applications will appear here.
                </p>
              </div>
            )}
          </aside>
        )}
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <TrendPanel
          title="Orders"
          lead="Daily order volume · last 7 days"
          total={`${chartTotal} orders`}
          data={trend.orders}
          stroke="#8B5A2B"
          gradientId="ordersFill"
          isEmpty={chartTotal === 0}
          emptyTitle="Nothing to plot yet"
          emptyBody="This chart fills in once storefront orders arrive."
          integerAxis
        />
        <TrendPanel
          title="Revenue"
          lead="Captured order value · last 7 days"
          total={formatCurrency(revenueTotal)}
          data={trend.revenue}
          stroke="#0E7C7B"
          gradientId="revenueFill"
          isEmpty={revenueTotal === 0}
          emptyTitle="No revenue yet"
          emptyBody="Paid orders will appear here."
          yAxisWidth={52}
          yTickFormatter={pesoTick}
          tooltipFormatter={(value) => [formatCurrency(value), 'Revenue']}
        />
      </div>
    </div>
  )
}
