import { statusLabel, statusTone } from '../../lib/orders'

const TONE_DOT = {
  amber: 'bg-amber',
  clay: 'bg-clay',
  olive: 'bg-olive',
  crimson: 'bg-crimson',
  muted: 'bg-muted/60',
}

/**
 * What happened to an order, and when.
 *
 * Built from `order_status_history`, which is the only place real transition
 * times live — the alternative is inferring them from the current status, which
 * produces a timeline that is entirely correct except for every date on it.
 *
 * The newest entry is marked as such (`aria-current`) rather than being
 * coloured differently: a customer opening a delivered order is looking for the
 * last thing that happened, and it should be findable without reading.
 *
 * Dates are absolute, not relative. "3 days ago" is friendlier on a feed and
 * useless on a receipt — a customer checking why a refund has not arrived needs
 * to know it was the 21st, and an order is a document.
 */
export default function OrderTimeline({ entries, className = '' }) {
  if (!entries || entries.length === 0) return null

  return (
    <ol className={`relative ${className}`}>
      {entries.map((entry, index) => {
        const last = index === entries.length - 1
        const tone = statusTone(entry.status)

        return (
          <li
            key={entry.key}
            className="relative flex gap-4 pb-6 last:pb-0"
            aria-current={last ? 'step' : undefined}
          >
            {/* The connector, drawn behind the dot and stopped at the last
                entry so the line does not dangle past the final event. */}
            {!last && (
              <span
                aria-hidden="true"
                className="absolute left-[5px] top-4 h-full w-px bg-hairline"
              />
            )}

            <span
              aria-hidden="true"
              className={`relative z-10 mt-1 h-[11px] w-[11px] shrink-0 rounded-full ring-4 ring-raised ${
                TONE_DOT[tone] ?? TONE_DOT.muted
              }`}
            />

            <div className="min-w-0 flex-1">
              <p
                className={`text-sm ${last ? 'font-semibold text-ink' : 'text-muted-strong'}`}
              >
                {entry.label ?? statusLabel(entry.status)}
              </p>
              <p className="num mt-0.5 text-xs text-muted">
                <time dateTime={entry.at.toISOString()}>
                  {formatMoment(entry.at)}
                </time>
              </p>
            </div>
          </li>
        )
      })}
    </ol>
  )
}

/** `25 Sep 2026, 7:13 PM` — the date AND the time, because an order is a record. */
export function formatMoment(value) {
  if (!value) return '—'
  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) return '—'

  return date.toLocaleString('en-PH', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}
