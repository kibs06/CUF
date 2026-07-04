import { useMemo, useState } from 'react'
import Badge from '../components/ui/Badge.jsx'
import AvatarInitials from '../components/ui/AvatarInitials.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import Modal from '../components/ui/Modal.jsx'
import { TableSkeleton } from '../components/ui/Skeleton.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import {
  useSellerApplications,
  useApproveApplication,
  useRejectApplication,
} from '../hooks/useSellerApplications.js'
import { formatDate } from '../lib/constants'


const TABS = [
  { key: 'pending', label: 'Pending' },
  { key: 'approved', label: 'Approved' },
  { key: 'rejected', label: 'Rejected' },
  { key: 'all', label: 'All' },
]

export default function SellerApplications() {
  const [tab, setTab] = useState('pending')
  const [loadingId, setLoadingId] = useState(null)
  const [rejectTarget, setRejectTarget] = useState(null)
  const [rejectReason, setRejectReason] = useState('')
  const { showToast } = useToast()

  const { data, isLoading, isError, error } = useSellerApplications(tab)
  const approve = useApproveApplication()
  const reject = useRejectApplication()

  const pendingCount = useMemo(() => {
    if (tab === 'pending') return data?.length ?? 0
    return null
  }, [tab, data])

  const handleApprove = async (userId) => {
    setLoadingId(userId)
    try {
      await approve.mutateAsync(userId)
      showToast('Seller approved successfully')
    } catch (err) {
      showToast(err.message ?? 'Approval failed', 'error')
    } finally {
      setLoadingId(null)
    }
  }

  const handleReject = async () => {
    if (!rejectTarget) return
    setLoadingId(rejectTarget.id)
    try {
      await reject.mutateAsync({ userId: rejectTarget.id, reason: rejectReason })
      showToast('Application rejected')
      setRejectTarget(null)
      setRejectReason('')
    } catch (err) {
      showToast(err.message ?? 'Rejection failed', 'error')
    } finally {
      setLoadingId(null)
    }
  }

  return (
    <div className="space-y-6">
      {/* Pill tabs */}
      <div className="flex gap-2">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setTab(t.key)}
            className={`rounded-xl px-4 py-2 text-sm font-medium transition-all ${
              tab === t.key
                ? 'bg-[#8B5A2B] text-white shadow-sm'
                : 'border border-[#D9D0C7] bg-white text-[#6B5C4E] hover:bg-[#F5F0EB]'
            } ${t.key === 'pending' && pendingCount > 0 ? 'ring-2 ring-[#E8A020]/40' : ''}`}
          >
            {t.label}
            {t.key === 'pending' && pendingCount > 0 && (
              <span className="ml-2 rounded-full bg-[#E8A020] px-1.5 py-0.5 text-xs text-white">
                {pendingCount}
              </span>
            )}
          </button>
        ))}
      </div>

      {isLoading && <TableSkeleton cols={5} rows={6} />}

      {isError && (
        <div className="rounded-2xl border border-[#D9D0C7] bg-white p-8 text-center text-[#6B5C4E]">
          <p className="text-sm text-[#D64545]">{error.message}</p>
        </div>
      )}

      {!isLoading && !isError && !data?.length && (
        <EmptyState
          icon="⏳"
          title="No pending applications"
          description="New seller sign-ups will appear here in real time."
        />
      )}

      {!isLoading && !isError && data?.length > 0 && (
        <div className="space-y-3">
          {data.map((row) => (
            <div
              key={row.id}
              className="flex items-center justify-between rounded-xl border border-[#D9D0C7] bg-white p-4 transition-shadow hover:shadow-sm"
            >
              <div className="flex items-center gap-3">
                <AvatarInitials name={row.full_name} email={row.email} />
                <div>
                  <p className="text-sm font-semibold text-[#3B2314]">{row.full_name}</p>
                  <p className="text-xs text-[#6B5C4E]">{row.email}</p>
                  <p className="text-xs text-[#6B5C4E] mt-0.5">
                    Applied {formatDate(row.created_at)}
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <Badge label={row.seller_status} variant={row.seller_status} />
                {row.seller_status === 'pending' && (
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      disabled={loadingId === row.id}
                      onClick={() => handleApprove(row.id)}
                      className="rounded-lg bg-[#4ECDC4] px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-teal-600 disabled:opacity-50"
                    >
                      {loadingId === row.id && approve.isPending ? '…' : 'Approve'}
                    </button>
                    <button
                      type="button"
                      disabled={loadingId === row.id}
                      onClick={() => setRejectTarget(row)}
                      className="rounded-lg border border-[#D64545] px-3 py-1.5 text-xs font-semibold text-[#D64545] transition-colors hover:bg-red-50 disabled:opacity-50"
                    >
                      Reject
                    </button>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      <Modal
        open={!!rejectTarget}
        onClose={() => {
          setRejectTarget(null)
          setRejectReason('')
        }}
        title="Reject Application"
        footer={
          <>
            <button
              type="button"
              onClick={() => setRejectTarget(null)}
              className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB]"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleReject}
              disabled={loadingId === rejectTarget?.id}
              className="rounded-xl border border-[#D64545] px-4 py-2 text-sm font-semibold text-[#D64545] transition-colors hover:bg-red-50 disabled:opacity-50"
            >
              Confirm Reject
            </button>
          </>
        }
      >
        <p className="mb-4 text-sm text-[#6B5C4E]">
          Reject seller application for <strong className="text-[#3B2314]">{rejectTarget?.full_name}</strong>?
        </p>
        <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
          Reason (optional)
        </label>
        <textarea
          value={rejectReason}
          onChange={(e) => setRejectReason(e.target.value)}
          rows={3}
          className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-3 py-2 text-sm text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
          placeholder="Optional note for internal records…"
        />
      </Modal>
    </div>
  )
}
