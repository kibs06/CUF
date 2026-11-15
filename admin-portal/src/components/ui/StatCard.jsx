import { TrendingUp, TrendingDown, Minus } from 'lucide-react'

const TILE = {
  primary: 'bg-primary/10 text-primary',
  amber: 'bg-pendingSoft text-pending',
  teal: 'bg-accentSoft text-accent',
  cocoa: 'bg-secondary/10 text-secondary',
  red: 'bg-errorSoft text-error',
  neutral: 'bg-faint text-muted',
}

const PILL = {
  up: 'bg-accentSoft text-accent',
  down: 'bg-errorSoft text-error',
  flat: 'bg-faint text-muted',
}

function Delta({ delta, invert = false, formatDelta }) {
  if (delta == null) return null
  const up = delta > 0
  const flat = delta === 0
  const good = invert ? !up : up
  const tone = flat ? 'flat' : good ? 'up' : 'down'
  const Icon = flat ? Minus : up ? TrendingUp : TrendingDown
  const copy =
    typeof formatDelta === 'function'
      ? formatDelta(delta)
      : flat
        ? 'No change'
        : up
          ? `+${delta}`
          : `${delta}`
  return (
    <span className={`tnum inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold ${PILL[tone]}`}>
      <Icon size={12} strokeWidth={2.5} aria-hidden="true" />
      {copy}
    </span>
  )
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
  bare = false,
}) {
  const tile = TILE[tone] ?? TILE.neutral
  const clickable = typeof onClick === 'function'
  const Tag = clickable ? 'button' : 'div'

  return (
    <Tag
      type={clickable ? 'button' : undefined}
      onClick={onClick}
      className={`group relative overflow-hidden text-left transition-all duration-200 ${bare ? 'bg-white p-5' : 'rounded-2xl border bg-white p-5 shadow-card'} ${
        highlight ? 'border-[#E8A020]/60 ring-1 ring-[#E8A020]/40' : 'border-border'
      } ${clickable ? 'w-full cursor-pointer hover:-translate-y-0.5 hover:border-primary/50 hover:shadow-pop' : ''} ${
        active ? 'border-primary ring-1 ring-primary/40' : ''
      }`}
    >
      {highlight && <span aria-hidden="true" className="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-[#E8A020] to-[#E8C99A]" />}
      <div className="flex items-center justify-between gap-3">
        <p className="text-[11px] font-bold uppercase tracking-[0.08em] text-muted">{label}</p>
        {Icon ? (
          <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${tile} transition-transform duration-200 group-hover:scale-105`}>
            <Icon size={16} strokeWidth={2} aria-hidden="true" />
          </div>
        ) : null}
      </div>

      <p className="tnum mt-2 font-mono text-[30px] font-semibold leading-none tracking-tight text-ink">{value}</p>
      {(delta != null || caption) && (
        <p className="mt-2.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted">
          {delta != null && <Delta delta={delta} invert={invertDelta} formatDelta={formatDelta} />}
          {caption && <span className="truncate">{caption}</span>}
        </p>
      )}
      {sparkline ? <div className="mt-3 h-11 w-full" aria-hidden="true">{sparkline}</div> : <div className="mt-3 h-1.5 w-10 rounded-full bg-canvas" aria-hidden="true" />}
    </Tag>
  )
}
