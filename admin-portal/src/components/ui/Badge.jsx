const VARIANTS = {
  customer: 'bg-[#EDE5DB] text-[#3B2314] border border-[#D9D0C7]',
  seller: 'bg-[#E0F2F1] text-[#0E7C7B] border border-[#0E7C7B]/25',
  admin: 'bg-[#FDECEA] text-[#B3261E] border border-[#B3261E]/25',
  pending: 'bg-[#FFF4D6] text-[#7A5600] border border-[#E8A020]/40',
  approved: 'bg-[#E0F2F1] text-[#0E7C7B] border border-[#0E7C7B]/25',
  rejected: 'bg-[#FDECEA] text-[#B3261E] border border-[#B3261E]/25',
  active: 'bg-[#E0F2F1] text-[#0E7C7B] border border-[#0E7C7B]/25',
  inactive: 'bg-[#EDE5DB] text-[#6B5C4E] border border-[#D9D0C7]',
  placed: 'bg-[#FFF4D6] text-[#7A5600] border border-[#E8A020]/40',
  confirmed: 'bg-[#E4EBFF] text-[#2B4BCB] border border-[#2B4BCB]/25',
  preparing: 'bg-[#E4EBFF] text-[#2B4BCB] border border-[#2B4BCB]/25',
  ready: 'bg-[#FFF4D6] text-[#7A5600] border border-[#E8A020]/40',
  shipped: 'bg-[#E9E4FB] text-[#5B3DF0] border border-[#5B3DF0]/25',
  received: 'bg-[#E0F2F1] text-[#0E7C7B] border border-[#0E7C7B]/25',
  delivered: 'bg-[#E0F2F1] text-[#0E7C7B] border border-[#0E7C7B]/25',
  cancelled: 'bg-[#FDECEA] text-[#B3261E] border border-[#B3261E]/25',
  suspended: 'bg-[#FDECEA] text-[#B3261E] border border-[#B3261E]/25',
  under_review: 'bg-[#E4EBFF] text-[#2B4BCB] border border-[#2B4BCB]/25',
  dismissed: 'bg-[#EDE5DB] text-[#6B5C4E] border border-[#D9D0C7]',
  resolved: 'bg-[#E0F2F1] text-[#0E7C7B] border border-[#0E7C7B]/25',
  none: 'bg-[#EDE5DB] text-[#6B5C4E] border border-[#D9D0C7]',
  succeeded: 'bg-[#E0F2F1] text-[#0E7C7B] border border-[#0E7C7B]/25',
  failed: 'bg-[#FDECEA] text-[#B3261E] border border-[#B3261E]/25',
  expired: 'bg-[#EDE5DB] text-[#6B5C4E] border border-[#D9D0C7]',
  requested: 'bg-[#FFF4D6] text-[#7A5600] border border-[#E8A020]/40',
  in_progress: 'bg-[#E4EBFF] text-[#2B4BCB] border border-[#2B4BCB]/25',
  fulfilled: 'bg-[#E0F2F1] text-[#0E7C7B] border border-[#0E7C7B]/25',
  declined: 'bg-[#FDECEA] text-[#B3261E] border border-[#B3261E]/25',
  processed: 'bg-[#E0F2F1] text-[#0E7C7B] border border-[#0E7C7B]/25',
  processing: 'bg-[#E4EBFF] text-[#2B4BCB] border border-[#2B4BCB]/25',
  amount_mismatch: 'bg-[#FDECEA] text-[#B3261E] border border-[#B3261E]/25',
  stock_conflict: 'bg-[#FDECEA] text-[#B3261E] border border-[#B3261E]/25',
  rejected_signature: 'bg-[#FDECEA] text-[#B3261E] border border-[#B3261E]/25',
}

function humanize(label) {
  return String(label ?? '').replace(/_/g, ' ').replace(/\s+/g, ' ').trim()
}

export default function Badge({ label, variant, dot = false }) {
  const key = (variant ?? label ?? '').toLowerCase()
  const classes = VARIANTS[key] ?? 'bg-[#EDE5DB] text-[#6B5C4E] border border-[#D9D0C7]'

  return (
    <span
      className={`inline-flex items-center whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold ${classes}`}
    >
      {dot && <span className="mr-1.5 inline-block h-1.5 w-1.5 rounded-full bg-current opacity-70" />}
      {humanize(label)}
    </span>
  )
}
