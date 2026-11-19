import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import TrendPanel from '../components/ui/TrendPanel.jsx'
import Badge from '../components/ui/Badge.jsx'
import AnimatedNumber from '../components/ui/AnimatedNumber.jsx'
import AvatarInitials from '../components/ui/AvatarInitials.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import Tooltip from '../components/ui/Tooltip.jsx'
import {
  PAID_PERIODS,
  useDashboardStats,
  paidTotals,
  usePaidSalesLedger,
  useRequestTable,
  useRecentPendingApplications,
  useRecentOrders,
  useOrdersSparkline,
  useOrderPipeline,
  useApproveSeller,
  useRejectSeller,
} from '../hooks/useDashboard.js'
import { usePayables } from '../hooks/useManualGcash.js'
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
  const [period, setPeriod] = useState('week')
  const activePeriod = PAID_PERIODS.find((option) => option.key === period) ?? PAID_PERIODS[0]
  const periodWord = activePeriod.label.toLowerCase()
  const windowLabel = activePeriod.days == null ? 'all time' : `last ${activePeriod.days} days`
  const [channels, setChannels] = useState({ pos: true, online: true })
  const toggleChannel = (key) =>
    setChannels((current) => {
      const next = { ...current, [key]: !current[key] }
      // A total with neither channel selected would always read zero; keep at
      // least one on rather than letting the figure become meaningless.
      return next.pos || next.online ? next : current
    })
  // The charts always plot a fixed number of days, so Overall only ever shows
  // the trailing year — the caption has to say so rather than claim "all time".
  const chartLabel = `last ${activePeriod.days ?? 365} days`

  const { data: stats, isLoading: statsLoading } = useDashboardStats(period)
  const { data: pendingApps, isLoading: pendingLoading } = useRecentPendingApplications(4)
  const { data: recentOrders, isLoading: ordersLoading } = useRecentOrders(6, period)
  const { data: spark } = useOrdersSparkline(activePeriod.days ?? 365)
  const { data: pipeline, isLoading: pipelineLoading } = useOrderPipeline(period)
  const { data: paidRows, isLoading: paidLoading } = usePaidSalesLedger()
  const paid = useMemo(
    () => paidTotals(paidRows ?? [], period, channels),
    [paidRows, period, channels],
  )
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
  const orderValueTotal = spark?.totalRevenue ?? 0
  const ordersInWindow = stats?.ordersWindow ?? chartTotal
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
  const openCount = pipe.slice(0, 3).reduce((sum, stage) => sum + stage.value, 0)

  const { data: requestRows, isLoading: requestsLoading } = useRequestTable()
  const { data: payables = [] } = usePayables()
  const [requestTab, setRequestTab] = useState('refunds')

  const openRequests = requestRows ?? []
  const refundRequests = openRequests.filter((row) => row.kind === 'refund')
  const reportRequests = openRequests.filter((row) => row.kind === 'report')
  const requestTabs = {
    list: [
      { key: 'refunds', label: 'Refunds', count: refundRequests.length, to: '/refunds' },
      { key: 'reports', label: 'Reports', count: reportRequests.length, to: '/reports' },
      { key: 'payouts', label: 'Payouts', count: payables.length, to: '/payouts' },
    ],
    copy: {
      refunds: 'Refund requests waiting to be paid back.',
      reports: 'Open customer and seller reports, high priority first.',
      payouts: 'Stores owed money, net of delivery and commission.',
    },
    headers: {
      refunds: ['Order', 'Customer', 'Amount', 'Status'],
      reports: ['Report', 'Reporter', 'Priority', 'Status'],
      payouts: ['Store', 'Orders', 'Net payout', 'Status'],
    },
    rows: { refunds: refundRequests, reports: reportRequests, payouts: payables },
    empty: {
      refunds: 'No refunds waiting.',
      reports: 'No open reports.',
      payouts: 'No store is owed anything right now.',
    },
  }

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

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-[12px] text-muted">
          Orders, workflow, lists and totals below all follow this timeframe.
        </p>
        <div
          role="group"
          aria-label="Dashboard timeframe"
          className="flex flex-wrap items-center gap-1 rounded-xl border border-border bg-canvas p-1"
        >
          {PAID_PERIODS.map((option) => {
            const active = period === option.key
            return (
              <Tooltip key={option.key} label={option.hint}>
                <button
                  type="button"
                  onClick={() => setPeriod(option.key)}
                  aria-pressed={active}
                  className={`h-8 shrink-0 rounded-lg px-3 text-[12px] font-semibold transition-colors ${
                    active
                      ? 'bg-secondary text-white'
                      : 'text-muted hover:bg-card hover:text-ink'
                  }`}
                >
                  {option.label}
                </button>
              </Tooltip>
            )
          })}
        </div>
      </div>

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

      <section aria-label="Total paid">
        <div className="overflow-hidden rounded-xl border border-border bg-card">
          <div className="flex flex-wrap items-start justify-between gap-3 border-b border-border px-4 py-3.5">
            <div>
              <h2 className="text-[15px] font-bold text-ink">Total paid</h2>
              <p className="mt-0.5 text-[12px] text-muted">
                Money that actually arrived — POS and online. Unpaid and pending
                orders are not counted.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-[12px] font-medium text-muted">Channels</span>
              <div
                role="group"
                aria-label="Channels included in the total"
                className="flex items-center gap-1 rounded-xl border border-border bg-canvas p-1"
              >
                <Tooltip label="Include pay-at-the-counter sales.">
                  <button
                    type="button"
                    aria-pressed={channels.pos}
                    onClick={() => toggleChannel('pos')}
                    className={`h-7 shrink-0 rounded-lg px-2.5 text-[12px] font-semibold transition-colors ${
                      channels.pos
                        ? 'bg-secondary text-white'
                        : 'text-muted hover:bg-card hover:text-ink'
                    }`}
                  >
                    POS
                  </button>
                </Tooltip>
                <Tooltip label="Include sales paid through the app.">
                  <button
                    type="button"
                    aria-pressed={channels.online}
                    onClick={() => toggleChannel('online')}
                    className={`h-7 shrink-0 rounded-lg px-2.5 text-[12px] font-semibold transition-colors ${
                      channels.online
                        ? 'bg-secondary text-white'
                        : 'text-muted hover:bg-card hover:text-ink'
                    }`}
                  >
                    Online
                  </button>
                </Tooltip>
              </div>
            </div>
          </div>

          <div className="flex flex-wrap items-end gap-x-10 gap-y-4 px-4 py-4">
            <div className="min-w-[200px]">
              <p className="text-[12px] font-medium text-muted">
                {paid?.period?.hint ?? 'Paid sales'}
              </p>
              {paidLoading ? (
                <div className="mt-2 h-8 w-40 animate-pulse rounded bg-canvas" />
              ) : (
                <p className="tnum mt-1.5 font-mono text-[32px] font-semibold leading-none tracking-tight text-ink">
                  <AnimatedNumber value={paid?.total ?? 0} format={formatCurrency} />
                </p>
              )}
              <p className="mt-2 text-[12px] text-muted">
                {paidLoading ? (
                  'Adding up the paid sales…'
                ) : (
                  <>
                    <AnimatedNumber
                      value={paid.count}
                      format={(v) => Math.round(v).toLocaleString('en-PH')}
                    />{' '}
                    paid sale{paid.count === 1 ? '' : 's'}
                    {paid.capped ? ' (first 10,000 counted)' : ''}
                  </>
                )}
              </p>
              <p className="mt-1 text-[12px] text-muted">
                {paidLoading ? (
                  '\u00a0'
                ) : (
                  <>
                    {paid.delta != null && (
                      <>
                        <Delta value={paid.delta}>
                          <AnimatedNumber value={paid.delta} format={signedCurrency} />
                        </Delta>{' '}
                        vs prior {paid.period.days} days ·{' '}
                      </>
                    )}
                    <span className="tnum">
                      <AnimatedNumber value={paid.allTime} format={formatCurrency} />
                    </span>{' '}
                    all time
                  </>
                )}
              </p>
            </div>

            <dl className="flex flex-wrap gap-x-10 gap-y-3">
              <div>
                <dt className="text-[12px] font-medium text-muted">Average sale</dt>
                <dd className="tnum mt-1 font-mono text-[18px] font-semibold text-ink">
                  {paidLoading ? (
                    '—'
                  ) : (
                    <AnimatedNumber value={paid?.average ?? 0} format={formatCurrency} />
                  )}
                </dd>
              </div>
            </dl>
          </div>
        </div>
      </section>

      <section
        aria-label="Marketplace summary"
        className="grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-border bg-border lg:grid-cols-3"
      >
        <Metric
          label={`Orders, ${periodWord}`}
          value={
            <AnimatedNumber
              value={ordersInWindow}
              format={(v) => Math.round(v).toLocaleString()}
            />
          }
          footer={ordersFooter}
          loading={statsLoading}
        />
        <Metric
          label="Open orders"
          value={<AnimatedNumber value={openCount} format={(v) => Math.round(v).toLocaleString()} />}
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
          value={
            <AnimatedNumber
              value={stats?.totalProducts ?? 0}
              format={(v) => Math.round(v).toLocaleString()}
            />
          }
          loading={statsLoading}
          footer="All time · all stores"
        />
      </section>

      <div className="grid gap-4 xl:grid-cols-2">
        <section className="overflow-hidden rounded-xl border border-border bg-card">
          <div className="flex items-center justify-between gap-3 px-4 py-3.5">
            <div>
              <h2 className="text-[15px] font-bold text-ink">Latest orders</h2>
              <p className="mt-0.5 text-[12px] text-muted">Newest first · {windowLabel}</p>
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

        <section
          aria-label="Reports and requests"
          className="flex flex-col overflow-hidden rounded-xl border border-border bg-card"
        >
          <div className="flex items-start justify-between gap-3 px-4 py-3.5">
            <div className="min-w-0">
              <h2 className="text-[15px] font-bold text-ink">Reports and requests</h2>
              <p className="mt-0.5 text-[12px] text-muted">{requestTabs.copy[requestTab]}</p>
            </div>
            <div
              role="tablist"
              aria-label="Request type"
              className="flex shrink-0 items-center gap-1 rounded-xl border border-border bg-canvas p-1"
            >
              {requestTabs.list.map((tab) => {
                const active = requestTab === tab.key
                return (
                  <button
                    key={tab.key}
                    type="button"
                    role="tab"
                    aria-selected={active}
                    onClick={() => setRequestTab(tab.key)}
                    className={`flex h-7 items-center gap-1.5 whitespace-nowrap rounded-lg px-2.5 text-[12px] font-semibold transition-colors ${
                      active ? 'bg-secondary text-white' : 'text-muted hover:text-ink'
                    }`}
                  >
                    {tab.label}
                    <span
                      className={`tnum text-[11px] ${active ? 'text-white/70' : 'text-muted'}`}
                    >
                      {tab.count}
                    </span>
                  </button>
                )
              })}
            </div>
          </div>

          <div className="min-h-0 flex-1">
            <table className="w-full text-left">
              <thead className="border-y border-border bg-canvas/60">
              <tr>
                {requestTabs.headers[requestTab].map((label) => (
                  <th
                    key={label}
                    className={`px-4 py-2 text-[12px] font-semibold text-muted ${
                      label === 'Amount' || label === 'Net payout' ? 'text-right' : ''
                    }`}
                  >
                    {label}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {requestsLoading ? (
                <tr>
                  <td colSpan={4} className="px-4 py-4">
                    <div className="h-4 w-full animate-pulse rounded bg-canvas" />
                  </td>
                </tr>
              ) : (requestTabs.rows[requestTab] ?? []).length === 0 ? (
                <tr>
                  <td colSpan={4} className="px-4 py-6 text-center text-[12px] text-muted">
                    {requestTabs.empty[requestTab]}
                  </td>
                </tr>
              ) : requestTab === 'refunds' ? (
                requestTabs.rows.refunds.map((row) => (
                  <tr key={row.id} className="admin-list-item admin-list-row">
                    <td className="px-4 py-3">
                      <span className="tnum block font-mono text-[12px] font-semibold text-ink">
                        {row.title}
                      </span>
                      <span className="tnum mt-0.5 block text-[12px] text-muted">
                        {row.at ? formatDate(row.at) : 'No date'}
                      </span>
                    </td>
                    <td className="max-w-[180px] px-4 py-3">
                      <div className="flex min-w-0 items-center gap-2.5">
                        <CustomerAvatar name={row.who} email={row.email} />
                        <p className="truncate text-[12.5px] font-semibold text-ink">{row.who}</p>
                      </div>
                    </td>
                    <td className="tnum px-4 py-3 text-right font-mono text-[12.5px] text-ink">
                      {formatCurrency(row.amount ?? 0)}
                    </td>
                    <td className="px-4 py-3">
                      <Badge label="awaiting refund" variant="pending" />
                    </td>
                  </tr>
                ))
              ) : requestTab === 'reports' ? (
                requestTabs.rows.reports.map((row) => (
                  <tr key={row.id} className="admin-list-item admin-list-row">
                    <td className="px-4 py-3">
                      <p className="truncate text-[12.5px] font-semibold capitalize text-ink">
                        {row.title}
                      </p>
                      <p className="tnum mt-0.5 text-[12px] text-muted">
                        {row.at ? formatDate(row.at) : 'No date'}
                      </p>
                    </td>
                    <td className="max-w-[180px] px-4 py-3">
                      <div className="flex min-w-0 items-center gap-2.5">
                        <CustomerAvatar name={row.who} email={row.email} />
                        <div className="min-w-0">
                          <p className="truncate text-[12.5px] font-semibold text-ink">{row.who}</p>
                          <p className="truncate text-[12px] text-muted">
                            {row.email ?? 'No email on file'}
                          </p>
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-[12px] font-semibold">
                      {row.critical ? (
                        <span className="inline-flex items-center gap-1 text-error">
                          <AlertTriangle size={12} aria-hidden="true" /> High
                        </span>
                      ) : (
                        <span className="text-muted">Normal</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <Badge label={row.status} variant="pending" />
                    </td>
                  </tr>
                ))
              ) : (
                requestTabs.rows.payouts.map((row) => (
                  <tr key={row.store_id} className="admin-list-item admin-list-row">
                    <td className="px-4 py-3">
                      <p className="truncate text-[12.5px] font-semibold text-ink">
                        {row.store_name}
                      </p>
                      <p className="mt-0.5 text-[12px] text-muted">
                        commission {formatCurrency(row.platform_fee)}
                      </p>
                    </td>
                    <td className="tnum px-4 py-3 text-[12.5px] text-ink">{row.order_count}</td>
                    <td className="tnum px-4 py-3 text-right font-mono text-[12.5px] text-ink">
                      {formatCurrency(row.net_amount)}
                    </td>
                    <td className="px-4 py-3">
                      <Badge label="owed" variant="pending" />
                    </td>
                  </tr>
                ))
              )}
            </tbody>
            </table>
          </div>

          <div className="flex items-center justify-end border-t border-border px-4 py-2.5">
            <Link
              to={requestTabs.list.find((tab) => tab.key === requestTab)?.to ?? '/reports'}
              className="inline-flex h-9 items-center gap-1 text-[12px] font-semibold text-primary hover:underline"
            >
              All {requestTabs.list.find((tab) => tab.key === requestTab)?.label.toLowerCase()}{' '}
              <ArrowRight size={13} aria-hidden="true" />
            </Link>
          </div>
        </section>
        {hasSellerQueue && (
          <aside className="overflow-hidden rounded-xl border border-border bg-card xl:col-span-2">
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
                    <Tooltip label="Approve this seller application and open their store.">
                      <button
                        type="button"
                        disabled={loadingId === app.id}
                        onClick={() => handleApprove(app.id)}
                        className="h-8 flex-1 rounded-lg bg-accent px-3 text-[12px] font-semibold text-white transition-colors hover:brightness-110 disabled:opacity-50"
                      >
                        Approve
                      </button>
                    </Tooltip>
                    <Tooltip label="Decline the application — the applicant is notified.">
                      <button
                        type="button"
                        disabled={loadingId === app.id}
                        onClick={() => handleReject(app.id)}
                        className="h-8 flex-1 rounded-lg border border-error/35 px-3 text-[12px] font-semibold text-error transition-colors hover:bg-errorSoft disabled:opacity-50"
                      >
                        Decline
                      </button>
                    </Tooltip>
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
          lead={`Daily order volume · ${chartLabel}`}
          total={`${chartTotal} orders`}
          data={trend.orders}
          stroke="#8B5A2B"
          gradientId="ordersFill"
          isEmpty={chartTotal === 0}
          emptyTitle="Nothing to plot yet"
          emptyBody="This chart fills in once storefront orders arrive."
          integerAxis
        />
        {/* Every order placed, paid or not — hence "order value" rather than
            "revenue": the money that actually arrived is the Total paid figure
            at the top of the page, and this chart must not look like a rival
            answer to that question. */}
        <TrendPanel
          title="Order value"
          lead={`Every order placed · ${chartLabel}, paid or not`}
          total={formatCurrency(orderValueTotal)}
          data={trend.revenue}
          stroke="#0E7C7B"
          gradientId="revenueFill"
          isEmpty={orderValueTotal === 0}
          emptyTitle="No orders to plot yet"
          emptyBody="This chart fills in once orders are placed."
          yAxisWidth={52}
          yTickFormatter={pesoTick}
          tooltipFormatter={(value) => [formatCurrency(value), 'Order value']}
        />
      </div>
    </div>
  )
}
