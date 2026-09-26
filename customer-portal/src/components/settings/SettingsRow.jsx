import { Link } from 'react-router-dom'
import { ChevronRight } from 'lucide-react'

/**
 * One row of Settings, and the section card it sits in.
 *
 * A row is one destination, so it is one link — the whole strip is clickable
 * and one tab stop, the same decision the product card makes. `subtitle` is
 * where the app puts the *current value* ("40 · Men's · set manually", the
 * chosen theme), which is what saves a customer from opening a screen just to
 * find out what it says.
 */
export function SettingsRow({
  to,
  onClick,
  Icon,
  title,
  subtitle = null,
  badge = false,
  danger = false,
  trailing = null,
}) {
  const className = [
    'flex w-full items-center gap-4 px-5 py-4 text-left transition-colors duration-200 ease-out-cubic hover:bg-subtle/70',
    danger ? 'text-crimson' : 'text-ink',
  ].join(' ')

  const body = (
    <>
      {Icon && (
        <Icon
          size={20}
          strokeWidth={1.75}
          className={`shrink-0 ${danger ? 'text-crimson' : 'text-clay-ink'}`}
        />
      )}

      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-1.5">
          <span className="truncate text-sm font-medium">{title}</span>
          {/* An unviewed-update dot, the app's own affordance. */}
          {badge && (
            <span
              aria-label="New"
              className="h-2 w-2 shrink-0 rounded-full bg-crimson"
            />
          )}
        </span>
        {subtitle && (
          <span className="mt-0.5 block truncate text-xs text-muted">
            {subtitle}
          </span>
        )}
      </span>

      {trailing ?? (
        <ChevronRight
          size={18}
          strokeWidth={2}
          className="shrink-0 text-card-edge"
        />
      )}
    </>
  )

  if (to) {
    return (
      <li className="border-b border-hairline-soft last:border-b-0">
        <Link to={to} className={className}>
          {body}
        </Link>
      </li>
    )
  }

  return (
    <li className="border-b border-hairline-soft last:border-b-0">
      <button type="button" onClick={onClick} className={className}>
        {body}
      </button>
    </li>
  )
}

/** A titled group of rows. The heading is a real `h2`, so the page has an outline. */
export function SettingsSection({ title, description = null, children }) {
  return (
    <section>
      <h2 className="overline">{title}</h2>
      {description && (
        <p className="mt-2 text-xs leading-relaxed text-muted">{description}</p>
      )}
      <ul className="mt-3 overflow-hidden rounded-card border border-hairline bg-raised shadow-card">
        {children}
      </ul>
    </section>
  )
}
