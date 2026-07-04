import { Users } from 'lucide-react'
import UserRow from './UserRow.jsx'

const SECTION_COLORS = {
  amber: {
    header: 'bg-amber-50 border-amber-200',
    title: 'text-amber-800',
    icon: 'bg-amber-100 text-amber-600',
    count: 'bg-amber-100 text-amber-700',
  },
  teal: {
    header: 'bg-teal-50 border-teal-200',
    title: 'text-teal-800',
    icon: 'bg-teal-100 text-teal-600',
    count: 'bg-teal-100 text-teal-700',
  },
  red: {
    header: 'bg-red-50 border-red-200',
    title: 'text-red-800',
    icon: 'bg-red-100 text-red-600',
    count: 'bg-red-100 text-red-700',
  },
}

export default function UserSection({
  title,
  color,
  icon,
  users,
  emptyMessage,
  showSellerStatus,
  onView,
}) {
  const c = SECTION_COLORS[color] ?? SECTION_COLORS.amber

  return (
    <div className="overflow-hidden rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
      {/* Section header */}
      <div className={`flex items-center justify-between border-b px-5 py-4 ${c.header}`}>
        <div className="flex items-center gap-2.5">
          <div className={`flex h-8 w-8 items-center justify-center rounded-lg ${c.icon}`}>
            {icon}
          </div>
          <h2 className={`font-display text-lg font-bold ${c.title}`}>{title}</h2>
        </div>
        <span className={`rounded-lg px-2.5 py-1 font-mono text-sm font-bold ${c.count}`}>
          {users.length}
        </span>
      </div>

      {/* User list */}
      <div className="divide-y divide-[#F5F0EB]">
        {users.length === 0 ? (
          <div className="flex flex-col items-center py-12 text-[#6B5C4E]">
            <Users size={28} className="mb-2 opacity-30" />
            <p className="text-sm">{emptyMessage}</p>
          </div>
        ) : (
          users.map((user) => (
            <UserRow
              key={user.id}
              user={user}
              showSellerStatus={showSellerStatus}
              onView={onView}
            />
          ))
        )}
      </div>
    </div>
  )
}
