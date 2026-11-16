import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth.jsx'
import { useAdminNotifications } from '../../hooks/useAdminNotifications.js'
import AvatarInitials from '../ui/AvatarInitials.jsx'
import {
  AlertTriangle,
  Bell,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Cuboid,
  LogOut,
  Menu,
  Settings,
  ShoppingCart,
  Store,
} from 'lucide-react'

export default function TopBar({ title, subtitle, onMenuClick }) {
  const { profile, signOut } = useAuth()
  const [menuOpen, setMenuOpen] = useState(false)
  const [notificationsOpen, setNotificationsOpen] = useState(false)
  const menuRef = useRef(null)
  const notificationsRef = useRef(null)
  const {
    data: notificationCounts,
    isLoading: notificationsLoading,
    isError: notificationsError,
    refetch: refetchNotifications,
  } = useAdminNotifications()

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

  useEffect(() => {
    if (!notificationsOpen) return undefined
    const onPointerDown = (event) => {
      if (!notificationsRef.current?.contains(event.target)) setNotificationsOpen(false)
    }
    const onKeyDown = (event) => {
      if (event.key === 'Escape') setNotificationsOpen(false)
    }
    document.addEventListener('pointerdown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [notificationsOpen])

  const notificationItems = [
    {
      key: 'reports',
      label: 'High-priority reports',
      hint: 'Waiting in the moderation queue',
      count: notificationCounts?.reports ?? 0,
      to: '/reports',
      icon: AlertTriangle,
      tone: 'bg-errorSoft text-error',
    },
    {
      key: 'applications',
      label: 'Seller applications',
      hint: 'Waiting for verification',
      count: notificationCounts?.applications ?? 0,
      to: '/seller-applications',
      icon: Store,
      tone: 'bg-pendingSoft text-pending',
    },
    {
      key: 'modelRequests',
      label: '3D fitting requests',
      hint: 'Waiting for a model',
      count: notificationCounts?.modelRequests ?? 0,
      to: '/model-requests',
      icon: Cuboid,
      tone: 'bg-pendingSoft text-pending',
    },
    {
      key: 'orders',
      label: 'Orders needing action',
      hint: 'Pending, placed, or confirmed',
      count: notificationCounts?.orders ?? 0,
      to: '/orders?status=pending',
      icon: ShoppingCart,
      tone: 'bg-accentSoft text-accent',
    },
  ].filter((item) => item.count > 0)

  const notificationTotal = notificationItems.reduce((sum, item) => sum + item.count, 0)
  const notificationBadge = notificationTotal > 99 ? '99+' : notificationTotal

  return (
    <header className="mb-6 flex items-center justify-between gap-4">
      <div className="flex min-w-0 items-center gap-3">
        <button
          type="button"
          onClick={onMenuClick}
          aria-label="Open navigation"
          className="admin-3d-pressable rounded-xl border border-border bg-white p-2 transition-colors hover:bg-canvas lg:hidden"
        >
          <Menu size={18} className="text-muted" />
        </button>
        <div className="min-w-0">
          <h1 className="truncate font-display text-[26px] font-bold leading-tight text-ink">{title}</h1>
          {subtitle && (
            <p className="mt-0.5 truncate text-[13px] text-muted">{subtitle}</p>
          )}
        </div>
      </div>

      <div className="flex shrink-0 items-center gap-2.5">
        <div ref={notificationsRef} className="relative">
          <button
            type="button"
            onClick={() => {
              setNotificationsOpen((value) => !value)
              setMenuOpen(false)
            }}
            aria-label={
              notificationTotal > 0
                ? `Notifications, ${notificationTotal} open`
                : 'Notifications'
            }
            aria-expanded={notificationsOpen}
            aria-haspopup="true"
            aria-controls="admin-notifications"
            title="Notifications"
            className={`admin-3d-pressable relative flex h-[38px] w-[38px] items-center justify-center rounded-xl border bg-white shadow-card transition-colors hover:border-primary/50 hover:bg-canvas ${
              notificationsOpen ? 'border-primary/50 bg-canvas' : 'border-border'
            }`}
          >
            <Bell size={16} className={notificationsOpen ? 'text-primary' : 'text-muted'} />
            {notificationTotal > 0 && (
              <span className="absolute -right-1 -top-1 flex h-[17px] min-w-[17px] items-center justify-center rounded-full bg-error px-1 font-mono text-[9px] font-bold leading-none text-white ring-2 ring-white">
                {notificationBadge}
              </span>
            )}
          </button>

          {notificationsOpen && (
            <div
              id="admin-notifications"
              className="absolute right-0 z-50 mt-2 w-[340px] max-w-[calc(100vw-2rem)] origin-top-right overflow-hidden rounded-xl border border-border bg-white shadow-pop"
            >
              <div className="flex items-start justify-between gap-3 border-b border-border px-4 py-3">
                <div>
                  <p className="text-[13px] font-semibold text-ink">Notifications</p>
                  <p className="mt-0.5 text-[11.5px] text-muted">
                    Action needed across the portal.
                  </p>
                </div>
                {notificationTotal > 0 && (
                  <span className="shrink-0 rounded-full bg-canvas px-2 py-1 font-mono text-[10px] font-semibold text-muted">
                    {notificationTotal} open
                  </span>
                )}
              </div>

              {notificationsLoading ? (
                <div className="divide-y divide-border/70">
                  {[0, 1, 2].map((row) => (
                    <div key={row} className="flex items-center gap-3 px-4 py-3.5">
                      <div className="h-8 w-8 animate-pulse rounded-lg bg-canvas" />
                      <div className="flex-1 space-y-2">
                        <div className="h-2.5 w-28 animate-pulse rounded bg-canvas" />
                        <div className="h-2 w-40 animate-pulse rounded bg-canvas" />
                      </div>
                    </div>
                  ))}
                </div>
              ) : notificationsError ? (
                <div className="px-5 py-7 text-center">
                  <p className="text-[12.5px] font-semibold text-ink">
                    Couldn’t load notifications
                  </p>
                  <p className="mt-1 text-[11.5px] text-muted">
                    Check your connection and try again.
                  </p>
                  <button
                    type="button"
                    onClick={() => refetchNotifications()}
                    className="mt-3 rounded-lg border border-border px-3 py-1.5 text-[11.5px] font-semibold text-ink transition-colors hover:bg-canvas"
                  >
                    Try again
                  </button>
                </div>
              ) : notificationItems.length === 0 ? (
                <div className="px-5 py-7 text-center">
                  <CheckCircle2 size={22} strokeWidth={1.8} className="mx-auto text-accent" />
                  <p className="mt-2 text-[12.5px] font-semibold text-ink">
                    You’re all caught up
                  </p>
                  <p className="mt-1 text-[11.5px] text-muted">
                    No open admin queues right now.
                  </p>
                </div>
              ) : (
                <div className="divide-y divide-border/70">
                  {notificationItems.map(({ key, label, hint, count, to, icon: Icon, tone }) => (
                    <Link
                      key={key}
                      to={to}
                      onClick={() => setNotificationsOpen(false)}
                      className="admin-list-item flex items-center gap-3 px-4 py-3"
                    >
                      <span
                        className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${tone}`}
                      >
                        <Icon size={15} strokeWidth={2} />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block text-[12.5px] font-semibold text-ink">
                          {label}
                        </span>
                        <span className="mt-0.5 block text-[11px] text-muted">{hint}</span>
                      </span>
                      <span className="tnum font-mono text-[12px] font-semibold text-ink">
                        {count}
                      </span>
                      <ChevronRight size={13} className="shrink-0 text-muted/60" />
                    </Link>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        <div ref={menuRef} className="relative">
          <button
            type="button"
            onClick={() => {
              setMenuOpen((value) => !value)
              setNotificationsOpen(false)
            }}
            aria-expanded={menuOpen}
            aria-haspopup="menu"
            aria-label="Your account"
            className="admin-3d-pressable flex h-[38px] items-center gap-1.5 rounded-xl border border-border bg-white py-1.5 pl-1.5 pr-2.5 shadow-card transition-colors hover:border-primary/50 hover:bg-canvas"
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
