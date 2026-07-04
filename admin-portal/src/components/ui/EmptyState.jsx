export default function EmptyState({ icon = '⏳', title, description }) {
  return (
    <div className="flex flex-col items-center justify-center rounded-2xl border border-border bg-surface px-6 py-16 text-center">
      <div className="mb-4 text-5xl">{icon}</div>
      <h3 className="font-display text-xl font-bold text-secondary">{title}</h3>
      {description && (
        <p className="mt-2 max-w-sm text-sm text-secondary/60">{description}</p>
      )}
    </div>
  )
}
