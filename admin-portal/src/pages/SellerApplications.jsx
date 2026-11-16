import { useMemo, useState } from 'react'
import { Eye } from 'lucide-react'
import Badge from '../components/ui/Badge.jsx'
import AvatarInitials from '../components/ui/AvatarInitials.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import Modal from '../components/ui/Modal.jsx'
import { TableSkeleton } from '../components/ui/Skeleton.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import ApplicationDetailModal from '../components/seller-applications/ApplicationDetailModal.jsx'
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
  const [reviewTarget, setReviewTarget] = useState(null)
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
      setReviewTarget(null)
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
      setReviewTarget(null)
    } catch (err) {
      showToast(err.message ?? 'Rejection failed', 'error')
    } finally {
      setLoadingId(null)
    }
  }

  return (
    <div className="space-y-4">
      {/* Pill tabs */}
      <div className="flex gap-2">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setTab(t.key)}
            className={`rounded-xl px-4 py-2 text-sm font-medium transition-all ${
              tab === t.key
                ? 'bg-secondary text-white'
                : 'border border-border bg-white text-muted hover:bg-canvas'
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
        <div className="rounded-xl border border-border bg-white p-8 text-center text-muted">
          <p className="text-sm text-error">{error.message}</p>
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
              className="admin-3d-listcard admin-list-item admin-list-card flex items-center justify-between rounded-xl border border-border bg-white p-4"
            >
              <div className="flex items-center gap-3">
                <AvatarInitials name={row.full_name} email={row.email} />
                <div>
                  <p className="text-sm font-semibold text-ink">{row.full_name}</p>
                  <p className="text-xs text-muted">{row.email}</p>
                  <p className="text-xs text-muted mt-0.5">
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
                      onClick={() => setReviewTarget(row)}
                      className="inline-flex items-center gap-1.5 rounded-lg border border-[#8B5A2B] px-3 py-1.5 text-xs font-semibold text-primary transition-colors hover:bg-secondary/10"
                    >
                      <Eye size={13} />
                      Review
                    </button>
                    <button
                      type="button"
                      disabled={loadingId === row.id}
                      onClick={() => handleApprove(row.id)}
                      className="rounded-lg bg-accent px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-accent/90 disabled:opacity-50"
                    >
                      {loadingId === row.id && approve.isPending ? '…' : 'Approve'}
                    </button>
                    <button
                      type="button"
                      disabled={loadingId === row.id}
                      onClick={() => setRejectTarget(row)}
                      className="rounded-lg border border-[#D64545] px-3 py-1.5 text-xs font-semibold text-error transition-colors hover:bg-red-50 disabled:opacity-50"
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

      {/* Full application review modal */}
      <ApplicationDetailModal
        application={reviewTarget}
        onClose={() => setReviewTarget(null)}
        onApprove={handleApprove}
        onReject={setRejectTarget}
        approving={!!reviewTarget && loadingId === reviewTarget.id}
        rejecting={!!reviewTarget && loadingId === reviewTarget.id}
      />

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
              className="rounded-xl border border-border px-4 py-2 text-sm text-muted hover:bg-canvas"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleReject}
              disabled={loadingId === rejectTarget?.id}
              className="rounded-xl border border-[#D64545] px-4 py-2 text-sm font-semibold text-error transition-colors hover:bg-red-50 disabled:opacity-50"
            >
              Confirm Reject
            </button>
          </>
        }
      >
        <p className="mb-4 text-sm text-muted">
          Reject seller application for <strong className="text-ink">{rejectTarget?.full_name}</strong>?
        </p>
        <label className="mb-1.5 block text-[12px] font-medium text-muted">
          Reason (optional)
        </label>
        <textarea
          value={rejectReason}
          onChange={(e) => setRejectReason(e.target.value)}
          rows={3}
          className="w-full rounded-xl border border-border bg-canvas px-3 py-2 text-sm text-ink outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
          placeholder="Optional note for internal records…"
        />
      </Modal>
    </div>
  )
}
