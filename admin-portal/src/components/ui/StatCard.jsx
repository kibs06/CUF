const TILE = {
  primary: 'bg-primary/10 text-primary',
  amber: 'bg-pendingSoft text-pending',
  teal: 'bg-accentSoft text-accent',
  cocoa: 'bg-secondary/10 text-secondary',
  red: 'bg-errorSoft text-error',
  neutral: 'bg-faint text-muted',
}

function Delta({ delta, invert = false, formatDelta }) {
  if (delta == null) return null
  const up = delta > 0
  const good = invert ? !up : up
  const color = delta === 0 ? 'text-muted' : good ? 'text-accent' : 'text-error'
  const copy =
    typeof formatDelta === 'function'
      ? formatDelta(delta)
      : delta === 0
        ? 'No change from last week'
        : up
          ? `Up ${delta} from last week`
          : `Down ${Math.abs(delta)} from last week`
  return <span className={`tnum text-xs font-semibold ${color}`}>{copy}</span>
}

export default function StatCard({
  label,
  value,
  caption,
  delta,
  highlight = false,
  tone = 'neutral',
  Icon,
  sparkline,
  onClick,
  active = false,
  invertDelta = false,
  formatDelta,
}) {
  const tile = TILE[tone] ?? TILE.neutral
  const clickable = typeof onClick === 'function'
  const Tag = clickable ? 'button' : 'div'

  return (
    <Tag
      type={clickable ? 'button' : undefined}
      onClick={onClick}
      className={`rounded-2xl border bg-white p-5 text-left shadow-card transition-colors ${
        highlight ? 'border-[#E8A020]/60 ring-1 ring-[#E8A020]/40' : 'border-border'
      } ${clickable ? 'w-full cursor-pointer hover:border-primary/50 hover:shadow-pop' : ''} ${
        active ? 'border-primary ring-1 ring-primary/40' : ''
      }`}
    >
      <div className="flex items-center justify-between gap-3">
        <p className="text-[13px] font-medium text-muted">{label}</p>
        {Icon ? (
          <div className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${tile}`}>
            <Icon size={15} strokeWidth={2} />
          </div>
        ) : null}
      </div>

      <p className="tnum mt-2 font-mono text-[40px] font-semibold leading-none tracking-tight text-ink">{value}</p>
      {(delta != null || caption) && (
        <p className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-muted">
          {delta != null && <Delta delta={delta} invert={invertDelta} formatDelta={formatDelta} />}
          {caption && <span className="truncate">{caption}</span>}
        </p>
      )}
      {sparkline ? <div className="mt-3 h-10 w-full">{sparkline}</div> : null}
    </Tag>
  )
}
