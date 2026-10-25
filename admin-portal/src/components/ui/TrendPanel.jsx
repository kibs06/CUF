import {
  AreaChart,
  Area,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
} from 'recharts'

export default function TrendPanel({
  title,
  lead = null,
  total,
  data = [],
  stroke = '#8B5A2B',
  gradientId,
  isEmpty = false,
  emptyTitle,
  emptyBody,
  integerAxis = false,
  yAxisWidth = 36,
  yTickFormatter,
  tooltipFormatter,
}) {
  const hasComparison = data.some((d) => d.previous != null)
  return (
    <section className="rounded-2xl border border-border bg-white p-6 shadow-card">
      <div className="mb-1 flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <h2 className="text-[15px] font-bold text-ink">{title}</h2>
          <p className="mt-0.5 text-[13px] text-muted">
            {lead}
            {hasComparison ? ' (dashed line shows the week before)' : ' (not enough history yet for a comparison)'}
          </p>
        </div>
        <span className="tnum font-mono text-sm font-semibold text-ink">{total}</span>
      </div>
      <div className="h-60">
        {isEmpty ? (
          <div className="flex h-full flex-col items-center justify-center rounded-xl bg-canvas px-6 text-center">
            <p className="text-sm font-semibold text-ink">{emptyTitle}</p>
            <p className="mt-1 max-w-sm text-[13px] text-muted">{emptyBody}</p>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -12 }}>
              <defs>
                <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={stroke} stopOpacity={0.22} />
                  <stop offset="100%" stopColor={stroke} stopOpacity={0.02} />
                </linearGradient>
              </defs>
              <XAxis dataKey="date" tick={{ fontSize: 12, fill: '#6B5C4E' }} tickLine={false} axisLine={{ stroke: '#EDE5DB' }} />
              <YAxis
                allowDecimals={integerAxis ? false : undefined}
                tick={{ fontSize: 12, fill: '#6B5C4E' }}
                tickLine={false}
                axisLine={false}
                width={yAxisWidth}
                tickFormatter={yTickFormatter}
              />
              <Tooltip
                contentStyle={{ fontFamily: 'DM Sans, sans-serif', borderRadius: '12px', border: '1px solid #D9D0C7', fontSize: 13 }}
                labelFormatter={(v) => `Oct ${v}`}
                formatter={tooltipFormatter}
              />
              {hasComparison && (
                <Line type="monotone" dataKey="previous" stroke="#B9AE9F" strokeDasharray="5 4" strokeWidth={1.5} dot={false} />
              )}
              <Area type="monotone" dataKey="value" stroke={stroke} strokeWidth={2.25} fill={`url(#${gradientId})`} dot={false} />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </div>
    </section>
  )
}
