import { NavLink } from 'react-router-dom'
import { SHOE_SOLE_SVG } from '../../lib/constants'
import { useAuth } from '../../hooks/useAuth.jsx'
import AvatarInitials from '../ui/AvatarInitials.jsx'
import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
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
  LogOut,
  Image,
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
    ],
  },
  {
    label: 'System',
    items: [
      { to: '/banners', label: 'Banners', icon: Image },
      { to: '/audit-logs', label: 'Audit Logs', icon: ScrollText },
      { to: '/settings', label: 'Settings', icon: Settings },
    ],
  },
]

export default function Sidebar({ open, onClose }) {
  const { profile, signOut } = useAuth()
  const [highPriorityCount, setHighPriorityCount] = useState(0)
  const [waitingModelRequests, setWaitingModelRequests] = useState(0)
  const [hovered, setHovered] = useState(false)
  // The drawer is always full-width: on touch screens there is no hover, so an
  // open drawer is expanded by definition and hover only matters on desktop.
  const expanded = hovered || open

  useEffect(() => {
    const fetchCount = async () => {
      try {
        const { count } = await supabase
          .from('reports')
          .select('*', { count: 'exact', head: true })
          .eq('priority', 'high')
          .in('status', ['pending', 'under_review'])
        setHighPriorityCount(count ?? 0)
      } catch (_) {
        // silently fail — badge is optional
      }

      try {
        const { count } = await supabase
          .from('shoe_model_requests')
          .select('*', { count: 'exact', head: true })
          .in('status', ['requested', 'in_progress'])
        setWaitingModelRequests(count ?? 0)
      } catch (_) {
        // silently fail — badge is optional
      }
    }
    fetchCount()
    const interval = setInterval(fetchCount, 60000)
    return () => clearInterval(interval)
  }, [])

  const badgeFor = (to) => {
    if (to === '/reports' && highPriorityCount > 0)
      return { value: highPriorityCount > 9 ? '9+' : highPriorityCount, tone: 'bg-[#D64545]' }
    if (to === '/model-requests' && waitingModelRequests > 0)
      return { value: waitingModelRequests > 9 ? '9+' : waitingModelRequests, tone: 'bg-[#E8A020]' }
    return null
  }

  return (
    <>
      {open && (
        <div
          className="fixed inset-0 z-40 bg-[#3B2314]/50 lg:hidden"
          onClick={onClose}
        />
      )}

      <aside
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        className={`sole-scroll fixed inset-y-0 left-0 z-50 flex w-64 flex-col bg-[#2E1C10] text-[#C4A882] transition-[transform,width] duration-200 ease-out motion-reduce:transition-none ${
          open ? 'translate-x-0' : '-translate-x-full'
        } lg:translate-x-0 ${expanded ? '' : 'lg:w-[76px]'} ${
          expanded ? 'shadow-pop' : ''
        }`}
      >
        {/* Brand */}
        <div className="border-b border-white/10 px-5 py-4">
          <div className={`flex items-center gap-3 ${expanded ? '' : 'lg:justify-center'}`}>
            <div
              className="h-9 w-9 shrink-0 rounded-lg bg-white/8 p-1.5 text-[#E8C99A]"
              dangerouslySetInnerHTML={{ __html: SHOE_SOLE_SVG }}
            />
            <div className={`whitespace-nowrap ${expanded ? '' : 'lg:hidden'}`}>
              <p className="font-display text-[17px] font-bold leading-tight text-white">SoleVision</p>
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
                            ? 'bg-[#8B5A2B] font-semibold text-white'
                            : 'text-[#C4A882]/90 hover:bg-white/6 hover:text-white'
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
                            className={`absolute right-1.5 top-1.5 hidden h-2 w-2 rounded-full lg:block ${badge.tone}`}
                          />
                        ))}
                    </NavLink>
                  )
                })}
              </div>
            </div>
          ))}
        </nav>

        {/* User footer */}
        <div className="border-t border-white/10 p-3">
          <div className={`mb-2 flex items-center gap-2.5 rounded-lg px-1.5 py-1.5 ${expanded ? '' : 'lg:justify-center'}`}>
            <AvatarInitials name={profile?.full_name} email={profile?.email} />
            <div className={`min-w-0 flex-1 whitespace-nowrap ${expanded ? '' : 'lg:hidden'}`}>
              <p className="truncate text-[13px] font-semibold text-white">{profile?.full_name ?? 'Admin'}</p>
              <p className="truncate text-xs text-[#C4A882]/60">{profile?.email}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={signOut}
            title={expanded ? undefined : 'Log out'}
            className="flex w-full items-center justify-center gap-2 rounded-lg border border-white/15 px-3 py-2 text-[13px] font-medium text-[#C4A882] transition-colors hover:bg-white/6 hover:text-white"
          >
            <LogOut size={15} />
            <span className={`whitespace-nowrap ${expanded ? '' : 'lg:hidden'}`}>Log out</span>
          </button>
        </div>
      </aside>
    </>
  )
}
