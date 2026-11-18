const VARIANTS = {
  customer: 'bg-faint text-ink border border-border',
  seller: 'bg-accentSoft text-accent border border-accent/25',
  admin: 'bg-errorSoft text-error border border-error/25',
  pending: 'bg-pendingSoft text-pendingInk border border-pending/40',
  approved: 'bg-accentSoft text-accent border border-accent/25',
  rejected: 'bg-errorSoft text-error border border-error/25',
  active: 'bg-accentSoft text-accent border border-accent/25',
  inactive: 'bg-faint text-muted border border-border',
  placed: 'bg-pendingSoft text-pendingInk border border-pending/40',
  confirmed: 'bg-infoSoft text-info border border-info/25',
  preparing: 'bg-infoSoft text-info border border-info/25',
  ready: 'bg-pendingSoft text-pendingInk border border-pending/40',
  shipped: 'bg-violetSoft text-violet border border-violet/25',
  received: 'bg-infoSoft text-info border border-info/25',
  delivered: 'bg-accentSoft text-accent border border-accent/25',
  return_requested: 'bg-warningSoft text-warning border border-pending/50',
  returnrequested: 'bg-warningSoft text-warning border border-pending/50',
  'return requested': 'bg-warningSoft text-warning border border-pending/50',
  cancelled: 'bg-errorSoft text-error border border-error/25',
  suspended: 'bg-errorSoft text-error border border-error/25',
  under_review: 'bg-infoSoft text-info border border-info/25',
  dismissed: 'bg-faint text-muted border border-border',
  resolved: 'bg-accentSoft text-accent border border-accent/25',
  none: 'bg-faint text-muted border border-border',
  succeeded: 'bg-accentSoft text-accent border border-accent/25',
  failed: 'bg-errorSoft text-error border border-error/25',
  expired: 'bg-faint text-muted border border-border',
  requested: 'bg-pendingSoft text-pendingInk border border-pending/40',
  in_progress: 'bg-infoSoft text-info border border-info/25',
  fulfilled: 'bg-accentSoft text-accent border border-accent/25',
  declined: 'bg-errorSoft text-error border border-error/25',
  processed: 'bg-accentSoft text-accent border border-accent/25',
  processing: 'bg-infoSoft text-info border border-info/25',
  amount_mismatch: 'bg-errorSoft text-error border border-error/25',
  stock_conflict: 'bg-errorSoft text-error border border-error/25',
  rejected_signature: 'bg-errorSoft text-error border border-error/25',
}

function humanize(label) {
  return String(label ?? '').replace(/_/g, ' ').replace(/\s+/g, ' ').trim()
}

export default function Badge({ label, variant, dot = false }) {
  const key = (variant ?? label ?? '').toLowerCase()
  const classes = VARIANTS[key] ?? 'bg-faint text-muted border border-border'

  return (
    <span
      className={`inline-flex items-center whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold ${classes}`}
    >
      {dot && <span className="mr-1.5 inline-block h-1.5 w-1.5 rounded-full bg-current opacity-70" />}
      {humanize(label)}
    </span>
  )
}
