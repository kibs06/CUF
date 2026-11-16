import {
  ComposedChart,
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
  const hasComparison = data.some((entry) => entry.previous != null)

  return (
    <section className="rounded-xl border border-border bg-white p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h2 className="text-[15px] font-bold text-ink">{title}</h2>
          {lead && <p className="mt-0.5 text-[12px] text-muted">{lead}</p>}
        </div>
        {total && (
          <span className="tnum font-mono text-[12px] font-semibold text-ink">{total}</span>
        )}
      </div>

      {!isEmpty && (
        <div className="mb-1 mt-3 flex items-center gap-4 text-[12px] font-medium text-muted">
          <span className="inline-flex items-center gap-1.5">
            <span
              className="h-1.5 w-1.5 rounded-full"
              style={{ backgroundColor: stroke }}
              aria-hidden="true"
            />
            This period
          </span>
          {hasComparison ? (
            <span className="inline-flex items-center gap-1.5">
              <span className="w-3 border-t border-dashed border-[#B9AE9F]" aria-hidden="true" />
              Prior week
            </span>
          ) : (
            <span>No prior-week comparison yet</span>
          )}
        </div>
      )}

      <div className="h-52">
        {isEmpty ? (
          <div className="flex h-full flex-col items-center justify-center px-6 text-center">
            <p className="text-sm font-semibold text-ink">{emptyTitle}</p>
            <p className="mt-1 max-w-sm text-[12.5px] text-muted">{emptyBody}</p>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -12 }}>
              <defs>
                <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={stroke} stopOpacity={0.22} />
                  <stop offset="100%" stopColor={stroke} stopOpacity={0.02} />
                </linearGradient>
              </defs>
              <XAxis
                dataKey="date"
                tick={{ fontSize: 12, fill: '#6B5C4E' }}
                tickLine={false}
                axisLine={{ stroke: '#EDE5DB' }}
              />
              <YAxis
                allowDecimals={integerAxis ? false : undefined}
                tick={{ fontSize: 12, fill: '#6B5C4E' }}
                tickLine={false}
                axisLine={false}
                width={yAxisWidth}
                tickFormatter={yTickFormatter}
              />
              <Tooltip
                contentStyle={{
                  fontFamily: 'DM Sans, sans-serif',
                  borderRadius: '12px',
                  border: '1px solid #D9D0C7',
                  fontSize: 12,
                }}
                labelFormatter={(value) => `${value}`}
                formatter={tooltipFormatter}
              />
              <Area
                type="monotone"
                dataKey="value"
                stroke={stroke}
                strokeWidth={2.25}
                fill={`url(#${gradientId})`}
                dot={false}
              />
              {hasComparison && (
                <Line
                  type="monotone"
                  dataKey="previous"
                  stroke="#A89A89"
                  strokeDasharray="5 4"
                  strokeWidth={1.6}
                  dot={false}
                />
              )}
            </ComposedChart>
          </ResponsiveContainer>
        )}
      </div>
    </section>
  )
}
