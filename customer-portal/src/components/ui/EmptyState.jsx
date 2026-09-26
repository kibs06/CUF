/**
 * What a customer sees when a list is legitimately empty — no products in a
 * category, a store with nothing published yet.
 *
 * Deliberately not a red error: an empty shelf is a normal state of a
 * marketplace where sellers publish on their own schedule, and colouring it
 * like a failure tells the customer something is broken when nothing is.
 */
export default function EmptyState({
  Icon,
  title,
  description,
  action,
  className = '',
}) {
  return (
    <div
      className={`flex flex-col items-center justify-center rounded-card border border-hairline bg-subtle/60 px-6 py-16 text-center ${className}`}
    >
      {Icon && (
        <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-premium bg-clay/10">
          <Icon size={28} className="text-clay-ink" strokeWidth={1.75} />
        </div>
      )}
      <h3 className="font-display text-xl font-semibold text-ink">{title}</h3>
      {description && (
        <p className="mt-2 max-w-sm text-sm leading-relaxed text-muted">
          {description}
        </p>
      )}
      {action && <div className="mt-6">{action}</div>}
    </div>
  )
}
