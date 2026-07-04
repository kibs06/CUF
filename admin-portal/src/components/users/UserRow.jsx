import { Eye } from 'lucide-react'

const AVATAR_COLORS = [
  'bg-[#8B5A2B]', 'bg-[#4ECDC4]', 'bg-[#E8A020]',
  'bg-[#D64545]', 'bg-[#3B2314]',
]

function getInitials(name, email) {
  const source = name || email || 'U'
  return source
    .split(' ')
    .map((w) => w[0])
    .join('')
    .toUpperCase()
    .slice(0, 2)
}

function getAvatarColor(name) {
  const charCode = name?.charCodeAt(0) ?? 0
  return AVATAR_COLORS[charCode % AVATAR_COLORS.length] || AVATAR_COLORS[0]
}

export default function UserRow({ user, showSellerStatus, onView }) {
  const initials = getInitials(user.full_name, user.email)
  const avatarColor = getAvatarColor(user.full_name)

  return (
    <div className="group flex items-center gap-4 px-5 py-4 transition-colors hover:bg-[#FDFAF7]">
      {/* Avatar */}
      <div className="flex-shrink-0">
        {user.avatar_url ? (
          <img
            src={user.avatar_url}
            alt=""
            className="h-10 w-10 rounded-full border-2 border-[#D9D0C7] object-cover"
          />
        ) : (
          <div
            className={`flex h-10 w-10 items-center justify-center rounded-full border-2 border-white text-sm font-bold text-white shadow-sm ${avatarColor}`}
          >
            {initials}
          </div>
        )}
      </div>

      {/* Name + email */}
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-semibold text-[#3B2314]">
          {user.full_name || 'Unnamed User'}
        </p>
        <p className="truncate text-xs text-[#6B5C4E]">{user.email}</p>
      </div>

      {/* Seller status badge (sellers only) */}
      {showSellerStatus && user.seller_status && (
        <span
          className={`flex-shrink-0 rounded-full border px-2.5 py-1 text-xs font-bold ${
            user.seller_status === 'approved'
              ? 'border-teal-200 bg-teal-50 text-teal-700'
              : user.seller_status === 'pending'
                ? 'border-amber-200 bg-amber-50 text-amber-700'
                : 'border-red-200 bg-red-50 text-red-600'
          }`}
        >
          {user.seller_status.charAt(0).toUpperCase() + user.seller_status.slice(1)}
        </span>
      )}

      {/* Joined date */}
      <span className="hidden flex-shrink-0 font-mono text-xs text-[#6B5C4E] md:block">
        {new Date(user.created_at).toLocaleDateString('en-PH', {
          month: 'short',
          day: 'numeric',
          year: 'numeric',
        })}
      </span>

      {/* Actions — visible on hover */}
      <div className="flex flex-shrink-0 items-center gap-1.5 opacity-0 transition-opacity group-hover:opacity-100">
        <button
          type="button"
          onClick={() => onView?.(user)}
          className="rounded-lg p-2 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] hover:text-[#3B2314]"
          title="View profile"
        >
          <Eye size={14} />
        </button>
      </div>
    </div>
  )
}
