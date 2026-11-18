import { Shield, ShoppingBag, Store } from 'lucide-react'
import { getInitials } from '../../lib/constants'

export const ROLE_ORDER = { admin: 0, seller: 1, customer: 2 }

export const ROLE_META = {
  customer: {
    label: 'Customer',
    Icon: ShoppingBag,
    pill: 'bg-pendingSoft text-pendingInk ring-pending/30',
    avatar: 'bg-[#F7E7C8] text-[#8A5A00]',
    hex: '#E8A020',
  },
  seller: {
    label: 'Seller',
    Icon: Store,
    pill: 'bg-accentSoft text-[#0B6B69] ring-accent/25',
    avatar: 'bg-[#DDF1EF] text-[#0B6B69]',
    hex: '#0E7C7B',
  },
  admin: {
    label: 'Admin',
    Icon: Shield,
    pill: 'bg-[#F1E7DD] text-[#5B3A1E] ring-primary/25',
    avatar: 'bg-[#EADFD3] text-[#6F4520]',
    hex: '#6F4520',
  },
}

/**
 * One account's access state, in the order an admin needs to see it:
 * suspension first, then a lockout, then a seller whose application is not
 * approved yet, then any failed attempts, then ordinary active access.
 */
export function accessState(user, lockout) {
  if (user?.suspended) {
    return { filter: 'suspended', label: 'Suspended', tone: 'text-error', dot: 'bg-error' }
  }
  if (lockout?.status === 'locked') {
    return { filter: 'locked', label: 'Sign-in locked', tone: 'text-error', dot: 'bg-error' }
  }

  const attempts = Number(lockout?.attemptCount) || 0
  if (user?.role === 'seller' && user?.seller_status === 'pending') {
    return { filter: 'active', label: 'Seller pending', tone: 'text-pending', dot: 'bg-pending' }
  }
  if (user?.role === 'seller' && user?.seller_status === 'rejected') {
    return { filter: 'active', label: 'Seller rejected', tone: 'text-error', dot: 'bg-error' }
  }
  if (attempts > 0) {
    return {
      filter: 'active',
      label: `${attempts} failed attempt${attempts === 1 ? '' : 's'}`,
      tone: 'text-pending',
      dot: 'bg-pending',
    }
  }
  return { filter: 'active', label: 'Active', tone: 'text-muted', dot: 'bg-accent' }
}

export function relativeJoined(value) {
  const then = new Date(value).getTime()
  if (!Number.isFinite(then)) return '—'
  const days = Math.floor((Date.now() - then) / 86_400_000)
  if (days <= 0) return 'Today'
  if (days === 1) return 'Yesterday'
  if (days < 30) return `${days} days ago`
  if (days < 365) {
    const months = Math.floor(days / 30)
    return `${months} month${months === 1 ? '' : 's'} ago`
  }
  const years = Math.floor(days / 365)
  return `${years} year${years === 1 ? '' : 's'} ago`
}

export function RoleBadge({ role }) {
  const meta = ROLE_META[role] ?? ROLE_META.customer
  const Icon = meta.Icon
  return (
    <span
      className={`inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2 py-0.5 text-[11px] font-bold ring-1 ring-inset ${meta.pill}`}
    >
      <Icon size={10} strokeWidth={2.4} aria-hidden="true" />
      {meta.label}
    </span>
  )
}

export function AccessStatus({ user, lockout }) {
  const state = accessState(user, lockout)
  return (
    <span className={`inline-flex items-center gap-1.5 whitespace-nowrap text-[11.5px] font-medium ${state.tone}`}>
      <span className={`h-1.5 w-1.5 rounded-full ${state.dot}`} aria-hidden="true" />
      {state.label}
    </span>
  )
}

export function UserAvatar({ user, size = 'md' }) {
  const meta = ROLE_META[user?.role] ?? ROLE_META.customer
  const dimensions = size === 'sm' ? 'h-9 w-9' : 'h-10 w-10'

  return (
    <span className="inline-flex shrink-0" aria-hidden="true">
      {user?.avatar_url ? (
        <img
          src={user.avatar_url}
          alt=""
          className={`${dimensions} rounded-xl object-cover ring-1 ring-black/5`}
        />
      ) : (
        <span
          className={`${dimensions} flex items-center justify-center rounded-xl text-[13px] font-bold ${meta.avatar}`}
        >
          {getInitials(user?.full_name, user?.email)}
        </span>
      )}
    </span>
  )
}
