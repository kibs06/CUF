import { useState } from 'react'
import {
  LineChart,
  Line,
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts'
import { useAnalytics } from '../hooks/useAnalytics.js'
import StatusPie3D from '../components/charts/StatusPie3D.jsx'
import TopProducts3D from '../components/charts/TopProducts3D.jsx'
import { ChartSkeleton } from '../components/ui/Skeleton.jsx'
import { ShoppingCart, TrendingUp } from 'lucide-react'

const CHART_COLORS = ['#8B5A2B', '#4ECDC4', '#E8A020', '#D64545', '#3B82F6', '#8B5CF6']
const STATUS_COLORS = {
  pending: '#E8A020',
  placed: '#E8A020',
  confirmed: '#3B82F6',
  preparing: '#3B82F6',
  ready: '#8B5A2B',
  shipped: '#8B5CF6',
  received: '#4ECDC4',
  delivered: '#4ECDC4',
  cancelled: '#D64545',
}

function EmptyChart({ message = 'No data yet' }) {
  return (
    <div className="flex h-64 flex-col items-center justify-center text-[#6B5C4E]">
      <TrendingUp size={32} className="mb-2 opacity-40" />
      <p className="text-sm">{message}</p>
    </div>
  )
}

export default function Analytics() {
  const [days, setDays] = useState(30)
  const { data, isLoading, isError, error } = useAnalytics(days)

  return (
    <div className="space-y-6">
      {/* Period selector pills */}
      <div className="flex gap-2">
        {[7, 30, 90].map((d) => (
          <button
            key={d}
            type="button"
            onClick={() => setDays(d)}
            className={`rounded-xl px-4 py-2 text-sm font-medium transition-all ${
              days === d
                ? 'bg-[#8B5A2B] text-white shadow-sm'
                : 'border border-[#D9D0C7] bg-white text-[#6B5C4E] hover:bg-[#F5F0EB]'
            }`}
          >
            Last {d} days
          </button>
        ))}
      </div>

      {isError && (
        <div className="rounded-2xl border border-[#D9D0C7] bg-white p-8 text-center">
          <p className="text-sm text-[#D64545]">{error.message}</p>
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-2">
        {/* Sales Over Time — orders + revenue on one timeline, dual axis */}
        <div className="lg:col-span-2">
          <ChartCard title="Orders and Revenue">
            {isLoading ? (
              <ChartSkeleton />
            ) : !(data?.salesOverTime ?? []).some((d) => d.orders > 0 || d.revenue > 0) ? (
              <EmptyChart message="No sales in this period" />
            ) : (
              <ResponsiveContainer width="100%" height={280}>
                <AreaChart data={data?.salesOverTime ?? []}>
                  <defs>
                    <linearGradient id="salesOrdersGradient" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#8B5A2B" stopOpacity={0.3} />
                      <stop offset="95%" stopColor="#8B5A2B" stopOpacity={0} />
                    </linearGradient>
                    <linearGradient id="salesRevenueGradient" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#4ECDC4" stopOpacity={0.3} />
                      <stop offset="95%" stopColor="#4ECDC4" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <XAxis dataKey="date" tick={{ fontSize: 11, fill: '#6B5C4E' }} />
                  <YAxis yAxisId="orders" allowDecimals={false} tick={{ fontSize: 11, fill: '#6B5C4E' }} width={32} />
                  <YAxis
                    yAxisId="revenue"
                    orientation="right"
                    tickFormatter={(v) => (v >= 1000 ? `₱${Math.round(v / 100) / 10}k` : `₱${v}`)}
                    tick={{ fontSize: 11, fill: '#6B5C4E' }}
                    width={52}
                  />
                  <Tooltip
                    contentStyle={{ fontFamily: 'DM Sans, sans-serif', borderRadius: '12px', border: '1px solid #D9D0C7' }}
                    formatter={(value, name) =>
                      name === 'Revenue' ? [`₱${Number(value).toLocaleString()}`, name] : [value, name]
                    }
                  />
                  <Legend />
                  <Area yAxisId="orders" type="monotone" dataKey="orders" name="Orders" stroke="#8B5A2B" strokeWidth={2} fill="url(#salesOrdersGradient)" />
                  <Area yAxisId="revenue" type="monotone" dataKey="revenue" name="Revenue" stroke="#4ECDC4" strokeWidth={2} fill="url(#salesRevenueGradient)" />
                </AreaChart>
              </ResponsiveContainer>
            )}
          </ChartCard>
        </div>

        {/* Orders by Status — Highcharts 3D pie */}
        <ChartCard title="Orders by Status">
          {isLoading ? (
            <ChartSkeleton />
          ) : (data?.ordersByStatus ?? []).length === 0 ? (
            <EmptyChart message="No orders yet" />
          ) : (
            <StatusPie3D
              data={data.ordersByStatus}
              colors={data.ordersByStatus.map(
                (entry, i) => STATUS_COLORS[entry.name] ?? CHART_COLORS[i % CHART_COLORS.length],
              )}
            />
          )}
        </ChartCard>

        {/* Top Products — ranked leaderboard */}
        <ChartCard title="Top Products">
          {isLoading ? (
            <ChartSkeleton />
          ) : (data?.topProducts ?? []).length === 0 ? (
            <EmptyChart message="No product data yet" />
          ) : (
            <>
              <TopProducts3D items={data.topProducts} />
              <p className="tnum mt-3 border-t border-border px-1 pt-3 text-xs text-muted">
                {data.topProducts.reduce((s, i) => s + i.count, 0)} units across {data.topProducts.length} product{data.topProducts.length === 1 ? '' : 's'} · last {days} days
              </p>
            </>
          )}
        </ChartCard>

        {/* New Users Over Time */}
        <ChartCard title="New Users Over Time">
          {isLoading ? (
            <ChartSkeleton />
          ) : (data?.usersOverTime ?? []).length === 0 ? (
            <EmptyChart message="No new users in this period" />
          ) : (
            <ResponsiveContainer width="100%" height={260}>
              <AreaChart data={data?.usersOverTime ?? []}>
                <defs>
                  <linearGradient id="usersAreaGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#4ECDC4" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#4ECDC4" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <XAxis dataKey="date" tick={{ fontSize: 11, fill: '#6B5C4E' }} />
                <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: '#6B5C4E' }} />
                <Tooltip contentStyle={{ fontFamily: 'DM Sans, sans-serif', borderRadius: '12px', border: '1px solid #D9D0C7' }} />
                <Legend />
                <Area type="monotone" dataKey="users" name="New Users" stroke="#4ECDC4" strokeWidth={2} fill="url(#usersAreaGradient)" />
              </AreaChart>
            </ResponsiveContainer>
          )}
        </ChartCard>

        {/* Seller Application Trend */}
        <ChartCard title="Seller Application Trend">
          {isLoading ? (
            <ChartSkeleton />
          ) : (data?.sellerApplicationTrend ?? []).length === 0 ? (
            <EmptyChart message="No applications yet" />
          ) : (
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={data?.sellerApplicationTrend ?? []}>
                <XAxis dataKey="month" tick={{ fontSize: 11, fill: '#6B5C4E' }} />
                <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: '#6B5C4E' }} />
                <Tooltip contentStyle={{ fontFamily: 'DM Sans, sans-serif', borderRadius: '12px', border: '1px solid #D9D0C7' }} />
                <Legend />
                <Bar dataKey="pending" name="Pending" fill="#E8A020" />
                <Bar dataKey="approved" name="Approved" fill="#4ECDC4" />
                <Bar dataKey="rejected" name="Rejected" fill="#D64545" />
              </BarChart>
            </ResponsiveContainer>
          )}
        </ChartCard>
      </div>
    </div>
  )
}

function ChartCard({ title, children }) {
  return (
    <div className="rounded-2xl border border-[#D9D0C7] bg-white p-6 shadow-sm">
      <h2 className="mb-4 font-display text-lg font-semibold text-[#3B2314]">{title}</h2>
      {children}
    </div>
  )
}
