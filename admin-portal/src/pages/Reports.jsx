import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import Badge from '../components/ui/Badge.jsx'
import AvatarInitials from '../components/ui/AvatarInitials.jsx'
import { StatCardSkeleton, TableSkeleton } from '../components/ui/Skeleton.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import { formatDate, shortId } from '../lib/constants'
import { Flag, AlertTriangle, CheckCircle, XCircle, Eye, MessageSquare, Package, Store, HelpCircle } from 'lucide-react'

// ── Machine key → display label mappings ──────────────────────────

const TYPE_ICONS = {
  message: MessageSquare,
  product: Package,
  seller: Store,
  other: HelpCircle,
}

const TYPE_COLORS = {
  message: '#5C6BC0',
  product: '#8B5A2B',
  seller: '#E8A020',
  other: '#78909C',
}

const CATEGORY_LABELS = {
  // Message
  harassment: 'Harassment / abusive language',
  spam_scam: 'Spam or scam attempt',
  inappropriate_content: 'Inappropriate content',
  off_platform: 'Trying to move the deal off-platform',
  // Product
  not_as_described: 'Item not as described',
  damaged_defective: 'Item damaged or defective',
  wrong_item: 'Wrong item received',
  never_received: 'Item never received',
  seller_refuses: 'Seller refuses to resolve/negotiate',
  buyer_misuse: 'Customer damaged/misused item before dispute',
  // Seller
  scam_fraud: 'Suspected scam or fraud',
  fake_listings: 'Fake or misleading listings',
  counterfeit: 'Counterfeit goods',
  repeated_violations: 'Repeated policy violations',
  harassment_outside_chat: 'Harassment outside the chat',
  // Other
  app_bug: 'App bug or technical issue',
  payment_billing: 'Payment or billing issue',
  account_issue: 'Account issue',
  general_feedback: 'General complaint / feedback',
  other: 'Other',
}

const STATUS_OPTIONS = ['pending', 'under_review', 'resolved', 'dismissed']
const ACTION_OPTIONS = ['none', 'warning_issued', 'content_removed', 'seller_suspended', 'refund_issued', 'other']

const NOTIFICATION_TEMPLATES = {
  reviewed_action_taken: "We've reviewed your report and taken action. Thank you for helping keep our community safe.",
  reviewed_no_violation: "We've reviewed your report and didn't find a violation of our policies. Thanks for flagging it — feel free to reach out if anything else comes up.",
  needs_more_info: "We're looking into your report and may reach out if we need more details. Thanks for your patience.",
}

function categoryLabel(key) {
  return CATEGORY_LABELS[key] ?? key
}

function categoryDisplay(report) {
  const label = categoryLabel(report.category)
  if (report.category === 'other' && report.custom_details) {
    const truncated = report.custom_details.length > 50
      ? report.custom_details.slice(0, 50) + '...'
      : report.custom_details
    return `Other: "${truncated}"`
  }
  return label
}

// ── Hooks ────────────────────────────────────────────────────────

function useReports(filters) {
  return useQuery({
    queryKey: ['admin-reports', filters],
    queryFn: async () => {
      let query = supabase
        .from('reports')
        .select('*, profiles!reports_reporter_id_fkey(full_name, email, avatar_url)')
        .order('created_at', { ascending: false })

      if (filters.type !== 'all') query = query.eq('type', filters.type)
      if (filters.status !== 'all') query = query.eq('status', filters.status)
      if (filters.priority !== 'all') query = query.eq('priority', filters.priority)

      const { data, error } = await query.limit(100)
      if (error) throw error

      // Client-side sort: high priority first, then newest first
      return (data ?? []).sort((a, b) => {
        if (a.priority === 'high' && b.priority !== 'high') return -1
        if (a.priority !== 'high' && b.priority === 'high') return 1
        return new Date(b.created_at) - new Date(a.created_at)
      })
    },
  })
}

