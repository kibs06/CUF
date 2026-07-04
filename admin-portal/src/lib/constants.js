export const SHOE_SOLE_SVG = `<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M50,12 C62,12 68,26 64,40 C60,54 66,74 62,84 C58,89 42,89 38,84 C34,74 40,54 36,40 C32,26 38,12 50,12 Z" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="43" y1="24" x2="57" y2="24" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="41" y1="34" x2="59" y2="34" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="42" y1="44" x2="58" y2="44" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="43" y1="54" x2="57" y2="54" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="45" y1="70" x2="55" y2="70" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="46" y1="78" x2="54" y2="78" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
</svg>`

export const ROLES = {
  CUSTOMER: 'customer',
  SELLER: 'seller',
  ADMIN: 'admin',
}

export const SELLER_STATUSES = {
  PENDING: 'pending',
  APPROVED: 'approved',
  REJECTED: 'rejected',
  NONE: 'none',
}

export const ORDER_STATUSES = [
  'pending',
  'placed',
  'confirmed',
  'preparing',
  'ready',
  'shipped',
  'received',
  'delivered',
  'cancelled',
]

export function formatDate(value) {
  if (!value) return '—'
  return new Date(value).toLocaleDateString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

export function formatDateTime(value) {
  if (!value) return '—'
  return new Date(value).toLocaleString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function formatCurrency(value) {
  const num = Number(value) || 0
  return `₱${num.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

export function getInitials(name, email) {
  const source = name || email || '?'
  const parts = source.trim().split(/\s+/)
  if (parts.length >= 2) {
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
  }
  return source.slice(0, 2).toUpperCase()
}

export function shortId(id) {
  if (!id) return '—'
  const str = String(id)
  return str.length > 8 ? `${str.slice(0, 8)}…` : str
}
