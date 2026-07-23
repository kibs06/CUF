const VARIANTS = {
  customer: 'bg-amber-50 text-amber-700 border border-amber-200',
  seller: 'bg-teal-50 text-teal-700 border border-teal-200',
  admin: 'bg-red-50 text-red-700 border border-red-200',
  pending: 'bg-amber-50 text-amber-700 border border-amber-200',
  approved: 'bg-teal-50 text-teal-700 border border-teal-200',
  rejected: 'bg-red-50 text-red-700 border border-red-200',
  active: 'bg-teal-50 text-teal-700 border border-teal-200',
  inactive: 'bg-red-50 text-red-700 border border-red-200',
  placed: 'bg-amber-50 text-amber-700 border border-amber-200',
  confirmed: 'bg-blue-50 text-blue-700 border border-blue-200',
  preparing: 'bg-blue-50 text-blue-700 border border-blue-200',
  ready: 'bg-amber-50 text-amber-700 border border-amber-200',
  shipped: 'bg-purple-50 text-purple-700 border border-purple-200',
  received: 'bg-teal-50 text-teal-700 border border-teal-200',
  delivered: 'bg-teal-50 text-teal-700 border border-teal-200',
  cancelled: 'bg-red-50 text-red-700 border border-red-200',
  suspended: 'bg-red-50 text-red-700 border border-red-200',
  under_review: 'bg-blue-50 text-blue-700 border border-blue-200',
  dismissed: 'bg-gray-50 text-gray-500 border border-gray-200',
  resolved: 'bg-teal-50 text-teal-700 border border-teal-200',
  none: 'bg-gray-50 text-gray-500 border border-gray-200',
}

export default function Badge({ label, variant }) {
  const key = (variant ?? label ?? '').toLowerCase()
  const classes = VARIANTS[key] ?? 'bg-gray-50 text-gray-600 border border-gray-200'

  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold capitalize ${classes}`}
    >
      {label}
    </span>
  )
}
