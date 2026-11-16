import { TrendingUp, TrendingDown, Minus } from 'lucide-react'

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
  sparkline,
  onClick,
  active = false,
  invertDelta = false,
  formatDelta,
  bare = false,
}) {
  const clickable = typeof onClick === 'function'
  const Tag = clickable ? 'button' : 'div'

  return (
    <Tag
      type={clickable ? 'button' : undefined}
      onClick={onClick}
      className={`flex h-full flex-col text-left transition-colors ${bare ? 'bg-white px-4 py-3.5' : 'admin-3d-surface rounded-xl border border-border bg-white px-4 py-3.5'} ${
        clickable ? 'w-full cursor-pointer hover:border-primary/40' : ''
      } ${active ? 'border-primary ring-1 ring-primary/40' : ''}`}
    >
      <p className="text-[12px] font-medium text-muted">{label}</p>

      <p className="tnum mt-1.5 font-mono text-[24px] font-semibold leading-none tracking-tight text-ink">
        {value}
      </p>
      {(delta != null || caption) && (
        <p className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-[11.5px] text-muted">
          {delta != null && <Delta delta={delta} invert={invertDelta} formatDelta={formatDelta} />}
          {caption && <span className="truncate">{caption}</span>}
        </p>
      )}
      {sparkline ? (
        <div className="mt-auto pt-3" aria-hidden="true">
          {sparkline}
        </div>
      ) : null}
    </Tag>
  )
}
