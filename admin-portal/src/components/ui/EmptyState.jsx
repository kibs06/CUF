export default function EmptyState({ icon = '⏳', title, description, Icon, action }) {
  return (
    <div className="flex flex-col items-center justify-center rounded-2xl border border-border bg-surface px-6 py-16 text-center">
      {Icon ? (
        <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10">
          <Icon size={30} className="text-primary" strokeWidth={1.75} />
        </div>
      ) : (
        <div className="mb-4 text-5xl">{icon}</div>
      )}
      <h3 className="font-display text-xl font-bold text-secondary">{title}</h3>
      {description && (
        <p className="mt-2 max-w-sm text-sm text-secondary/60">{description}</p>
      )}
      {action}
    </div>
  )
}