function useReportCounts() {
  return useQuery({
    queryKey: ['report-counts'],
    queryFn: async () => {
      const [total, pending, high, resolved, underReview, dismissed] = await Promise.all([
        supabase.from('reports').select('*', { count: 'exact', head: true }),
        supabase.from('reports').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
        supabase.from('reports').select('*', { count: 'exact', head: true }).eq('priority', 'high').in('status', ['pending', 'under_review']),
        supabase.from('reports').select('*', { count: 'exact', head: true }).eq('status', 'resolved'),
        supabase.from('reports').select('*', { count: 'exact', head: true }).eq('status', 'under_review'),
        supabase.from('reports').select('*', { count: 'exact', head: true }).eq('status', 'dismissed'),
      ])
      return {
        total: total.count ?? 0,
        pending: pending.count ?? 0,
        high_priority: high.count ?? 0,
        resolved: resolved.count ?? 0,
        under_review: underReview.count ?? 0,
        dismissed: dismissed.count ?? 0,
      }
    },
  })
}

function useUpdateReport() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, updates }) => {
      const { error } = await supabase.from('reports').update({ ...updates, updated_at: new Date().toISOString() }).eq('id', id)
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['admin-reports'] })
      qc.invalidateQueries({ queryKey: ['report-counts'] })
    },
  })
}

// ── Main Page ────────────────────────────────────────────────────

