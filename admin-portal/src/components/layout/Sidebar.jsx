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
  BarChart2,
  Settings,
  LogOut,
  Image,
  Sparkles,
} from 'lucide-react'

const NAV_ITEMS = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/users', label: 'Users', icon: Users },
  { to: '/seller-applications', label: 'Seller Applications', icon: Store },
  { to: '/products', label: 'Products', icon: Package },
  { to: '/model-requests', label: '3D Fitting Requests', icon: Cuboid },
  { to: '/orders', label: 'Orders', icon: ShoppingCart },
  { to: '/transactions', label: 'Transactions', icon: Wallet },
  { to: '/reports', label: 'Reports', icon: Flag },
  { to: '/analytics', label: 'Analytics', icon: BarChart2 },
  { to: '/banners', label: 'Banners', icon: Image },
  // A component surface rather than a data one: it reads nothing from Supabase
  // and owns no rows. Kept in the main nav because it is the reference for the
  // AI voice-assistant visual, and a reference nobody can find is a demo.
  { to: '/ai', label: 'AI', icon: Sparkles },
  { to: '/settings', label: 'Settings', icon: Settings },
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

      // Sellers' 3D model asks. A queue nobody is told about is a queue nobody
      // opens: the row is filed from the app, so this badge is the only signal
      // an admin sitting in the portal gets that there is work waiting.
      // `requested` and `in_progress` are the two open states.
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
    // Refresh every 60 seconds
    const interval = setInterval(fetchCount, 60000)
    return () => clearInterval(interval)
  }, [])

  return (
    <>
      {open && (
        <div
          className="fixed inset-0 z-40 bg-[#3B2314]/50 lg:hidden"
          onClick={onClose}
        />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-72 flex-col bg-[#3B2314] text-[#C4A882] transition-transform lg:sticky lg:top-0 lg:h-screen lg:bottom-auto lg:translate-x-0 ${
          open ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        {/* Logo */}
        <div className="border-b border-white/10 p-5">
          <div className="flex items-center gap-3">
            <div
              className="h-10 w-10 text-[#C4A882]"
              dangerouslySetInnerHTML={{ __html: SHOE_SOLE_SVG }}
            />
            <div>
              <p className="font-display text-lg font-bold leading-tight text-white">SoleVision</p>
              <p className="text-xs text-[#C4A882]/60">Admin Portal</p>
            </div>
          </div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 space-y-1 overflow-y-auto p-4">
          {NAV_ITEMS.map((item) => {
            const Icon = item.icon
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.to === '/'}
                onClick={onClose}
                className={({ isActive }) =>
                  `flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-all ${
                    isActive
                      ? 'bg-[#8B5A2B] text-white shadow-md'
                      : 'text-[#C4A882] hover:bg-[#4A2E1A] hover:text-white'
                  }`
                }
              >
                <Icon size={18} />
                <span className="flex-1">{item.label}</span>
                {item.to === '/reports' && highPriorityCount > 0 && (
                  <span className="flex h-5 min-w-5 items-center justify-center rounded-full bg-[#D64545] px-1.5 text-[10px] font-bold text-white">
                    {highPriorityCount > 9 ? '9+' : highPriorityCount}
                  </span>
                )}
                {item.to === '/model-requests' && waitingModelRequests > 0 && (
                  <span className="flex h-5 min-w-5 items-center justify-center rounded-full bg-[#E8A020] px-1.5 text-[10px] font-bold text-white">
                    {waitingModelRequests > 9 ? '9+' : waitingModelRequests}
                  </span>
                )}
              </NavLink>
            )
          })}
        </nav>

        {/* Bottom section: user + logout */}
        <div className="border-t border-white/10 p-4">
          <div className="mb-3 flex items-center gap-3">
            <AvatarInitials name={profile?.full_name} email={profile?.email} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium text-white">{profile?.full_name ?? 'Admin'}</p>
              <p className="truncate text-xs text-[#C4A882]/60">{profile?.email}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={signOut}
            className="flex w-full items-center gap-2 rounded-xl border border-white/20 px-4 py-2 text-sm transition-colors hover:bg-red-900/20 hover:text-red-400"
          >
            <LogOut size={16} />
            Log out
          </button>
        </div>
      </aside>
    </>
  )
}
