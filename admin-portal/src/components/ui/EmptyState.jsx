import { Inbox } from 'lucide-react'

export default function EmptyState({ title, description, Icon = Inbox, action }) {
  return (
    <div className="admin-3d-surface flex flex-col items-center justify-center rounded-xl border border-border bg-card px-6 py-16 text-center">
      <Icon size={22} strokeWidth={1.5} className="text-muted/70" aria-hidden="true" />
      <h3 className="mt-3 text-[15px] font-semibold text-ink">{title}</h3>
      {description && (
        <p className="mt-1.5 max-w-sm text-[12.5px] leading-relaxed text-muted">{description}</p>
      )}
      {action}
    </div>
  )
}
