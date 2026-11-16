import { useState } from 'react'
import { ChevronRight, Trash2 } from 'lucide-react'
import Modal from '../ui/Modal.jsx'
import { useToast } from '../ui/Toast.jsx'
import { useDeleteUser } from '../../hooks/useUsers.js'
import { formatDate } from '../../lib/constants'
import { AccessStatus, RoleBadge, UserAvatar, relativeJoined } from './userMeta.jsx'

export default function UserRow({ user, lockout, onView, isSelf = false }) {
  const suspended = !!user.suspended
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [deleteConfirm, setDeleteConfirm] = useState('')
  const deleteUser = useDeleteUser()
  const { showToast } = useToast()

  const canConfirmDelete = deleteConfirm.trim().toUpperCase() === 'DELETE'
  const name = user.full_name || 'Unnamed user'

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

  return (
    <>
      <div
        role="listitem"
        className={`group admin-list-item admin-list-card ${
          suspended ? 'bg-errorSoft/20' : ''
        }`}
      >
        <div className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 px-4 py-3 md:grid-cols-[minmax(0,1fr)_170px_112px_auto] md:gap-4 md:px-5">
          {/* Identity — the primary action, so the whole name block is the button. */}
          <button
            type="button"
            onClick={() => onView?.(user)}
            className="flex min-w-0 items-center gap-3 text-left"
          >
            <UserAvatar user={user} />
            <span className="min-w-0 flex-1">
              <span className="flex items-center gap-1.5">
                <span className="truncate text-[14px] font-semibold text-ink">{name}</span>
                {isSelf && (
                  <span className="shrink-0 rounded-full bg-canvas px-1.5 py-0.5 text-[10px] font-semibold text-muted ring-1 ring-border">
                    You
                  </span>
                )}
              </span>
              <span className="block truncate text-[12px] text-muted">{user.email || 'No email'}</span>

              {/* Compact access summary for the mobile card layout. */}
              <span className="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1 md:hidden">
                <RoleBadge role={user.role} />
                <AccessStatus user={user} lockout={lockout} />
                <span className="text-[12px] text-muted">Joined {formatDate(user.created_at)}</span>
              </span>
            </span>
          </button>

          <div className="hidden md:block">
            <RoleBadge role={user.role} />
            <div className="mt-1">
              <AccessStatus user={user} lockout={lockout} />
            </div>
          </div>

          <div className="hidden md:block">
            <p className="font-mono text-[12px] text-secondary">{formatDate(user.created_at)}</p>
            <p className="mt-0.5 text-[12px] text-muted">{relativeJoined(user.created_at)}</p>
          </div>

          <div className="flex items-center gap-0.5">
            <button
              type="button"
              onClick={() => onView?.(user)}
              aria-label={`View ${name}`}
              className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-muted/60 transition-colors hover:bg-canvas hover:text-ink group-hover:text-muted"
            >
              <ChevronRight size={16} />
            </button>
            {suspended && (
              <button
                type="button"
                onClick={() => setDeleteOpen(true)}
                disabled={deleteUser.isPending}
                aria-label={`Delete ${name} permanently`}
                title="Delete permanently"
                className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-error/70 transition-colors hover:bg-errorSoft hover:text-error disabled:opacity-50"
              >
                <Trash2 size={15} />
              </button>
            )}
          </div>
        </div>
      </div>

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
              className="rounded-xl border border-border px-4 py-2 text-sm text-muted hover:bg-canvas"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleDelete}
              disabled={!canConfirmDelete || deleteUser.isPending}
              className="rounded-xl bg-error px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-red-700 disabled:opacity-40"
            >
              {deleteUser.isPending ? 'Deleting…' : 'Delete forever'}
            </button>
          </>
        }
      >
        <p className="mb-4 text-sm text-muted">
          This permanently deletes <strong className="text-secondary">{name}</strong> — their
          account, store, and data. This <strong className="text-error">cannot be undone</strong>.
        </p>
        <p className="mb-4 text-sm text-muted">
          Customer orders placed at their store will be kept but detached from the store.
        </p>
        <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-muted">
          Type DELETE to confirm
        </label>
        <input
          value={deleteConfirm}
          onChange={(event) => setDeleteConfirm(event.target.value)}
          autoFocus
          className="w-full rounded-xl border border-border bg-surface px-3 py-2 text-sm text-secondary outline-none transition-colors focus:border-error focus:ring-2 focus:ring-error/20"
          placeholder="DELETE"
        />
      </Modal>
    </>
  )
}
