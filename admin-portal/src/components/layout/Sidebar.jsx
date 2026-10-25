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
  Sparkles,
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
      { to: '/ai', label: 'AI', icon: Sparkles },
      { to: '/audit-logs', label: 'Audit Logs', icon: ScrollText },
      { to: '/settings', label: 'Settings', icon: Settings },
    ],
  },
]

export default function Sidebar({ open, onClose }) {
  const { profile, signOut } = useAuth()
  const [highPriorityCount, setHighPriorityCount] = useState(0)
  const [waitingModelRequests, setWaitingModelRequests] = useState(0)

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
        className={`sole-scroll fixed inset-y-0 left-0 z-50 flex w-64 flex-col bg-[#2E1C10] text-[#C4A882] transition-transform lg:sticky lg:top-0 lg:h-screen lg:bottom-auto lg:translate-x-0 ${
          open ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        {/* Brand */}
        <div className="border-b border-white/10 px-5 py-4">
          <div className="flex items-center gap-3">
            <div
              className="h-9 w-9 rounded-lg bg-white/8 p-1.5 text-[#E8C99A]"
              dangerouslySetInnerHTML={{ __html: SHOE_SOLE_SVG }}
            />
            <div>
              <p className="font-display text-[17px] font-bold leading-tight text-white">SoleVision</p>
              <p className="text-xs text-[#C4A882]/70">Admin portal</p>
            </div>
          </div>
        </div>

        {/* Grouped nav */}
        <nav className="flex-1 space-y-5 overflow-y-auto px-3 py-4">
          {GROUPS.map((group) => (
            <div key={group.label}>
              <p className="px-2 pb-1.5 text-xs font-medium text-[#C4A882]/50">{group.label}</p>
              <div className="space-y-0.5">
                {group.items.map((item) => {
                  const Icon = item.icon
                  const badge = badgeFor(item.to)
                  return (
                    <NavLink
                      key={item.to}
                      to={item.to}
                      end={item.to === '/'}
                      onClick={onClose}
                      className={({ isActive }) =>
                        `group relative flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-[13.5px] transition-colors ${
                          isActive
                            ? 'bg-[#8B5A2B] font-semibold text-white'
                            : 'text-[#C4A882]/90 hover:bg-white/6 hover:text-white'
                        }`
                      }
                    >
                      <Icon size={17} strokeWidth={2} className="shrink-0 opacity-90" />
                      <span className="flex-1 truncate">{item.label}</span>
                      {badge && (
                        <span
                          className={`flex h-5 min-w-5 items-center justify-center rounded-full px-1.5 text-[10px] font-bold text-white ${badge.tone}`}
                        >
                          {badge.value}
                        </span>
                      )}
                    </NavLink>
                  )
                })}
              </div>
            </div>
          ))}
        </nav>

        {/* User footer */}
        <div className="border-t border-white/10 p-3">
          <div className="mb-2 flex items-center gap-2.5 rounded-lg px-1.5 py-1.5">
            <AvatarInitials name={profile?.full_name} email={profile?.email} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-[13px] font-semibold text-white">{profile?.full_name ?? 'Admin'}</p>
              <p className="truncate text-xs text-[#C4A882]/60">{profile?.email}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={signOut}
            className="flex w-full items-center justify-center gap-2 rounded-lg border border-white/15 px-3 py-2 text-[13px] font-medium text-[#C4A882] transition-colors hover:bg-white/6 hover:text-white"
          >
            <LogOut size={15} />
            Log out
          </button>
        </div>
      </aside>
    </>
  )
}
