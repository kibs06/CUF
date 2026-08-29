import { useState } from 'react'
import { Eye, Trash2 } from 'lucide-react'
import Modal from '../ui/Modal.jsx'
import { useToast } from '../ui/Toast.jsx'
import { useDeleteUser } from '../../hooks/useUsers.js'

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

export default function UserRow({ user, showSellerStatus, lockout, onView }) {
  const initials = getInitials(user.full_name, user.email)
  const avatarColor = getAvatarColor(user.full_name)
  const suspended = !!user.suspended

  const [deleteOpen, setDeleteOpen] = useState(false)
  const [deleteConfirm, setDeleteConfirm] = useState('')
  const deleteUser = useDeleteUser()
  const { showToast } = useToast()

  const canConfirmDelete = deleteConfirm.trim().toUpperCase() === 'DELETE'

  const handleDelete = async () => {
    try {
      await deleteUser.mutateAsync({ userId: user.id })
      showToast('Account deleted permanently')
    } catch (err) {
      showToast(err.message ?? 'Failed to delete account', 'error')
    } finally {
      setDeleteOpen(false)
      setDeleteConfirm('')
    }
  }

  const isLocked = lockout?.status === 'locked'
  const attemptCount = lockout?.attemptCount ?? 0
  const hasFailedAttempts = attemptCount > 0

  return (
    <>
      <div className={`group flex items-center gap-4 px-5 py-4 transition-colors hover:bg-[#FDFAF7] ${suspended ? 'bg-red-50/40' : isLocked ? 'bg-red-50/30' : ''}`}>
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
          <p className="flex items-center gap-2 truncate text-sm font-semibold text-[#3B2314]">
            {user.full_name || 'Unnamed User'}
            {isLocked && (
              <span className="flex-shrink-0 rounded-full border border-red-300 bg-red-100 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-red-700">
                🔒 Locked
              </span>
            )}
            {!isLocked && suspended && (
              <span className="flex-shrink-0 rounded-full border border-red-200 bg-red-50 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-red-600">
                Suspended
              </span>
            )}
            {!isLocked && !suspended && hasFailedAttempts && (
              <span className="flex-shrink-0 rounded-full border border-amber-200 bg-amber-50 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-amber-600">
                ⚠ {attemptCount} attempt{attemptCount === 1 ? '' : 's'}
              </span>
            )}
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

        {/* Permanent delete — suspended accounts only. Isolated at the far
            right of the row so it can never be confused with the other
            actions. Always guarded by a type-DELETE confirmation. */}
        {suspended && (
          <div className="ml-2 flex flex-shrink-0 border-l border-red-200 pl-2">
            <button
              type="button"
              onClick={() => setDeleteOpen(true)}
              disabled={deleteUser.isPending}
              className="rounded-lg p-2 text-[#D64545] transition-colors hover:bg-red-50 hover:text-red-700 disabled:opacity-50"
              title="Delete permanently"
            >
              <Trash2 size={14} />
            </button>
          </div>
        )}
      </div>

      {/* Delete confirmation — type DELETE to enable */}
      <Modal
        open={deleteOpen}
        onClose={() => {
          setDeleteOpen(false)
          setDeleteConfirm('')
        }}
        title="Delete account permanently?"
        footer={
          <>
            <button
              type="button"
              onClick={() => {
                setDeleteOpen(false)
                setDeleteConfirm('')
              }}
              className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB]"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleDelete}
              disabled={!canConfirmDelete || deleteUser.isPending}
              className="rounded-xl bg-[#D64545] px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-red-700 disabled:opacity-40"
            >
              {deleteUser.isPending ? 'Deleting…' : 'Delete forever'}
            </button>
          </>
        }
      >
        <p className="mb-4 text-sm text-[#6B5C4E]">
          This permanently deletes{' '}
          <strong className="text-[#3B2314]">{user.full_name}</strong> — their
          account, store, and data. This <strong className="text-[#D64545]">cannot be undone</strong>.
        </p>
        <p className="mb-4 text-sm text-[#6B5C4E]">
          Customer orders placed at their store will be kept but detached from
          the store.
        </p>
        <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
          Type DELETE to confirm
        </label>
        <input
          value={deleteConfirm}
          onChange={(e) => setDeleteConfirm(e.target.value)}
          autoFocus
          className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-3 py-2 text-sm text-[#3B2314] outline-none transition-colors focus:border-[#D64545] focus:ring-2 focus:ring-[#D64545]/20"
          placeholder="DELETE"
        />
      </Modal>
    </>
  )
}
