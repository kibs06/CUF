import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth.jsx'
import AvatarInitials from '../ui/AvatarInitials.jsx'
import { Bell, ChevronDown, LogOut, Menu, Settings } from 'lucide-react'

function formatDateLong() {
  return new Date().toLocaleDateString('en-PH', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  })
}

export default function TopBar({ title, onMenuClick }) {
  const { profile, signOut } = useAuth()
  const [menuOpen, setMenuOpen] = useState(false)
  const menuRef = useRef(null)
  const firstName = (profile?.full_name ?? 'Admin').split(' ')[0]

  useEffect(() => {
    if (!menuOpen) return undefined
    const onPointerDown = (event) => {
      if (!menuRef.current?.contains(event.target)) setMenuOpen(false)
    }
    const onKeyDown = (event) => {
      if (event.key === 'Escape') setMenuOpen(false)
    }
    document.addEventListener('pointerdown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [menuOpen])

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

        <div ref={menuRef} className="relative">
          <button
            type="button"
            onClick={() => setMenuOpen((v) => !v)}
            aria-expanded={menuOpen}
            aria-haspopup="menu"
            aria-label="Your account"
            className="flex items-center gap-1.5 rounded-xl border border-border bg-white py-1.5 pl-1.5 pr-2.5 shadow-card transition-colors hover:border-primary/50"
          >
            <AvatarInitials name={profile?.full_name} email={profile?.email} size="sm" />
            <span className="hidden max-w-[140px] truncate text-[13px] font-semibold text-ink sm:inline">
              {profile?.full_name ?? 'Admin'}
            </span>
            <ChevronDown size={14} className="text-muted" />
          </button>

          {menuOpen && (
            <div
              role="menu"
              className="absolute right-0 z-50 mt-2 w-60 origin-top-right overflow-hidden rounded-2xl border border-border bg-white shadow-pop"
            >
              <div className="flex items-center gap-3 border-b border-canvas px-4 py-3">
                <AvatarInitials name={profile?.full_name} email={profile?.email} />
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-ink">
                    {profile?.full_name ?? 'Admin'}
                  </p>
                  <p className="truncate text-xs text-muted" title={profile?.email}>
                    {profile?.email}
                  </p>
                </div>
              </div>
              <div className="py-1">
                <Link
                  to="/settings"
                  role="menuitem"
                  onClick={() => setMenuOpen(false)}
                  className="flex items-center gap-2.5 px-4 py-2.5 text-sm text-muted transition-colors hover:bg-canvas hover:text-ink"
                >
                  <Settings size={16} strokeWidth={2} />
                  Account settings
                </Link>
              </div>
              <div className="border-t border-canvas py-1">
                <button
                  type="button"
                  role="menuitem"
                  onClick={() => {
                    setMenuOpen(false)
                    signOut()
                  }}
                  className="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-muted transition-colors hover:bg-errorSoft hover:text-error"
                >
                  <LogOut size={16} strokeWidth={2} />
                  Log out
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </header>
  )
}
