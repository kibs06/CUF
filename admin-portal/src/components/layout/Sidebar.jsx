import { Link, NavLink } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth.jsx'
import { useAdminNotifications } from '../../hooks/useAdminNotifications.js'
import { useTheme } from '../../hooks/useTheme.js'
import AvatarInitials from '../ui/AvatarInitials.jsx'
import { useEffect, useRef, useState } from 'react'
import {
  LayoutDashboard,
  Users,
  Store,
  Package,
  Cuboid,
  ShoppingCart,
  Wallet,
  Flag,
  ScrollText,
  BarChart2,
  ChevronDown,
  Settings,
  LogOut,
  Image,
  UserCircle,
  Landmark,
  BadgeCheck,
  Banknote,
  RotateCcw,
  Moon,
  Sun,
} from 'lucide-react'

const GROUPS = [
  {
    label: 'Overview',
    items: [
      { to: '/', label: 'Dashboard', icon: LayoutDashboard },
      { to: '/analytics', label: 'Analytics', icon: BarChart2 },
      { to: '/reports', label: 'Reports', icon: Flag },
    ],
  },
  {
    label: 'Catalog and sellers',
    items: [
      { to: '/users', label: 'Users', icon: Users },
      { to: '/seller-applications', label: 'Seller Applications', icon: Store },
      { to: '/products', label: 'Products', icon: Package },
      { to: '/model-requests', label: '3D Fitting Requests', icon: Cuboid },
    ],
  },
  {
    label: 'Operations',
    items: [
      { to: '/orders', label: 'Orders', icon: ShoppingCart },
      { to: '/transactions', label: 'Transactions', icon: Wallet },
      { to: '/payment-verification', label: 'GCash Verification', icon: BadgeCheck },
      { to: '/payouts', label: 'Payouts', icon: Banknote },
      { to: '/refunds', label: 'Refunds owed', icon: RotateCcw },
    ],
  },
  {
    label: 'System',
    items: [
      { to: '/platform-payments', label: 'Platform GCash', icon: Landmark },
      { to: '/banners', label: 'Banners', icon: Image },
      { to: '/audit-logs', label: 'Audit Logs', icon: ScrollText },
      { to: '/settings', label: 'Settings', icon: Settings },
    ],
  },
]