export default function Reports() {
  const { showToast } = useToast()
  const [filters, setFilters] = useState({ type: 'all', status: 'all', priority: 'all' })
  const [selectedReport, setSelectedReport] = useState(null)
  const { data: counts, isLoading: countsLoading } = useReportCounts()
  const { data: reports, isLoading: reportsLoading } = useReports(filters)
  const updateReport = useUpdateReport()

  return (
    <div className="space-y-6">
      {/* Stats */}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {countsLoading ? (
          Array.from({ length: 4 }).map((_, i) => <StatCardSkeleton key={i} />)
        ) : (
          <>
            <StatCard icon="📋" label="Total Reports" value={counts?.total ?? 0} iconBg="rgba(92,107,192,0.1)" iconColor="#5C6BC0" />
            <StatCard icon="⏳" label="Pending Review" value={counts?.pending ?? 0} highlight={(counts?.pending ?? 0) > 0} iconBg="rgba(232,160,32,0.1)" iconColor="#E8A020" />
            <StatCard icon="🔴" label="High Priority Open" value={counts?.high_priority ?? 0} highlight={(counts?.high_priority ?? 0) > 0} iconBg="rgba(214,69,69,0.1)" iconColor="#D64545" />
            <StatCard icon="✅" label="Resolved" value={counts?.resolved ?? 0} iconBg="rgba(78,205,196,0.1)" iconColor="#4ECDC4" />
          </>
        )}
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3">
        <FilterSelect label="Type" value={filters.type} onChange={(v) => setFilters(f => ({ ...f, type: v }))} options={['all', 'message', 'product', 'seller', 'other']} />
        <FilterSelect label="Status" value={filters.status} onChange={(v) => setFilters(f => ({ ...f, status: v }))} options={['all', ...STATUS_OPTIONS]} />
        <FilterSelect label="Priority" value={filters.priority} onChange={(v) => setFilters(f => ({ ...f, priority: v }))} options={['all', 'high', 'normal']} />
      </div>

      {/* Table */}
      <section className="rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
        <div className="border-b border-[#F5F0EB] px-6 py-4">
          <h2 className="font-display text-lg font-bold text-[#3B2314]">Reports Queue</h2>
        </div>
        <div className="p-4">
          {reportsLoading ? (
            <TableSkeleton cols={6} rows={5} />
          ) : reports?.length > 0 ? (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="bg-[#F5F0EB]">
                  <tr>
                    <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Priority</th>
                    <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Type</th>
                    <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Category</th>
                    <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Reporter</th>
                    <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Status</th>
                    <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Date</th>
                    <th className="px-4 py-3"></th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[#F5F0EB]">
                  {reports.map((report) => (
                    <ReportRow key={report.id} report={report} onClick={() => setSelectedReport(report)} />
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center py-12 text-[#6B5C4E]">
              <Flag size={32} className="mb-2 opacity-40" />
              <p className="text-sm">No reports found</p>
            </div>
          )}
        </div>
      </section>

      {/* Detail Modal */}
      {selectedReport && (
        <ReportDetailModal
          report={selectedReport}
          onClose={() => setSelectedReport(null)}
          onUpdate={async (updates) => {
            await updateReport.mutateAsync({ id: selectedReport.id, updates })
            setSelectedReport({ ...selectedReport, ...updates })
            showToast('Report updated')
          }}
          onNotify={async (templateKey, customText) => {
            await updateReport.mutateAsync({
              id: selectedReport.id,
              updates: {
                reporter_notified: true,
                reporter_notification_text: customText ?? NOTIFICATION_TEMPLATES[templateKey],
              },
            })
            setSelectedReport({
              ...selectedReport,
              reporter_notified: true,
              reporter_notification_text: customText ?? NOTIFICATION_TEMPLATES[templateKey],
            })
            showToast('Reporter notified')
          }}
        />
      )}
    </div>
  )
}

// ── Sub-components ───────────────────────────────────────────────

function StatCard({ icon, label, value, highlight, iconBg }) {
  return (
    <div className={`rounded-2xl border bg-white p-5 shadow-sm transition-shadow hover:shadow-md ${highlight ? 'border-[#E8A020]' : 'border-[#D9D0C7]'}`}>
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm text-[#6B5C4E]">{label}</p>
          <p className="mt-1 text-2xl font-bold text-[#3B2314]">{value}</p>
        </div>
        <div className="flex h-12 w-12 items-center justify-center rounded-xl text-xl" style={{ backgroundColor: iconBg }}>
          {icon}
        </div>
      </div>
    </div>
  )
}

function FilterSelect({ label, value, onChange, options }) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="rounded-lg border border-[#D9D0C7] bg-white px-3 py-2 text-sm text-[#3B2314] focus:border-[#8B5A2B] focus:outline-none"
    >
      {options.map((opt) => (
        <option key={opt} value={opt}>{opt === 'all' ? `All ${label}s` : opt.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())}</option>
      ))}
    </select>
  )
}

function ReportRow({ report, onClick }) {
  const TypeIcon = TYPE_ICONS[report.type] || Flag
  const typeColor = TYPE_COLORS[report.type] || '#78909C'
  const isHigh = report.priority === 'high'

  return (
    <tr className="transition-colors hover:bg-[#FBF8F5] cursor-pointer" onClick={onClick}>
      <td className="px-4 py-3">
        {isHigh ? (
          <span className="inline-flex items-center gap-1 rounded-full bg-red-50 px-2.5 py-0.5 text-xs font-semibold text-[#D64545]">
            <AlertTriangle size={12} /> HIGH
          </span>
        ) : null}
      </td>
      <td className="px-4 py-3">
        <span className="inline-flex items-center gap-1.5 text-sm" style={{ color: typeColor }}>
          <TypeIcon size={14} />
          {report.type}
        </span>
      </td>
      <td className="px-4 py-3 text-sm text-[#6B5C4E] max-w-[200px] truncate" title={report.category === 'other' ? report.custom_details : categoryLabel(report.category)}>
        {categoryDisplay(report)}
      </td>
      <td className="px-4 py-3">
        <div className="flex items-center gap-2">
          <AvatarInitials name={report.profiles?.full_name} email={report.profiles?.email} size={28} />
          <span className="text-sm">{report.profiles?.full_name ?? '—'}</span>
        </div>
      </td>
      <td className="px-4 py-3"><Badge label={report.status?.replace(/_/g, ' ')} variant={report.status} /></td>
      <td className="px-4 py-3 text-xs text-[#6B5C4E]">{formatDate(report.created_at)}</td>
      <td className="px-4 py-3">
        <button className="rounded-lg p-1.5 text-[#6B5C4E] hover:bg-[#F5F0EB]" onClick={(e) => { e.stopPropagation(); onClick() }}>
          <Eye size={16} />
        </button>
      </td>
    </tr>
  )
}

function ReportDetailModal({ report, onClose, onUpdate, onNotify }) {
  const [status, setStatus] = useState(report.status)
  const [actionTaken, setActionTaken] = useState(report.action_taken ?? 'none')
  const [adminNotes, setAdminNotes] = useState(report.admin_notes ?? '')
  const [notifyMode, setNotifyMode] = useState(null) // null | 'template' | 'custom'
  const [selectedTemplate, setSelectedTemplate] = useState(null)
  const [customMsg, setCustomMsg] = useState('')
  const [actionError, setActionError] = useState(null)
  const TypeIcon = TYPE_ICONS[report.type] || Flag

  const handleSave = () => {
    if (status === 'resolved' && (actionTaken === 'none' || !actionTaken)) {
      setActionError('Action Taken is required when resolving a report.')
      return
    }
    setActionError(null)
    onUpdate({ status, action_taken: actionTaken, admin_notes: adminNotes })
  }

  const handleNotify = () => {
    if (notifyMode === 'template' && selectedTemplate) {
      onNotify(selectedTemplate, null)
      setNotifyMode(null)
    } else if (notifyMode === 'custom' && customMsg.trim()) {
      onNotify(null, customMsg.trim())
      setNotifyMode(null)
      setCustomMsg('')
    }
  }

  const isOther = report.category === 'other'

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={onClose}>
      <div className="w-full max-w-lg rounded-2xl bg-white shadow-xl" onClick={(e) => e.stopPropagation()}>
        {/* Header */}
        <div className="flex items-center justify-between border-b border-[#F5F0EB] px-6 py-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl" style={{ backgroundColor: `${TYPE_COLORS[report.type]}15` }}>
              <TypeIcon size={20} style={{ color: TYPE_COLORS[report.type] }} />
            </div>
            <div>
              <h3 className="font-display text-lg font-bold text-[#3B2314]">Report Detail</h3>
              <p className="text-xs text-[#6B5C4E]">{report.category ? `#${shortId(report.id)} · ${categoryLabel(report.category)}` : ''}</p>
            </div>
          </div>
          <button onClick={onClose} className="rounded-lg p-2 hover:bg-[#F5F0EB]">
            <XCircle size={20} className="text-[#6B5C4E]" />
          </button>
        </div>

        {/* Body */}
        <div className="max-h-[60vh] space-y-4 overflow-y-auto px-6 py-4">
          {/* Reporter info */}
          <div className="flex items-center gap-3 rounded-xl bg-[#FBF8F5] p-3">
            <AvatarInitials name={report.profiles?.full_name} email={report.profiles?.email} size={36} />
            <div>
              <p className="text-sm font-semibold text-[#3B2314]">{report.profiles?.full_name ?? 'Unknown'}</p>
              <p className="text-xs text-[#6B5C4E]">{report.reporter_role} · {formatDate(report.created_at)}</p>
            </div>
            {report.priority === 'high' && (
              <span className="ml-auto inline-flex items-center gap-1 rounded-full bg-red-50 px-2.5 py-0.5 text-xs font-semibold text-[#D64545]">
                <AlertTriangle size={12} /> HIGH
              </span>
            )}
          </div>

          {/* Custom details (for 'other' category) */}
          {isOther && report.custom_details && (
            <div className="rounded-xl border border-[#E8A020] bg-[#FFF8E7] p-4">
              <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#C47D00]">Reporter's Description</p>
              <p className="text-sm text-[#3B2314] whitespace-pre-wrap">{report.custom_details}</p>
            </div>
          )}

          {/* Status control */}
          <div>
            <label className="mb-1 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Status</label>
            <select value={status} onChange={(e) => { setStatus(e.target.value); setActionError(null) }} className="w-full rounded-lg border border-[#D9D0C7] px-3 py-2 text-sm focus:border-[#8B5A2B] focus:outline-none">
              {STATUS_OPTIONS.map((s) => <option key={s} value={s}>{s.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())}</option>)}
            </select>
          </div>

          {/* Action taken */}
          <div>
            <label className="mb-1 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              Action Taken {status === 'resolved' && <span className="text-[#D64545]">*</span>}
            </label>
            <select value={actionTaken} onChange={(e) => { setActionTaken(e.target.value); setActionError(null) }} className="w-full rounded-lg border border-[#D9D0C7] px-3 py-2 text-sm focus:border-[#8B5A2B] focus:outline-none">
              {ACTION_OPTIONS.map((a) => <option key={a} value={a}>{a.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())}</option>)}
            </select>
            {actionError && <p className="mt-1 text-xs text-[#D64545]">{actionError}</p>}
          </div>

          {/* Admin notes */}
          <div>
            <label className="mb-1 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Admin Notes</label>
            <textarea
              value={adminNotes}
              onChange={(e) => setAdminNotes(e.target.value)}
              rows={3}
              placeholder="Internal notes (not visible to reporter)"
              className="w-full rounded-lg border border-[#D9D0C7] px-3 py-2 text-sm focus:border-[#8B5A2B] focus:outline-none"
            />
          </div>

          {/* Notify reporter */}
          <div className="rounded-xl border border-[#F5F0EB] p-3">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-semibold text-[#3B2314]">Notify Reporter</p>
                <p className="text-xs text-[#6B5C4E]">
                  {report.reporter_notified
                    ? `Already notified — "${(report.reporter_notification_text ?? '').slice(0, 60)}${(report.reporter_notification_text ?? '').length > 60 ? '...' : ''}"`
                    : 'Send an update to the reporter'}
                </p>
              </div>
              {!notifyMode && (
                <button onClick={() => setNotifyMode('template')} className="rounded-lg bg-[#8B5A2B] px-3 py-1.5 text-xs font-semibold text-white hover:bg-[#6B4423]">
                  Notify
                </button>
              )}
            </div>
            {notifyMode && (
              <div className="mt-3 space-y-2">
                {Object.entries(NOTIFICATION_TEMPLATES).map(([key, tpl]) => (
                  <button
                    key={key}
                    onClick={() => { setSelectedTemplate(key); setNotifyMode('template') }}
                    className={`w-full rounded-lg border px-3 py-2 text-left text-xs hover:bg-[#FBF8F5] ${selectedTemplate === key ? 'border-[#8B5A2B] bg-[#FBF8F5]' : 'border-[#D9D0C7]'}`}
                  >
                    {tpl}
                  </button>
                ))}
                <button onClick={() => setNotifyMode('custom')} className="w-full rounded-lg border border-dashed border-[#D9D0C7] px-3 py-2 text-left text-xs text-[#6B5C4E] hover:bg-[#FBF8F5]">
                  ✏️ Write custom message
                </button>
                {notifyMode === 'custom' && (
                  <textarea
                    value={customMsg}
                    onChange={(e) => setCustomMsg(e.target.value)}
                    rows={2}
                    placeholder="Type a custom message..."
                    className="w-full rounded-lg border border-[#D9D0C7] px-3 py-2 text-sm focus:border-[#8B5A2B] focus:outline-none"
                  />
                )}
                <div className="flex gap-2">
                  <button onClick={() => { setNotifyMode(null); setSelectedTemplate(null); setCustomMsg('') }} className="rounded-lg border border-[#D9D0C7] px-3 py-1.5 text-xs font-semibold text-[#6B5C4E]">Cancel</button>
                  <button
                    onClick={handleNotify}
                    disabled={notifyMode === 'template' ? !selectedTemplate : !customMsg.trim()}
                    className="rounded-lg bg-[#8B5A2B] px-3 py-1.5 text-xs font-semibold text-white hover:bg-[#6B4423] disabled:opacity-50"
                  >
                    Send
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="flex justify-end gap-2 border-t border-[#F5F0EB] px-6 py-4">
          <button onClick={onClose} className="rounded-lg border border-[#D9D0C7] px-4 py-2 text-sm font-semibold text-[#6B5C4E] hover:bg-[#F5F0EB]">Cancel</button>
          <button onClick={handleSave} className="rounded-lg bg-[#8B5A2B] px-4 py-2 text-sm font-semibold text-white hover:bg-[#6B4423]">Save Changes</button>
        </div>
      </div>
    </div>
  )
}
