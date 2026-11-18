import { useMemo, useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import Badge from '../components/ui/Badge.jsx'
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
const OPEN_STATUSES = ['pending', 'under_review']
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
    if (statusFilter === 'open') rows = rows.filter((r) => OPEN_STATUSES.includes(r.status))
    else if (statusFilter !== 'all') rows = rows.filter((r) => r.status === statusFilter)
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

  const highView = priorityFilter === 'high' && statusFilter === 'open'
  const hasFilters =
    !!search || statusFilter !== 'all' || typeFilter !== 'all' || priorityFilter !== 'all' || !!dateFrom || !!dateTo

  const showStatus = (status) => {
    setStatusFilter((current) => (current === status ? 'all' : status))
    setPriorityFilter('all')
    setPage(1)
  }

  const showHighPriority = () => {
    if (highView) {
      setPriorityFilter('all')
      setStatusFilter('all')
    } else {
      setPriorityFilter('high')
      setStatusFilter('open')
    }
    setPage(1)
  }

  const clearFilters = () => {
    setSearch('')
    setStatusFilter('all')
    setTypeFilter('all')
    setPriorityFilter('all')
    setDateFrom('')
    setDateTo('')
    setPage(1)
  }

  return (
    <div className="space-y-4">
      {/* Queue summary */}
      <section
        aria-label="Report queue"
        className="grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-border bg-border lg:grid-cols-4"
      >
        <TriageStat
          label="Pending"
          value={counts?.pending ?? 0}
          caption="Awaiting first review"
          onClick={() => showStatus('pending')}
          active={statusFilter === 'pending'}
          loading={countsLoading}
        />
        <TriageStat
          label="High priority"
          value={counts?.high_priority ?? 0}
          caption={
            counts?.high_priority > 0 ? 'Open and needs attention' : 'No open high-priority reports'
          }
          onClick={showHighPriority}
          active={highView}
          alert={counts?.high_priority > 0}
          loading={countsLoading}
        />
        <TriageStat
          label="Under review"
          value={counts?.under_review ?? 0}
          caption="Being investigated"
          onClick={() => showStatus('under_review')}
          active={statusFilter === 'under_review'}
          loading={countsLoading}
        />
        <TriageStat
          label="Resolved · 7d"
          value={counts?.resolved_7d ?? 0}
          caption="Closed in the last 7 days"
          loading={countsLoading}
        />
      </section>

      {/* Filters */}
      <section aria-label="Filter reports" className="rounded-xl border border-border bg-card p-3">
        <div className="grid grid-cols-2 gap-2.5 xl:grid-cols-[minmax(230px,1.6fr)_repeat(3,minmax(125px,1fr))_minmax(135px,1fr)_minmax(135px,1fr)]">
          <label className="col-span-2 block xl:col-span-1">
            <span className="mb-1 block text-[12px] font-medium text-muted">Search</span>
            <span className="relative block">
              <Search
                size={14}
                className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-muted"
                aria-hidden="true"
              />
              <input
                type="search"
                placeholder="Search reporter, target, or ID"
                value={search}
                onChange={(e) => {
                  setSearch(e.target.value)
                  setPage(1)
                }}
                className="h-9 w-full rounded-lg border border-border bg-card pl-8 pr-3 text-[12.5px] text-ink placeholder:text-muted/70 outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
              />
            </span>
          </label>

          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">Status</span>
            <select
              value={statusFilter}
              onChange={(e) => {
                setStatusFilter(e.target.value)
                setPage(1)
              }}
              className="h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12.5px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
            >
              <option value="all">All statuses</option>
              <option value="open">Open reports</option>
              {STATUS_OPTIONS.map((status) => (
                <option key={status} value={status}>
                  {status.replace(/_/g, ' ').replace(/\b\w/g, (character) => character.toUpperCase())}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">Type</span>
            <select
              value={typeFilter}
              onChange={(e) => {
                setTypeFilter(e.target.value)
                setPage(1)
              }}
              className="h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12.5px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
            >
              <option value="all">All types</option>
              {['message', 'product', 'seller', 'other'].map((type) => (
                <option key={type} value={type}>
                  {type.charAt(0).toUpperCase() + type.slice(1)}
                </option>
              ))}
            </select>
          </label>

          <label className="col-span-2 block xl:col-span-1">
            <span className="mb-1 block text-[12px] font-medium text-muted">Priority</span>
            <select
              value={priorityFilter}
              onChange={(e) => {
                setPriorityFilter(e.target.value)
                setPage(1)
              }}
              className="h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12.5px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
            >
              <option value="all">All priorities</option>
              <option value="high">High</option>
              <option value="normal">Normal</option>
            </select>
          </label>

          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">From</span>
            <input
              type="date"
              value={dateFrom}
              onChange={(e) => {
                setDateFrom(e.target.value)
                setPage(1)
              }}
              className="h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
            />
          </label>

          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">To</span>
            <input
              type="date"
              value={dateTo}
              onChange={(e) => {
                setDateTo(e.target.value)
                setPage(1)
              }}
              className="h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
            />
          </label>
        </div>

        {hasFilters && (
          <div className="mt-2 flex justify-end">
            <button
              type="button"
              onClick={clearFilters}
              className="text-[12px] font-semibold text-primary hover:underline"
            >
              Clear filters
            </button>
          </div>
        )}
      </section>

      {/* Report table */}
      {reportsLoading && <ReportsSkeleton />}
      {isError && (
        <div className="rounded-xl border border-error/20 bg-card p-10 text-center">
          <p className="text-[13px] text-error">{error.message}</p>
        </div>
      )}

      {!reportsLoading && !isError && (
        <section className="overflow-hidden rounded-xl border border-border bg-card">
          <div className="px-4 py-3.5">
            <h2 className="text-[15px] font-bold text-ink">Reports</h2>
            <p className="mt-0.5 text-[12px] text-muted">
              {filtered.length} matching report{filtered.length === 1 ? '' : 's'} · high priority first
            </p>
          </div>

          {pageRows.length === 0 ? (
            <div className="flex flex-col items-center border-t border-border px-6 py-16 text-center">
              <Flag size={22} className="text-muted" aria-hidden="true" />
              <p className="mt-2 text-[15px] font-semibold text-ink">
                {hasFilters ? 'No reports match these filters' : 'No reports yet'}
              </p>
              <p className="mt-1 max-w-sm text-[12.5px] leading-relaxed text-muted">
                {hasFilters
                  ? 'Try a different reporter, status, type, priority, or date range.'
                  : 'New reports from the storefront will appear here.'}
              </p>
              {hasFilters && (
                <button
                  type="button"
                  onClick={clearFilters}
                  className="mt-3 inline-flex h-9 items-center rounded-lg bg-secondary px-3.5 text-[12px] font-semibold text-white hover:bg-primaryDeep"
                >
                  Clear filters
                </button>
              )}
            </div>
          ) : (
            <>
              <div className="hidden overflow-x-auto lg:block">
                <table className="w-full min-w-[760px] text-left">
                  <thead className="border-y border-border bg-canvas/60">
                    <tr>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Priority</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Type</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Reporter</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Target</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Status</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Opened</th>
                      <th className="w-10 px-3 py-2">
                        <span className="sr-only">Open report</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {pageRows.map((row) => {
                      const TypeIcon = TYPE_ICONS[row.type] || Flag
                      const typeColor = TYPE_COLORS[row.type] || '#78909C'
                      const target =
                        row.category === 'other' && row.custom_details
                          ? `Other: "${row.custom_details.length > 52 ? `${row.custom_details.slice(0, 52)}...` : row.custom_details}"`
                          : categoryLabel(row.category)
                      return (
                        <tr
                          key={row.id}
                          onClick={() => openReport(row)}
                          className={`admin-list-item admin-list-row cursor-pointer ${
                            row.priority === 'high' ? 'bg-errorSoft/15' : ''
                          }`}
                        >
                          <td className="px-4 py-3">
                            {row.priority === 'high' ? (
                              <span className="inline-flex items-center gap-1 text-[12px] font-semibold text-error">
                                <AlertTriangle size={12} aria-hidden="true" /> High
                              </span>
                            ) : (
                              <span className="text-[12px] text-muted">Normal</span>
                            )}
                          </td>
                          <td className="px-4 py-3">
                            <span
                              className="inline-flex items-center gap-1.5 text-[12px] font-medium"
                              style={{ color: typeColor }}
                            >
                              <TypeIcon size={13} aria-hidden="true" /> {row.type}
                            </span>
                          </td>
                          <td className="max-w-[190px] px-4 py-3">
                            <p className="truncate text-[12.5px] font-semibold text-ink">
                              {row.profiles?.full_name ?? 'Unknown reporter'}
                            </p>
                            {row.profiles?.email && (
                              <p className="truncate text-[12px] text-muted">{row.profiles.email}</p>
                            )}
                          </td>
                          <td className="max-w-[240px] px-4 py-3">
                            <span className="block truncate text-[12px] text-muted" title={target}>
                              {target}
                            </span>
                          </td>
                          <td className="px-4 py-3">
                            <Badge label={row.status?.replace(/_/g, ' ')} variant={row.status} />
                          </td>
                          <td className="px-4 py-3">
                            <span className="block text-[12px] text-muted">
                              {formatDate(row.created_at)}
                            </span>
                            <span className="mt-0.5 block font-mono text-[11px] text-muted/70">
                              #{shortId(row.id)}
                            </span>
                          </td>
                          <td className="px-3 py-3">
                            <button
                              type="button"
                              onClick={(event) => {
                                event.stopPropagation()
                                openReport(row)
                              }}
                              aria-label={`Open report ${shortId(row.id)}`}
                              className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-muted/60 transition-colors hover:bg-canvas hover:text-ink"
                            >
                              <ChevronRight size={15} aria-hidden="true" />
                            </button>
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>

              <div className="divide-y divide-border border-t border-border lg:hidden">
                {pageRows.map((row) => {
                  const TypeIcon = TYPE_ICONS[row.type] || Flag
                  const typeColor = TYPE_COLORS[row.type] || '#78909C'
                  const target =
                    row.category === 'other' && row.custom_details
                      ? `Other: "${row.custom_details.length > 44 ? `${row.custom_details.slice(0, 44)}...` : row.custom_details}"`
                      : categoryLabel(row.category)
                  return (
                    <button
                      key={row.id}
                      type="button"
                      onClick={() => openReport(row)}
                      className={`admin-list-item admin-list-card block w-full px-4 py-3 text-left ${
                        row.priority === 'high' ? 'bg-errorSoft/15' : ''
                      }`}
                    >
                      <span className="flex items-center justify-between gap-2">
                        <span
                          className="inline-flex items-center gap-1.5 text-[12px] font-medium"
                          style={{ color: typeColor }}
                        >
                          <TypeIcon size={13} aria-hidden="true" /> {row.type}
                        </span>
                        <Badge label={row.status?.replace(/_/g, ' ')} variant={row.status} />
                      </span>
                      <span className="mt-2 block text-[13px] font-semibold text-ink">
                        {row.profiles?.full_name ?? 'Unknown reporter'}
                      </span>
                      <span className="mt-0.5 block truncate text-[12px] text-muted">
                        {target}
                      </span>
                      <span className="mt-1.5 flex items-center justify-between gap-2 text-[11.5px] text-muted">
                        <span>
                          {formatDate(row.created_at)} · #{shortId(row.id)}
                        </span>
                        {row.priority === 'high' && (
                          <span className="inline-flex items-center gap-1 font-semibold text-error">
                            <AlertTriangle size={11} aria-hidden="true" /> High priority
                          </span>
                        )}
                      </span>
                    </button>
                  )
                })}
              </div>

              <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-3">
                <p className="text-[12px] text-muted">
                  Showing{' '}
                  <span className="font-semibold text-secondary">
                    {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, filtered.length)}
                  </span>{' '}
                  of {filtered.length}
                </p>
                <div className="flex items-center gap-1">
                  <button
                    type="button"
                    disabled={page <= 1}
                    onClick={() => setPage((current) => Math.max(1, current - 1))}
                    aria-label="Previous page"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-card text-muted transition-colors hover:border-primary/40 hover:text-ink disabled:cursor-not-allowed disabled:opacity-35"
                  >
                    <ChevronLeft size={14} />
                  </button>
                  <span className="px-2 font-mono text-[11px] text-muted">
                    {page} / {totalPages}
                  </span>
                  <button
                    type="button"
                    disabled={page >= totalPages}
                    onClick={() => setPage((current) => Math.min(totalPages, current + 1))}
                    aria-label="Next page"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-card text-muted transition-colors hover:border-primary/40 hover:text-ink disabled:cursor-not-allowed disabled:opacity-35"
                  >
                    <ChevronRight size={14} />
                  </button>
                </div>
              </div>
            </>
          )}
        </section>
      )}

      {/* Slide-over Detail Panel */}
      {selectedReport && (
        <div className="fixed inset-0 z-50 flex justify-end" onClick={() => setSelectedReport(null)}>
          <div className="fixed inset-0 bg-black/30" />
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Report details"
            className="relative flex h-full w-full max-w-lg flex-col bg-card shadow-pop"
            onClick={(event) => event.stopPropagation()}
          >
            <header className="flex shrink-0 items-start justify-between gap-3 border-b border-border px-5 py-4">
              <div className="min-w-0">
                <p className="text-[12px] text-muted">
                  #{shortId(selectedReport.id)} · {formatDate(selectedReport.created_at)}
                </p>
                <div className="mt-1 flex flex-wrap items-center gap-2">
                  {selectedReport.priority === 'high' && (
                    <span className="rounded-full bg-errorSoft px-2 py-0.5 text-[11px] font-semibold text-error">
                      High priority
                    </span>
                  )}
                  <Badge label={selectedReport.type} variant={selectedReport.type} />
                  <span className="text-[12px] text-muted">
                    {categoryLabel(selectedReport.category)}
                  </span>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setSelectedReport(null)}
                aria-label="Close report"
                className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-muted transition-colors hover:bg-canvas hover:text-ink"
              >
                <X size={18} />
              </button>
            </header>

            <div className="flex-1 space-y-5 overflow-y-auto px-5 py-5">
              <div className="border-b border-border pb-4">
                <p className="text-[12px] font-medium text-muted">Reporter</p>
                <p className="mt-1 text-[14px] font-semibold text-ink">
                  {selectedReport.profiles?.full_name ?? 'Unknown'}
                </p>
                <p className="mt-0.5 text-[12px] text-muted">
                  {selectedReport.reporter_role}
                  {selectedReport.profiles?.email ? ` · ${selectedReport.profiles.email}` : ''}
                </p>
              </div>

              {selectedReport.category === 'other' && selectedReport.custom_details && (
                <div className="rounded-xl border border-pending/30 bg-pendingSoft/40 p-4">
                  <p className="text-[12px] font-semibold text-pending">Reporter&apos;s description</p>
                  <p className="mt-1 whitespace-pre-wrap text-[13px] leading-relaxed text-ink">
                    {selectedReport.custom_details}
                  </p>
                </div>
              )}

              <div>
                <label
                  htmlFor="report-status"
                  className="mb-1 block text-[12px] font-medium text-muted"
                >
                  Status
                </label>
                <select
                  id="report-status"
                  value={detailStatus}
                  onChange={(event) => {
                    setDetailStatus(event.target.value)
                    setActionError(null)
                  }}
                  className="h-10 w-full rounded-lg border border-border bg-card px-3 text-[13px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
                >
                  {STATUS_OPTIONS.map((status) => (
                    <option key={status} value={status}>
                      {status.replace(/_/g, ' ').replace(/\b\w/g, (character) => character.toUpperCase())}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label
                  htmlFor="report-action"
                  className="mb-1 block text-[12px] font-medium text-muted"
                >
                  Action taken {detailStatus === 'resolved' && <span className="text-error">*</span>}
                </label>
                <select
                  id="report-action"
                  value={detailAction}
                  onChange={(event) => {
                    setDetailAction(event.target.value)
                    setActionError(null)
                  }}
                  className="h-10 w-full rounded-lg border border-border bg-card px-3 text-[13px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
                >
                  {ACTION_OPTIONS.map((action) => (
                    <option key={action} value={action}>
                      {action.replace(/_/g, ' ').replace(/\b\w/g, (character) => character.toUpperCase())}
                    </option>
                  ))}
                </select>
                {actionError && <p className="mt-1 text-[12px] text-error">{actionError}</p>}
              </div>

              <div>
                <label
                  htmlFor="report-notes"
                  className="mb-1 block text-[12px] font-medium text-muted"
                >
                  Admin notes
                </label>
                <textarea
                  id="report-notes"
                  value={detailNotes}
                  onChange={(event) => setDetailNotes(event.target.value)}
                  rows={3}
                  placeholder="Internal notes (not visible to reporter)"
                  className="w-full rounded-lg border border-border bg-card px-3 py-2.5 text-[13px] text-ink outline-none transition-colors placeholder:text-muted/70 focus:border-primary focus:ring-2 focus:ring-primary/15"
                />
              </div>

              <div className="rounded-xl border border-border p-4">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="text-[13px] font-semibold text-ink">Notify reporter</p>
                    <p className="mt-0.5 text-[12px] text-muted">
                      {selectedReport.reporter_notified
                        ? 'Already notified'
                        : 'Send an update to the reporter'}
                    </p>
                  </div>
                  {!notifyMode && !selectedReport.reporter_notified && (
                    <button
                      type="button"
                      onClick={() => setNotifyMode('template')}
                      className="h-8 shrink-0 rounded-lg bg-secondary px-3 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep"
                    >
                      Notify
                    </button>
                  )}
                </div>
                {notifyMode && (
                  <div className="mt-3 space-y-2">
                    {Object.entries(NOTIFICATION_TEMPLATES).map(([key, template]) => (
                      <button
                        key={key}
                        type="button"
                        onClick={() => {
                          setSelectedTemplate(key)
                          setNotifyMode('template')
                        }}
                        className={`w-full rounded-lg border px-3 py-2 text-left text-[12px] leading-relaxed transition-colors hover:bg-canvas ${
                          selectedTemplate === key
                            ? 'border-primary bg-canvas'
                            : 'border-border bg-card'
                        }`}
                      >
                        {template}
                      </button>
                    ))}
                    <button
                      type="button"
                      onClick={() => setNotifyMode('custom')}
                      className="w-full rounded-lg border border-border px-3 py-2 text-left text-[12px] text-secondary transition-colors hover:bg-canvas"
                    >
                      Write custom message
                    </button>
                    {notifyMode === 'custom' && (
                      <textarea
                        value={customMsg}
                        onChange={(event) => setCustomMsg(event.target.value)}
                        rows={3}
                        placeholder="Type a custom message..."
                        className="w-full rounded-lg border border-border bg-card px-3 py-2.5 text-[13px] text-ink outline-none transition-colors placeholder:text-muted/70 focus:border-primary focus:ring-2 focus:ring-primary/15"
                      />
                    )}
                    <div className="flex gap-2">
                      <button
                        type="button"
                        onClick={() => {
                          setNotifyMode(null)
                          setSelectedTemplate(null)
                          setCustomMsg('')
                        }}
                        className="h-8 rounded-lg border border-border px-3 text-[12px] font-semibold text-muted hover:bg-canvas"
                      >
                        Cancel
                      </button>
                      <button
                        type="button"
                        onClick={handleNotify}
                        disabled={
                          saving ||
                          (notifyMode === 'template' ? !selectedTemplate : !customMsg.trim())
                        }
                        className="h-8 rounded-lg bg-secondary px-3 text-[12px] font-semibold text-white hover:bg-primaryDeep disabled:opacity-50"
                      >
                        {saving ? 'Sending…' : 'Send'}
                      </button>
                    </div>
                  </div>
                )}
              </div>
            </div>

            <footer className="shrink-0 border-t border-border bg-card px-5 py-4">
              <button
                type="button"
                onClick={handleSave}
                disabled={saving}
                className="h-10 w-full rounded-lg bg-secondary text-[13px] font-semibold text-white transition-colors hover:bg-primaryDeep disabled:opacity-50"
              >
                {saving ? 'Saving…' : 'Save changes'}
              </button>
            </footer>
          </div>
        </div>
      )}
    </div>
  )
}

// ── Queue summary ────────────────────────────────────────────────

function TriageStat({ label, value, caption, onClick, active = false, alert = false, loading = false }) {
  const content = (
    <>
      <p className="text-[12px] font-medium text-muted">{label}</p>
      {loading ? (
        <div className="mt-1.5 h-6 w-14 animate-pulse rounded bg-canvas" />
      ) : (
        <p
          className={`mt-1.5 font-mono text-[24px] font-semibold leading-none tracking-tight tnum ${
            alert ? 'text-error' : 'text-ink'
          }`}
        >
          {value}
        </p>
      )}
      <p className="mt-2 text-[12px] leading-relaxed text-muted">{caption}</p>
    </>
  )

  const classes = `border-b-2 bg-card px-4 py-4 text-left transition-colors ${
    active ? 'border-primary bg-canvas' : 'border-transparent'
  }`

  if (!onClick) {
    return <div className={classes}>{content}</div>
  }

  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`${classes} hover:bg-canvas`}
    >
      {content}
    </button>
  )
}

function ReportsSkeleton() {
  return (
    <div className="overflow-hidden rounded-xl border border-border bg-card">
      <div className="border-b border-border px-4 py-3.5">
        <div className="h-4 w-24 animate-pulse rounded bg-canvas" />
        <div className="mt-1.5 h-3 w-44 animate-pulse rounded bg-canvas" />
      </div>
      <div className="border-y border-border bg-canvas/60 px-4 py-2.5">
        <div className="h-3 w-full animate-pulse rounded bg-sand" />
      </div>
      <div className="divide-y divide-border">
        {Array.from({ length: 6 }).map((_, index) => (
          <div key={index} className="flex items-center gap-4 px-4 py-3">
            <div className="h-3 w-16 animate-pulse rounded bg-canvas" />
            <div className="h-3 flex-1 animate-pulse rounded bg-canvas" />
            <div className="h-5 w-20 animate-pulse rounded-full bg-canvas" />
          </div>
        ))}
      </div>
    </div>
  )
}
