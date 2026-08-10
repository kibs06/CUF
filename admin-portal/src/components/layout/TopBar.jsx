import { useAuth } from '../../hooks/useAuth.jsx'
import AvatarInitials from '../ui/AvatarInitials.jsx'
import { Bell, Menu } from 'lucide-react'

function formatDateLong() {
  return new Date().toLocaleDateString('en-PH', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })
}

export default function TopBar({ title, onMenuClick }) {
  const { profile } = useAuth()

  return (
    <header className="mb-8 flex items-center justify-between gap-4">
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={onMenuClick}
          className="rounded-xl border border-[#D9D0C7] bg-white p-2 lg:hidden hover:bg-[#F5F0EB] transition-colors"
        >
          <Menu size={18} className="text-[#6B5C4E]" />
        </button>
        <div className="relative pl-4">
          <span className="absolute inset-y-1 left-0 w-1 rounded-full bg-gradient-to-b from-primary to-accent" />
          <h1 className="font-display text-3xl font-bold text-[#3B2314]">{title}</h1>
          <p className="mt-0.5 text-sm text-[#6B5C4E]">
            Welcome back, {profile?.full_name ?? 'Admin'} · {formatDateLong()}
          </p>
        </div>
      </div>

      <div className="flex items-center gap-3">
        {/* Notification bell */}
        <button
          type="button"
          className="flex h-9 w-9 items-center justify-center rounded-xl border border-[#D9D0C7] bg-white transition-colors hover:bg-[#F5F0EB]"
        >
          <Bell size={16} className="text-[#6B5C4E]" />
        </button>

        {/* Admin avatar chip */}
        <div className="flex items-center gap-2 rounded-xl border border-[#D9D0C7] bg-white px-3 py-1.5">
          <AvatarInitials name={profile?.full_name} email={profile?.email} size="sm" />
          <span className="hidden text-sm font-medium text-[#3B2314] sm:inline">
            {profile?.full_name ?? 'Admin'}
          </span>
        </div>
      </div>
    </header>
  )
}
