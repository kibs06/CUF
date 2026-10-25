const TILE = {
  primary: 'bg-[#8B5A2B]/10 text-[#8B5A2B]',
  amber: 'bg-[#FFF4D6] text-[#9A6B0A]',
  teal: 'bg-[#E0F2F1] text-[#0E7C7B]',
  cocoa: 'bg-[#3B2314]/8 text-[#3B2314]',
  red: 'bg-[#FDECEA] text-[#B3261E]',
  neutral: 'bg-[#EDE5DB] text-[#6B5C4E]',
}

function Delta({ delta, invert = false, formatDelta }) {
  const n = Number(delta)
  if (delta == null || Number.isNaN(n)) return null
  const up = n > 0
  const flat = n === 0
  const good = invert ? !up : up
  const color = flat ? 'text-muted' : good ? 'text-[#0E7C7B]' : 'text-[#B3261E]'
  const copy =
    typeof formatDelta === 'function'
      ? formatDelta(n)
      : flat
        ? 'No change from last week'
        : up
          ? `Up ${Math.abs(n)} from last week`
          : `Down ${Math.abs(n)} from last week`
  return <span className={`tnum text-xs font-semibold ${color}`}>{copy}</span>
}

export default function StatCard({
  icon,
  label,
  value,
  caption,
  delta,
  highlight = false,
  iconBg,
  iconColor,
  children,
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
      <div className="flex items-start justify-between gap-3">
        <div
          className={`flex h-10 w-10 items-center justify-center rounded-xl ${tile}`}
          style={iconBg ? { background: iconBg } : undefined}
        >
          {Icon ? (
            <Icon size={18} strokeWidth={2} />
          ) : (
            <span style={iconColor ? { color: iconColor } : undefined} className="text-base leading-none">
              {icon}
            </span>
          )}
        </div>
        {sparkline ? <div className="h-9 w-24 shrink-0">{sparkline}</div> : null}
      </div>

      <p className="tnum mt-4 font-mono text-[28px] font-semibold leading-none text-ink">
        {children ?? value}
      </p>
      <p className="mt-1.5 text-[13px] font-medium text-muted">{label}</p>
      {(delta != null || caption) && (
        <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-muted">
          {delta != null && <Delta delta={delta} invert={invertDelta} formatDelta={formatDelta} />}
          {caption && <span className="truncate">{caption}</span>}
        </p>
      )}
    </Tag>
  )
}
