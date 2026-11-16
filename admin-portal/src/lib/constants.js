// ─── Can an admin publish a model from this portal? (roadmap P2, V2.11) ──
//
// The Flutter admin queue's own switch is `AppConstants.adminModelUploadAllowed`
// — off — and this is the portal's equivalent, for the same reason and one
// more. The app's reason: the whole publish path ends in `validate-shoe-model`,
// which is the only caller the database lets write `product_models.status =
// 'active'`, so with the switch off nothing can go live by accident. The
// portal's extra reason: this path also *needs the request-flow migration applied
// to the live project* (`20260928140000`), and until that happens a publish here
// would fail in a way that reads like a bug in this page.
//
// Off unless `VITE_ADMIN_MODEL_UPLOAD=true` is set in `.env`, so a plain build
// behaves exactly like yesterday's — the same "ships dark" convention the app
// uses for every phase of this pipeline.
export const MODEL_UPLOAD_ENABLED = import.meta.env.VITE_ADMIN_MODEL_UPLOAD === 'true'

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

export const BANNER_LINK_TYPES = [
  { value: 'none', label: 'No link' },
  { value: 'category', label: 'Category' },
  { value: 'product', label: 'Product' },
  { value: 'url', label: 'URL' },
]

export const BANNER_CATEGORIES = [
  'Boots', 'Sandals', 'Sneakers', 'Formal', 'Casual',
  'Slip-ons', 'Sports', 'Heels', 'Loafers', 'Mules', 'Platforms',
]

export const PAYMENT_INTENT_STATUSES = [
  'pending',
  'succeeded',
  'failed',
  'expired',
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
