import { Link, NavLink } from 'react-router-dom'
import { useAdminNotifications } from '../../hooks/useAdminNotifications.js'
import { SHOW_GCASH_VERIFICATION } from '../../lib/features.js'
import { useState } from 'react'
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
  Settings,
  Image,
  Landmark,
  BadgeCheck,
  Banknote,
  RotateCcw,
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
      ...(SHOW_GCASH_VERIFICATION
        ? [{ to: '/payment-verification', label: 'GCash Verification', icon: BadgeCheck }]
        : []),
      { to: '/payouts', label: 'Payouts', icon: Banknote },
      { to: '/refunds', label: 'Replacements owed', icon: RotateCcw },
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
  const { data: notificationCounts } = useAdminNotifications()
  const highPriorityCount = notificationCounts?.reports ?? 0
  const waitingModelRequests = notificationCounts?.modelRequests ?? 0
  const proofsUnderReview = notificationCounts?.gcashProofs ?? 0
  const [hovered, setHovered] = useState(false)

  // The drawer is always full-width: on touch screens there is no hover, so an
  // open drawer is expanded by definition and hover only matters on desktop.
  const expanded = hovered || open

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
      </aside>
    </>
  )
}