export default function Sidebar({ open, onClose }) {
  const { profile, signOut } = useAuth()
  const { data: notificationCounts } = useAdminNotifications()
  const highPriorityCount = notificationCounts?.reports ?? 0
  const waitingModelRequests = notificationCounts?.modelRequests ?? 0
  const proofsUnderReview = notificationCounts?.gcashProofs ?? 0
  const [hovered, setHovered] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const { isDark, toggle: toggleTheme } = useTheme()
  const menuRef = useRef(null)
  // The drawer is always full-width: on touch screens there is no hover, so an
  // open drawer is expanded by definition and hover only matters on desktop.
  const expanded = hovered || open

  // The menu lives on the footer button, so it must die with the rail: a
  // panel left hanging open while the sidebar shrinks would float in space.
  useEffect(() => {
    if (!expanded) setMenuOpen(false)
  }, [expanded])

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


  const badgeFor = (to) => {
    if (to === '/reports' && highPriorityCount > 0)
      return { value: highPriorityCount > 9 ? '9+' : highPriorityCount, tone: 'bg-danger' }
    if (to === '/model-requests' && waitingModelRequests > 0)
      return { value: waitingModelRequests > 9 ? '9+' : waitingModelRequests, tone: 'bg-pending' }
    if (to === '/payment-verification' && proofsUnderReview > 0)
      return { value: proofsUnderReview > 9 ? '9+' : proofsUnderReview, tone: 'bg-pending' }
    return null
  }

  return (
    <>
      {open && (
        <div
          className="fixed inset-0 z-40 bg-secondary/50 lg:hidden"
          onClick={onClose}
        />
      )}

      <aside
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        className={`admin-3d-rail sole-scroll fixed inset-y-0 left-0 z-50 flex w-64 flex-col bg-[#2E1C10] text-[#C4A882] transition-[transform,width] duration-200 ease-out motion-reduce:transition-none ${
          open ? 'translate-x-0' : '-translate-x-full'
        } lg:translate-x-0 ${expanded ? '' : 'lg:w-[76px]'} ${
          expanded ? 'shadow-pop' : ''
        }`}
      >
        {/* Brand */}
        <div className="border-b border-white/10 px-5 py-4">
          <div className={`flex items-center gap-3 ${expanded ? '' : 'lg:justify-center'}`}>
            <img
              src="/logo.svg"
              alt=""
              className="h-9 w-9 shrink-0 rounded-lg"
            />
            <div className={`whitespace-nowrap ${expanded ? '' : 'lg:hidden'}`}>
              <p className="font-display text-[17px] font-bold leading-tight text-white">CUFMAI</p>
              <p className="text-xs text-[#C4A882]/70">Admin portal</p>
            </div>
          </div>
        </div>

        {/* Grouped nav */}
        <nav className="flex-1 space-y-5 overflow-y-auto overflow-x-hidden px-3 py-4">
          {GROUPS.map((group) => (
            <div key={group.label}>
              <p className={`whitespace-nowrap px-2 pb-1.5 text-xs font-medium text-[#C4A882]/50 ${expanded ? '' : 'lg:hidden'}`}>{group.label}</p>
              <div className="space-y-0.5">
                {group.items.map((item) => {
                  const Icon = item.icon
                  const badge = badgeFor(item.to)
                  return (
                    <NavLink
                      key={item.to}
                      to={item.to}
                      end={item.to === '/'}
                      onClose={onClose}
                      title={expanded ? undefined : item.label}
                      className={({ isActive }) =>
                        `group relative flex items-center gap-2.5 rounded-lg py-2 text-[13.5px] transition-colors ${
                          expanded ? 'px-2.5' : 'px-2.5 lg:justify-center lg:px-2'
                        } ${
                          isActive
                            ? 'bg-primary font-semibold text-white shadow-card ring-1 ring-white/10'
                            : 'text-[#C4A882]/90 hover:bg-white/10 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#E8C99A]/70'
                        }`
                      }
                    >
                      <Icon size={17} strokeWidth={2} className="shrink-0 opacity-90" />
                      <span className={`flex-1 truncate whitespace-nowrap ${expanded ? '' : 'lg:hidden'}`}>{item.label}</span>
                      {badge &&
                        (expanded ? (
                          <span
                            className={`flex h-5 min-w-5 items-center justify-center rounded-full px-1.5 text-[10px] font-bold text-white ${badge.tone}`}
                          >
                            {badge.value}
                          </span>
                        ) : (
                          <span
                            aria-hidden="true"
                            title={`${badge.value} waiting`}
                            className={`absolute right-1.5 top-1.5 hidden h-2.5 w-2.5 rounded-full ring-2 ring-[#2E1C10] lg:block ${badge.tone}`}
                          />
                        ))}
                    </NavLink>
                  )
                })}
              </div>
            </div>
          ))}
        </nav>

        {/* User footer - a button like the seller portal's face: the profile
            header is the control, and the panel holds settings and the way out. */}
        <div className="border-t border-white/10 p-3">
          <div ref={menuRef} className="relative">
            <button
              type="button"
              onClick={() => setMenuOpen((v) => !v)}
              aria-expanded={menuOpen}
              aria-haspopup="menu"
              aria-label="Your account"
              title={expanded ? undefined : 'Your account'}
              className={`flex w-full items-center gap-2.5 rounded-xl border border-white/15 px-3 py-2 text-left transition-colors hover:bg-white/6 ${expanded ? '' : 'lg:justify-center lg:px-2'}`}
            >
              <AvatarInitials name={profile?.full_name} email={profile?.email} />
              <span className={`min-w-0 flex-1 whitespace-nowrap ${expanded ? '' : 'lg:hidden'}`}>
                <span className="block truncate text-[13px] font-semibold text-white">{profile?.full_name ?? 'Admin'}</span>
                <span className="block truncate text-xs text-[#C4A882]/60">{profile?.email}</span>
              </span>
              <ChevronDown size={14} className={`shrink-0 text-[#C4A882]/70 ${expanded ? '' : 'lg:hidden'}`} />
            </button>

            {menuOpen && (
              <div
                role="menu"
                className="absolute bottom-full left-0 z-50 mb-2 w-60 origin-bottom-left overflow-hidden rounded-2xl border border-border bg-card shadow-pop"
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
                  <button
                    type="button"
                    role="menuitemcheckbox"
                    aria-checked={isDark}
                    aria-label="Dark mode"
                    onClick={toggleTheme}
                    className="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-muted transition-colors hover:bg-canvas hover:text-ink"
                  >
                    {isDark ? (
                      <Moon size={16} strokeWidth={2} />
                    ) : (
                      <Sun size={16} strokeWidth={2} />
                    )}
                    <span className="flex-1">Dark mode</span>
                    <span
                      aria-hidden="true"
                      className={`relative h-4 w-7 shrink-0 rounded-full border transition-colors ${
                        isDark ? 'border-primary bg-primary' : 'border-border bg-faint'
                      }`}
                    >
                      <span
                        className={`absolute top-[2px] h-[10px] w-[10px] rounded-full bg-card shadow transition-all ${
                          isDark ? 'left-[15px]' : 'left-[2px]'
                        }`}
                      />
                    </span>
                  </button>
                  <Link
                    to="/settings"
                    role="menuitem"
                    onClick={() => {
                      setMenuOpen(false)
                      onClose()
                    }}
                    className="flex items-center gap-2.5 px-4 py-2.5 text-sm text-muted transition-colors hover:bg-canvas hover:text-ink"
                  >
                    <UserCircle size={16} strokeWidth={2} />
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
      </aside>
    </>
  )
}
