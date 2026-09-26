/**
 * The discount tag on a product tile.
 *
 * Uppercase and tightly tracked so it reads as a stamped label rather than a
 * sentence; the minus sign is the typographic one (−, U+2212) so it sits on the
 * same optical line as the digits instead of floating like a hyphen.
 */
export default function SaleBadge({ percent, className = '' }) {
  if (!percent) return null

  return (
    <span
      className={`num inline-flex items-center rounded-full bg-clay px-2.5 py-1 text-[11px] font-semibold uppercase leading-none tracking-[0.04em] text-ink-inverse shadow-warm ${className}`}
    >
      −{percent}%
    </span>
  )
}
