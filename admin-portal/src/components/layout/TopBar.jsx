import { useAuth } from '../../hooks/useAuth.jsx'
import AvatarInitials from '../ui/AvatarInitials.jsx'
import { Bell, Menu } from 'lucide-react'

function formatDateLong() {
  return new Date().toLocaleDateString('en-PH', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  })
}

export default function TopBar({ title, onMenuClick }) {
  const { profile } = useAuth()
  const firstName = (profile?.full_name ?? 'Admin').split(' ')[0]

  return (
    <header className="mb-6 flex items-center justify-between gap-4">
      <div className="flex min-w-0 items-center gap-3">
        <button
          type="button"
          onClick={onMenuClick}
          aria-label="Open navigation"
          className="rounded-xl border border-border bg-white p-2 transition-colors hover:bg-canvas lg:hidden"
        >
          <Menu size={18} className="text-muted" />
        </button>
        <div className="min-w-0">
          <h1 className="truncate font-display text-[26px] font-bold leading-tight text-ink">{title}</h1>
          <p className="mt-0.5 truncate text-[13px] text-muted">
            Good to see you, {firstName}. Today is {formatDateLong()}.
          </p>
        </div>
      </div>

      <div className="flex shrink-0 items-center gap-2.5">
        <button
          type="button"
          aria-label="Notifications"
          className="relative flex h-9 w-9 items-center justify-center rounded-xl border border-border bg-white shadow-card transition-colors hover:border-primary/50"
        >
          <Bell size={16} className="text-muted" />
        </button>

        <div className="flex items-center gap-2 rounded-xl border border-border bg-white py-1.5 pl-1.5 pr-3 shadow-card">
          <AvatarInitials name={profile?.full_name} email={profile?.email} size="sm" />
          <span className="hidden max-w-[140px] truncate text-[13px] font-semibold text-ink sm:inline">
            {profile?.full_name ?? 'Admin'}
          </span>
        </div>
      </div>
    </header>
  )
}
