import { X } from 'lucide-react'

function getInitials(name) {
  return (name || 'U')
    .split(' ')
    .map((w) => w[0])
    .join('')
    .toUpperCase()
    .slice(0, 2)
}

export default function UserDetailModal({ user, onClose }) {
  if (!user) return null

  const initials = getInitials(user.full_name)

  const roleBg =
    user.role === 'seller'
      ? 'bg-teal-50'
      : user.role === 'admin'
        ? 'bg-red-50'
        : 'bg-amber-50'

  const avatarBg =
    user.role === 'seller'
      ? 'bg-[#4ECDC4]'
      : user.role === 'admin'
        ? 'bg-[#D64545]'
        : 'bg-[#E8A020]'

  const roleBadge =
    user.role === 'seller'
      ? 'bg-teal-100 text-teal-700'
      : user.role === 'admin'
        ? 'bg-red-100 text-red-700'
        : 'bg-amber-100 text-amber-700'

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-[#3B2314]/50" onClick={onClose} />
      <div className="relative z-10 w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-2xl">
        {/* Header with role color */}
        <div className={`p-6 ${roleBg}`}>
          <div className="flex items-start justify-between">
            <div className="flex items-center gap-4">
              {user.avatar_url ? (
                <img
                  src={user.avatar_url}
                  alt=""
                  className="h-16 w-16 rounded-2xl border-2 border-white object-cover shadow-md"
                />
              ) : (
                <div
                  className={`flex h-16 w-16 items-center justify-center rounded-2xl text-2xl font-bold text-white shadow-md ${avatarBg}`}
                >
                  {initials}
                </div>
              )}
              <div>
                <h2 className="font-display text-xl font-bold text-[#3B2314]">
                  {user.full_name || 'Unnamed User'}
                </h2>
                <p className="mt-0.5 text-sm text-[#6B5C4E]">{user.email}</p>
                <span className={`mt-2 inline-block rounded-full px-3 py-1 text-xs font-bold ${roleBadge}`}>
                  {user.role.charAt(0).toUpperCase() + user.role.slice(1)}
                </span>
              </div>
            </div>
            <button
              type="button"
              onClick={onClose}
              className="flex h-8 w-8 items-center justify-center rounded-lg hover:bg-black/10"
            >
              <X size={16} className="text-[#6B5C4E]" />
            </button>
          </div>
        </div>

        {/* Details */}
        <div className="space-y-4 p-6">
          <div className="grid grid-cols-2 gap-4">
            <div className="rounded-xl bg-[#F5F0EB] p-3">
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Member Since
              </p>
              <p className="font-mono text-sm font-semibold text-[#3B2314]">
                {new Date(user.created_at).toLocaleDateString('en-PH', {
                  month: 'long',
                  year: 'numeric',
                })}
              </p>
            </div>
            <div className="rounded-xl bg-[#F5F0EB] p-3">
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                User ID
              </p>
              <p className="truncate font-mono text-xs text-[#6B5C4E]" title={user.id}>
                {user.id.slice(0, 8)}...
              </p>
            </div>
            {user.phone && (
              <div className="rounded-xl bg-[#F5F0EB] p-3">
                <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                  Phone
                </p>
                <p className="font-mono text-sm text-[#3B2314]">{user.phone}</p>
              </div>
            )}
            {user.seller_status && (
              <div className="rounded-xl bg-[#F5F0EB] p-3">
                <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                  Seller Status
                </p>
                <span
                  className={`rounded-full px-2.5 py-1 text-xs font-bold ${
                    user.seller_status === 'approved'
                      ? 'bg-teal-100 text-teal-700'
                      : user.seller_status === 'pending'
                        ? 'bg-amber-100 text-amber-700'
                        : 'bg-red-100 text-red-600'
                  }`}
                >
                  {user.seller_status}
                </span>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
