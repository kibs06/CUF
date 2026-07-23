import { useMemo, useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import Badge from '../components/ui/Badge.jsx'
import { TableSkeleton, StatCardSkeleton } from '../components/ui/Skeleton.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import { formatDate, shortId } from '../lib/constants'
import { Search, Flag, AlertTriangle, X, MessageSquare, Package, Store, HelpCircle, ChevronLeft, ChevronRight } from 'lucide-react'

const PAGE_SIZE = 20

const TYPE_ICONS = { message: MessageSquare, product: Package, seller: Store, other: HelpCircle }
const TYPE_COLORS = { message: '#5C6BC0', product: '#8B5A2B', seller: '#E8A020', other: '#78909C' }

const CATEGORY_LABELS = {
  harassment: 'Harassment / abusive language', spam_scam: 'Spam or scam attempt',
  inappropriate_content: 'Inappropriate content', off_platform: 'Trying to move the deal off-platform',
  not_as_described: 'Item not as described', damaged_defective: 'Item damaged or defective',
  wrong_item: 'Wrong item received', never_received: 'Item never received',
  seller_refuses: 'Seller refuses to resolve/negotiate', buyer_misuse: 'Customer damaged/misused item before dispute',
  scam_fraud: 'Suspected scam or fraud', fake_listings: 'Fake or misleading listings',
  counterfeit: 'Counterfeit goods', repeated_violations: 'Repeated policy violations',
  harassment_outside_chat: 'Harassment outside the chat',
  app_bug: 'App bug or technical issue', payment_billing: 'Payment or billing issue',
  account_issue: 'Account issue', general_feedback: 'General complaint / feedback', other: 'Other',
}

const STATUS_OPTIONS = ['pending', 'under_review', 'resolved', 'dismissed']
const ACTION_OPTIONS = ['none', 'warning_issued', 'content_removed', 'seller_suspended', 'refund_issued', 'other']

const NOTIFICATION_TEMPLATES = {
  reviewed_action_taken: "We've reviewed your report and taken action. Thank you for helping keep our community safe.",
  reviewed_no_violation: "We've reviewed your report and didn't find a violation of our policies. Thanks for flagging it — feel free to reach out if anything else comes up.",
  needs_more_info: "We're looking into your report and may reach out if we need more details. Thanks for your patience.",
}

const categoryLabel = (key) => CATEGORY_LABELS[key] ?? key

// ── Hooks ────────────────────────────────────────────────────────

function useReports() {
  return useQuery({
    queryKey: ['admin-reports'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('reports')
        .select('*, profiles!reports_reporter_id_fkey(full_name, email, avatar_url)')
        .order('created_at', { ascending: false })
        .limit(500)
      if (error) throw error
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
      const [pending, high, underReview, resolved7d] = await Promise.all([
        supabase.from('reports').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
        supabase.from('reports').select('*', { count: 'exact', head: true }).eq('priority', 'high').in('status', ['pending', 'under_review']),
        supabase.from('reports').select('*', { count: 'exact', head: true }).eq('status', 'under_review'),
        supabase.from('reports').select('*', { count: 'exact', head: true }).eq('status', 'resolved').gte('updated_at', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()),
      ])
      return {
        pending: pending.count ?? 0,
        high_priority: high.count ?? 0,
        under_review: underReview.count ?? 0,
        resolved_7d: resolved7d.count ?? 0,
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
  const { data: counts, isLoading: countsLoading } = useReportCounts()
  const { data: reports, isLoading: reportsLoading, isError, error } = useReports()
  const updateReport = useUpdateReport()

  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [typeFilter, setTypeFilter] = useState('all')
  const [priorityFilter, setPriorityFilter] = useState('all')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [page, setPage] = useState(1)
  const [selectedReport, setSelectedReport] = useState(null)
  const [detailStatus, setDetailStatus] = useState('')
  const [detailAction, setDetailAction] = useState('none')
  const [detailNotes, setDetailNotes] = useState('')
  const [notifyMode, setNotifyMode] = useState(null)
  const [selectedTemplate, setSelectedTemplate] = useState(null)
  const [customMsg, setCustomMsg] = useState('')
  const [actionError, setActionError] = useState(null)
  const [saving, setSaving] = useState(false)

  const filtered = useMemo(() => {
    let rows = reports ?? []
    const q = search.trim().toLowerCase()
    if (q) {
      rows = rows.filter((r) =>
        String(r.id).toLowerCase().includes(q) ||
        r.profiles?.full_name?.toLowerCase().includes(q) ||
        r.category?.toLowerCase().includes(q) ||
        r.custom_details?.toLowerCase().includes(q)
      )
    }
    if (statusFilter !== 'all') rows = rows.filter((r) => r.status === statusFilter)
    if (typeFilter !== 'all') rows = rows.filter((r) => r.type === typeFilter)
    if (priorityFilter !== 'all') rows = rows.filter((r) => r.priority === priorityFilter)
    if (dateFrom) { const from = new Date(dateFrom); rows = rows.filter((r) => new Date(r.created_at) >= from) }
    if (dateTo) { const to = new Date(dateTo); to.setHours(23, 59, 59, 999); rows = rows.filter((r) => new Date(r.created_at) <= to) }
    return rows
  }, [reports, search, statusFilter, typeFilter, priorityFilter, dateFrom, dateTo])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const pageRows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const openReport = (report) => {
    setSelectedReport(report)
    setDetailStatus(report.status)
    setDetailAction(report.action_taken ?? 'none')
    setDetailNotes(report.admin_notes ?? '')
    setNotifyMode(null)
    setSelectedTemplate(null)
    setCustomMsg('')
    setActionError(null)
  }

  const handleSave = async () => {
    if (detailStatus === 'resolved' && (detailAction === 'none' || !detailAction)) {
      setActionError('Action Taken is required when resolving a report.')
      return
    }
    setActionError(null)
    setSaving(true)
    try {
      await updateReport.mutateAsync({
        id: selectedReport.id,
        updates: { status: detailStatus, action_taken: detailAction, admin_notes: detailNotes },
      })
      setSelectedReport({ ...selectedReport, status: detailStatus, action_taken: detailAction, admin_notes: detailNotes })
      showToast('Report updated')
    } catch (err) {
      showToast(err.message ?? 'Update failed', 'error')
    } finally {
      setSaving(false)
    }
  }

  const handleNotify = async () => {
    let msg = ''
    if (notifyMode === 'template' && selectedTemplate) msg = NOTIFICATION_TEMPLATES[selectedTemplate]
    else if (notifyMode === 'custom' && customMsg.trim()) msg = customMsg.trim()
    else return
    setSaving(true)
    try {
      await updateReport.mutateAsync({
        id: selectedReport.id,
        updates: { reporter_notified: true, reporter_notification_text: msg },
      })
      setSelectedReport({ ...selectedReport, reporter_notified: true, reporter_notification_text: msg })
      setNotifyMode(null)
      setCustomMsg('')
      showToast('Reporter notified')
    } catch (err) {
      showToast(err.message ?? 'Notify failed', 'error')
    } finally {
      setSaving(false)
    }
  }

  const handleStatClick = (filterType, filterValue) => {
    if (filterType === 'status') { setStatusFilter(filterValue); setPage(1) }
    else if (filterType === 'priority') { setPriorityFilter(filterValue); setPage(1) }
  }

  return (
    <div className="space-y-4">
      {/* Stat Cards */}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {countsLoading ? (
          Array.from({ length: 4 }).map((_, i) => <StatCardSkeleton key={i} />)
        ) : (
          <>
            <StatCard icon="⏳" label="Pending" value={counts?.pending ?? 0} iconBg="rgba(232,160,32,0.1)" iconColor="#E8A020" onClick={() => handleStatClick('status', 'pending')} active={statusFilter === 'pending'} />
            <StatCard icon="🔴" label="High Priority" value={counts?.high_priority ?? 0} highlight iconBg="rgba(214,69,69,0.1)" iconColor="#D64545" onClick={() => handleStatClick('priority', 'high')} active={priorityFilter === 'high'} />
            <StatCard icon="🔍" label="Under Review" value={counts?.under_review ?? 0} iconBg="rgba(92,107,192,0.1)" iconColor="#5C6BC0" onClick={() => handleStatClick('status', 'under_review')} active={statusFilter === 'under_review'} />
            <StatCard icon="✅" label="Resolved (7d)" value={counts?.resolved_7d ?? 0} iconBg="rgba(78,205,196,0.1)" iconColor="#4ECDC4" onClick={() => handleStatClick('status', 'resolved')} active={statusFilter === 'resolved'} />
          </>
        )}
      </div>

      {/* Filter Bar */}
      <div className="flex flex-wrap gap-3">
        <div className="relative flex-1 min-w-[200px]">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#6B5C4E]" />
          <input type="search" placeholder="Search reporter, target, or report ID…" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }}
            className="w-full rounded-xl border border-[#D9D0C7] bg-white py-2.5 pl-9 pr-4 text-sm text-[#3B2314] placeholder-[#6B5C4E] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20" />
        </div>
        <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1) }}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]">
          <option value="all">All statuses</option>
          {STATUS_OPTIONS.map((s) => <option key={s} value={s}>{s.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())}</option>)}
        </select>
        <select value={typeFilter} onChange={(e) => { setTypeFilter(e.target.value); setPage(1) }}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]">
          <option value="all">All types</option>
          {['message', 'product', 'seller', 'other'].map((t) => <option key={t} value={t}>{t.charAt(0).toUpperCase() + t.slice(1)}</option>)}
        </select>
        <select value={priorityFilter} onChange={(e) => { setPriorityFilter(e.target.value); setPage(1) }}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]">
          <option value="all">All priorities</option>
          <option value="high">High</option>
          <option value="normal">Normal</option>
        </select>
        <input type="date" value={dateFrom} onChange={(e) => { setDateFrom(e.target.value); setPage(1) }}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]" />
        <input type="date" value={dateTo} onChange={(e) => { setDateTo(e.target.value); setPage(1) }}
          className="rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]" />
      </div>

      {/* Table */}
      {reportsLoading && <TableSkeleton cols={6} rows={8} />}
      {isError && (
        <div className="rounded-2xl border border-[#D9D0C7] bg-white p-8 text-center">
          <p className="text-sm text-[#D64545]">{error.message}</p>
        </div>
      )}

      {!reportsLoading && !isError && (
        <>
          <div className="overflow-x-auto rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
            <table className="min-w-full text-left text-sm">
              <thead className="bg-[#F5F0EB]">
                <tr>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Priority</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Type</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Reporter</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Target</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Status</th>
                  <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#F5F0EB]">
                {pageRows.length === 0 ? (
                  <tr><td colSpan={6} className="px-6 py-12 text-center text-[#6B5C4E]">No reports found</td></tr>
                ) : pageRows.map((row) => {
                  const TypeIcon = TYPE_ICONS[row.type] || Flag
                  const typeColor = TYPE_COLORS[row.type] || '#78909C'
                  const target = row.category === 'other' && row.custom_details
                    ? `Other: "${row.custom_details.length > 40 ? row.custom_details.slice(0, 40) + '...' : row.custom_details}"`
                    : categoryLabel(row.category)
                  return (
                    <tr key={row.id} onClick={() => openReport(row)} className="cursor-pointer transition-colors hover:bg-[#FBF8F5]">
                      <td className="px-6 py-4">
                        {row.priority === 'high' && (
                          <span className="inline-flex items-center gap-1 rounded-full bg-red-50 px-2.5 py-0.5 text-xs font-semibold text-[#D64545]">
                            <AlertTriangle size={12} /> HIGH
                          </span>
                        )}
                      </td>
                      <td className="px-6 py-4">
                        <span className="inline-flex items-center gap-1.5 text-sm" style={{ color: typeColor }}>
                          <TypeIcon size={14} /> {row.type}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-[#3B2314]">{row.profiles?.full_name ?? '—'}</td>
                      <td className="px-6 py-4 text-[#6B5C4E] max-w-[200px] truncate" title={target}>{target}</td>
                      <td className="px-6 py-4"><Badge label={row.status?.replace(/_/g, ' ')} variant={row.status} /></td>
                      <td className="px-6 py-4 text-[#6B5C4E]">{formatDate(row.created_at)}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>

          <div className="flex items-center justify-between text-sm">
            <span className="text-[#6B5C4E]">{filtered.length} reports · Page {page} of {totalPages}</span>
            <div className="flex gap-2">
              <button type="button" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}
                className="flex items-center gap-1 rounded-xl border border-[#D9D0C7] px-3 py-1 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] disabled:opacity-40">
                <ChevronLeft size={14} /> Previous
              </button>
              <button type="button" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}
                className="flex items-center gap-1 rounded-xl border border-[#D9D0C7] px-3 py-1 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] disabled:opacity-40">
                Next <ChevronRight size={14} />
              </button>
            </div>
          </div>
        </>
      )}

      {/* Slide-over Detail Panel */}
      {selectedReport && (
        <div className="fixed inset-0 z-50 flex justify-end" onClick={() => setSelectedReport(null)}>
          <div className="absolute inset-0 bg-black/30" />
          <div className="relative h-full w-full max-w-lg overflow-y-auto bg-white shadow-2xl" onClick={(e) => e.stopPropagation()}>
            {/* Panel Header */}
            <div className="sticky top-0 z-10 flex items-center justify-between border-b border-[#F5F0EB] bg-white px-6 py-4">
              <div>
                <p className="text-xs text-[#6B5C4E]">#{shortId(selectedReport.id)} · {formatDate(selectedReport.created_at)}</p>
                <div className="mt-1 flex items-center gap-2">
                  {selectedReport.priority === 'high' && <span className="inline-flex items-center gap-1 rounded-full bg-red-50 px-2 py-0.5 text-[10px] font-bold text-[#D64545]">HIGH</span>}
                  <Badge label={selectedReport.type} variant={selectedReport.type} />
                  <span className="text-xs text-[#6B5C4E]">{categoryLabel(selectedReport.category)}</span>
                </div>
              </div>
              <button onClick={() => setSelectedReport(null)} className="rounded-lg p-2 hover:bg-[#F5F0EB]"><X size={20} className="text-[#6B5C4E]" /></button>
            </div>

            <div className="space-y-5 px-6 py-5">
              {/* Reporter */}
              <div className="rounded-xl bg-[#FBF8F5] p-4">
                <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Reporter</p>
                <p className="text-sm font-semibold text-[#3B2314]">{selectedReport.profiles?.full_name ?? 'Unknown'}</p>
                <p className="text-xs text-[#6B5C4E]">{selectedReport.reporter_role} · {selectedReport.profiles?.email}</p>
              </div>

              {/* Custom details for 'other' */}
              {selectedReport.category === 'other' && selectedReport.custom_details && (
                <div className="rounded-xl border border-[#E8A020] bg-[#FFF8E7] p-4">
                  <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#C47D00]">Reporter's Description</p>
                  <p className="whitespace-pre-wrap text-sm text-[#3B2314]">{selectedReport.custom_details}</p>
                </div>
              )}

              {/* Status */}
              <div>
                <label className="mb-1 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Status</label>
                <select value={detailStatus} onChange={(e) => { setDetailStatus(e.target.value); setActionError(null) }}
                  className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]">
                  {STATUS_OPTIONS.map((s) => <option key={s} value={s}>{s.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())}</option>)}
                </select>
              </div>

              {/* Action Taken */}
              <div>
                <label className="mb-1 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                  Action Taken {detailStatus === 'resolved' && <span className="text-[#D64545]">*</span>}
                </label>
                <select value={detailAction} onChange={(e) => { setDetailAction(e.target.value); setActionError(null) }}
                  className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]">
                  {ACTION_OPTIONS.map((a) => <option key={a} value={a}>{a.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())}</option>)}
                </select>
                {actionError && <p className="mt-1 text-xs text-[#D64545]">{actionError}</p>}
              </div>

              {/* Admin Notes */}
              <div>
                <label className="mb-1 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Admin Notes</label>
                <textarea value={detailNotes} onChange={(e) => setDetailNotes(e.target.value)} rows={3} placeholder="Internal notes (not visible to reporter)"
                  className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]" />
              </div>

              {/* Notify Reporter */}
              <div className="rounded-xl border border-[#F5F0EB] p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-semibold text-[#3B2314]">Notify Reporter</p>
                    <p className="text-xs text-[#6B5C4E]">
                      {selectedReport.reporter_notified
                        ? `Already notified`
                        : 'Send an update to the reporter'}
                    </p>
                  </div>
                  {!notifyMode && (
                    <button onClick={() => setNotifyMode('template')} className="rounded-xl bg-[#8B5A2B] px-3 py-1.5 text-xs font-semibold text-white hover:bg-[#6B4423]">Notify</button>
                  )}
                </div>
                {notifyMode && (
                  <div className="mt-3 space-y-2">
                    {Object.entries(NOTIFICATION_TEMPLATES).map(([key, tpl]) => (
                      <button key={key} onClick={() => { setSelectedTemplate(key); setNotifyMode('template') }}
                        className={`w-full rounded-xl border px-3 py-2 text-left text-xs hover:bg-[#FBF8F5] ${selectedTemplate === key ? 'border-[#8B5A2B] bg-[#FBF8F5]' : 'border-[#D9D0C7]'}`}>
                        {tpl}
                      </button>
                    ))}
                    <button onClick={() => setNotifyMode('custom')} className="w-full rounded-xl border border-dashed border-[#D9D0C7] px-3 py-2 text-left text-xs text-[#6B5C4E] hover:bg-[#FBF8F5]">
                      ✏️ Write custom message
                    </button>
                    {notifyMode === 'custom' && (
                      <textarea value={customMsg} onChange={(e) => setCustomMsg(e.target.value)} rows={2} placeholder="Type a custom message..."
                        className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]" />
                    )}
                    <div className="flex gap-2">
                      <button onClick={() => { setNotifyMode(null); setSelectedTemplate(null); setCustomMsg('') }}
                        className="rounded-xl border border-[#D9D0C7] px-3 py-1.5 text-xs font-semibold text-[#6B5C4E]">Cancel</button>
                      <button onClick={handleNotify} disabled={saving || (notifyMode === 'template' ? !selectedTemplate : !customMsg.trim())}
                        className="rounded-xl bg-[#8B5A2B] px-3 py-1.5 text-xs font-semibold text-white hover:bg-[#6B4423] disabled:opacity-50">
                        {saving ? 'Sending...' : 'Send'}
                      </button>
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* Sticky Footer */}
            <div className="sticky bottom-0 border-t border-[#F5F0EB] bg-white px-6 py-4">
              <button onClick={handleSave} disabled={saving}
                className="w-full rounded-xl bg-[#8B5A2B] px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-[#6B4423] disabled:opacity-50">
                {saving ? 'Saving...' : 'Save Changes'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// ── Stat Card ────────────────────────────────────────────────────

function StatCard({ icon, label, value, highlight, iconBg, iconColor, onClick, active }) {
  return (
    <button type="button" onClick={onClick}
      className={`rounded-2xl border bg-white p-5 text-left shadow-sm transition-all hover:shadow-md ${active ? 'ring-2 ring-[#8B5A2B]/40 border-[#8B5A2B]' : highlight ? 'border-[#D64545]/30' : 'border-[#D9D0C7]'}`}>
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm text-[#6B5C4E]">{label}</p>
          <p className={`mt-1 text-2xl font-bold ${highlight ? 'text-[#D64545]' : 'text-[#3B2314]'}`}>{value}</p>
        </div>
        <div className="flex h-12 w-12 items-center justify-center rounded-xl text-xl" style={{ backgroundColor: iconBg }}>
          {icon}
        </div>
      </div>
    </button>
  )
}
