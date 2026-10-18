import { useMemo, useState } from 'react'
import {
  Activity,
  Download,
  FileClock,
  Gavel,
  LogIn,
  Search,
  SearchX,
  ShieldAlert,
  Wallet,
  X,
} from 'lucide-react'
import Badge from '../components/ui/Badge.jsx'
import Modal from '../components/ui/Modal.jsx'
import StatCard from '../components/ui/StatCard.jsx'
import { StatCardSkeleton, TableSkeleton } from '../components/ui/Skeleton.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import DateRangePicker from '../components/ui/DateRangePicker.jsx'
import { useActivityAudit, usePaymentAudit, useSecurityAudit, useSellerAudit, useSessionAudit } from '../hooks/useAuditLogs.js'
import {
  ACTIVITY_ACTIONS,
  AUDIT_TABS,
  LOCKOUT_STATUSES,
  PAYMENT_DECISIONS,
  SELLER_ACTIONS,
  SESSION_EVENTS,
  activityAuditCsv,
  downloadCsv,
  formatAuditDateTime,
  paymentAuditCsv,
  securityAuditCsv,
  sellerAuditCsv,
  sessionAuditCsv,
  shortId,
  toneFor,
} from '../lib/audit'
import { formatCurrency } from '../lib/constants'

const ACTION_OPTIONS = { seller: SELLER_ACTIONS, payment: PAYMENT_DECISIONS, security: LOCKOUT_STATUSES, sessions: SESSION_EVENTS, activity: ACTIVITY_ACTIONS }
const CSV_EXPORTERS = { seller: sellerAuditCsv, payment: paymentAuditCsv, security: securityAuditCsv, sessions: sessionAuditCsv, activity: activityAuditCsv }

function parseISODate(str) {
  if (!str) return null
  const [y, m, d] = str.split('-').map(Number)
  return new Date(y, m - 1, d)
}

function toISODate(date) {
  if (!date) return ''
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

function humanize(value) {
  return String(value ?? '').replace(/[_]/g, ' ')
}

/**
 * Audit Logs — who did what, when. Required for client compliance.
 *
 * Five trails. Four are written server-side and unbypassable by clients:
 * seller decisions (immutable status-change trigger), manual GCash decisions
 * (trigger + RPC writers only), sign-in security (failed attempts and
 * lockouts with approximate city-level location) and seller activity
 * (trigger-written product / store / order-status log). The fifth — seller
 * sessions (sign-in / sign-out) — is written best-effort BY the clients,
 * because sign-ins touch no public table for a trigger to fire on; its rows
 * are claims, not proof, and a missing sign-out means "never logged".
 *
 * Deliberately NOT here: live GoTrue events (not client-readable — use the
 * per-account security diagnostics behind `admin_account_security_overview`)
 * and suspensions (the flag has no history table yet, so there is nothing to
 * list). Both gaps are stated on the page rather than hidden.
 */
export default function AuditLogs() {
  const [tab, setTab] = useState('seller')
  const [action, setAction] = useState('all')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(0)
  const [selected, setSelected] = useState(null)
  const [exporting, setExporting] = useState(false)

  const filters = useMemo(
    () => ({ dateFrom: dateFrom || null, dateTo: dateTo || null, search, page }),
    [dateFrom, dateTo, search, page],
  )

  const sellerQuery = useSellerAudit({ ...filters, action: tab === 'seller' ? action : 'all' })
  const paymentQuery = usePaymentAudit({ ...filters, decision: tab === 'payment' ? action : 'all' })
  const securityQuery = useSecurityAudit({ ...filters, status: tab === 'security' ? action : 'all' })
  const sessionQuery = useSessionAudit({ ...filters, event: tab === 'sessions' ? action : 'all' })
  const activityQuery = useActivityAudit({ ...filters, action: tab === 'activity' ? action : 'all' })

  const activeQuery = tab === 'seller' ? sellerQuery : tab === 'payment' ? paymentQuery : tab === 'security' ? securityQuery : tab === 'sessions' ? sessionQuery : activityQuery
  const { data, isLoading, isError, error } = activeQuery
  const rows = data?.rows ?? []
  const total = data?.total ?? 0
  const pageSize = data?.pageSize ?? 50
  const pageCount = Math.max(1, Math.ceil(total / pageSize))

  const switchTab = (next) => {
    setTab(next)
    setAction('all')
    setPage(0)
    setSelected(null)
  }

  const clearFilters = () => {
    setAction('all')
    setDateFrom('')
    setDateTo('')
    setSearch('')
    setPage(0)
  }

  const filtersActive = action !== 'all' || dateFrom || dateTo || search.trim()

  const handleExport = async () => {
    // Export the whole filtered set, not just the visible page: re-run the
    // active query without pagination (capped server-side at 2000 rows).
    setExporting(true)
    try {
      const { supabase } = await import('../lib/supabase')
      const { from: gte, to: lte } = (() => {
        const b = {}
        if (dateFrom) { const f = new Date(dateFrom); f.setHours(0, 0, 0, 0); b.gte = f.toISOString() }
        if (dateTo) { const t = new Date(dateTo); t.setHours(23, 59, 59, 999); b.lte = t.toISOString() }
        return b
      })()

      const { mapActivityRow, mapFailedLoginRow, mapPaymentAuditRow, mapSellerAuditRow, mapSessionRow } = await import('../lib/audit')
      let mapped = []
      if (tab === 'seller') {
        let q = supabase.from('seller_application_audit_log').select('*').order('created_at', { ascending: false }).limit(2000)
        if (action !== 'all') q = q.eq('action', action)
        if (gte) q = q.gte('created_at', gte)
        if (lte) q = q.lte('created_at', lte)
        const { data: raw, error: err } = await q
        if (err) throw err
        const ids = (raw ?? []).flatMap((r) => [r.actor_id, r.profile_id])
        const { data: profiles } = await supabase.from('profiles').select('id, full_name, email').in('id', [...new Set(ids.filter(Boolean))])
        const names = Object.fromEntries((profiles ?? []).map((p) => [p.id, p]))
        mapped = (raw ?? []).map((r) => mapSellerAuditRow(r, names))
      } else if (tab === 'payment') {
        let q = supabase.from('gcash_payment_decision_audit').select('*').order('created_at', { ascending: false }).limit(2000)
        if (action !== 'all') q = q.eq('decision', action)
        if (gte) q = q.gte('created_at', gte)
        if (lte) q = q.lte('created_at', lte)
        const { data: raw, error: err } = await q
        if (err) throw err
        const ids = (raw ?? []).map((r) => r.seller_id)
        const { data: profiles } = await supabase.from('profiles').select('id, full_name, email').in('id', [...new Set(ids.filter(Boolean))])
        const names = Object.fromEntries((profiles ?? []).map((p) => [p.id, p]))
        mapped = (raw ?? []).map((r) => mapPaymentAuditRow(r, names))
      } else if (tab === 'sessions') {
        let q = supabase.from('account_session_log').select('*').eq('role', 'seller').order('created_at', { ascending: false }).limit(2000)
        if (action !== 'all') q = q.eq('event', action)
        if (gte) q = q.gte('created_at', gte)
        if (lte) q = q.lte('created_at', lte)
        const { data: raw, error: err } = await q
        if (err) throw err
        const ids = (raw ?? []).map((r) => r.user_id)
        const { data: profiles } = await supabase.from('profiles').select('id, full_name, email').in('id', [...new Set(ids.filter(Boolean))])
        const names = Object.fromEntries((profiles ?? []).map((p) => [p.id, p]))
        mapped = (raw ?? []).map((r) => mapSessionRow(r, names))
      } else if (tab === 'activity') {
        let q = supabase.from('seller_activity_log').select('*').order('created_at', { ascending: false }).limit(2000)
        if (action !== 'all') q = q.eq('action', action)
        if (gte) q = q.gte('created_at', gte)
        if (lte) q = q.lte('created_at', lte)
        const { data: raw, error: err } = await q
        if (err) throw err
        const ids = (raw ?? []).map((r) => r.actor_id)
        const { data: profiles } = await supabase.from('profiles').select('id, full_name, email').in('id', [...new Set(ids.filter(Boolean))])
        const names = Object.fromEntries((profiles ?? []).map((p) => [p.id, p]))
        mapped = (raw ?? []).map((r) => mapActivityRow(r, names))
      } else {
        let q = supabase.from('failed_logins').select('*').order('failed_at', { ascending: false }).limit(2000)
        if (action !== 'all') q = q.eq('status', action)
        if (gte) q = q.gte('failed_at', gte)
        if (lte) q = q.lte('failed_at', lte)
        const { data: raw, error: err } = await q
        if (err) throw err
        const ids = (raw ?? []).map((r) => r.user_id)
        const { data: profiles } = await supabase.from('profiles').select('id, full_name, email').in('id', [...new Set(ids.filter(Boolean))])
        const names = Object.fromEntries((profiles ?? []).map((p) => [p.id, p]))
        mapped = (raw ?? []).map((r) => mapFailedLoginRow(r, names))
      }
      const q = search.trim().toLowerCase()
      const filtered = q
        ? mapped.filter((r) => [r.actor, r.actorEmail, r.subject, r.subjectEmail, r.notes, r.reference, r.ip, r.device, r.place, r.role, r.detail, r.entity].filter(Boolean).some((v) => String(v).toLowerCase().includes(q)))
        : mapped
      downloadCsv(`audit-${tab}-${new Date().toISOString().slice(0, 10)}.csv`, CSV_EXPORTERS[tab](filtered))
    } finally {
      setExporting(false)
    }
  }

  // Breakdowns describe the loaded page (bounded, honest); the total counts
  // every matching event across pages.
  const stats = useMemo(() => {
    const count = (predicate) => rows.filter(predicate).length
    if (tab === 'seller') {
      return [
        { label: 'Matching events', value: total },
        { label: 'Approved (page)', value: count((r) => r.action === 'approved') },
        { label: 'Rejected (page)', value: count((r) => r.action === 'rejected') },
      ]
    }
    if (tab === 'payment') {
      return [
        { label: 'Matching events', value: total },
        { label: 'Confirmed (page)', value: count((r) => r.action === 'confirmed') },
        { label: 'Rejected (page)', value: count((r) => r.action === 'rejected') },
      ]
    }
    if (tab === 'sessions') {
      return [
        { label: 'Matching events', value: total },
        { label: 'Sign-ins (page)', value: count((r) => r.action === 'sign_in') },
        { label: 'Sign-outs (page)', value: count((r) => r.action === 'sign_out') },
      ]
    }
    if (tab === 'activity') {
      return [
        { label: 'Matching events', value: total },
        { label: 'Products (page)', value: count((r) => String(r.action).startsWith('product_')) },
        { label: 'Orders (page)', value: count((r) => r.action === 'order_status_changed') },
      ]
    }
    return [
      { label: 'Matching events', value: total },
      { label: 'Locked (page)', value: count((r) => r.action === 'locked') },
      { label: 'Active watch (page)', value: count((r) => r.action === 'active') },
    ]
  }, [rows, total, tab])

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-display text-2xl font-bold text-[#3B2314]">Audit Logs</h1>
          <p className="mt-1 max-w-2xl text-sm text-[#6B5C4E]">
            Who did what, when — mostly from trails the database writes
            itself, so no client can rewrite them. Seller sessions are the
            exception: the apps report their own sign-ins. Newest first,
            refreshed every minute.
          </p>
        </div>
        <button
          type="button"
          onClick={handleExport}
          disabled={!rows.length || exporting}
          className="inline-flex items-center gap-2 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-white shadow-sm transition-all hover:bg-secondary hover:shadow-md disabled:opacity-40"
        >
          <Download size={16} />
          {exporting ? 'Exporting…' : 'Export CSV'}
        </button>
      </div>

      {/* Tabs */}
      <div className="flex flex-wrap gap-2">
        {AUDIT_TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            onClick={() => switchTab(t.id)}
            aria-pressed={tab === t.id}
            className={`inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm font-semibold transition-colors ${
              tab === t.id ? 'bg-[#3B2314] text-white shadow-sm' : 'border border-[#D9D0C7] bg-white text-[#6B5C4E] hover:border-[#8B5A2B] hover:text-[#3B2314]'
            }`}
          >
            {t.id === 'seller' && <Gavel size={15} />}
            {t.id === 'payment' && <Wallet size={15} />}
            {t.id === 'security' && <ShieldAlert size={15} />}
            {t.id === 'sessions' && <LogIn size={15} />}
            {t.id === 'activity' && <Activity size={15} />}
            {t.label}
          </button>
        ))}
      </div>

      {/* Stats */}
      {isLoading ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <StatCardSkeleton /><StatCardSkeleton /><StatCardSkeleton />
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          {stats.map((s) => (
            <StatCard key={s.label} label={s.label} value={s.value} icon={<FileClock size={18} />} />
          ))}
        </div>
      )}

      {/* Filters */}
      <div className="rounded-2xl border border-[#D9D0C7] bg-white p-4 shadow-sm">
        <div className="flex flex-wrap items-center gap-3">
          <select
            value={action}
            onChange={(e) => { setAction(e.target.value); setPage(0) }}
            aria-label="Filter by action"
            className="rounded-full border border-[#D9D0C7] bg-white px-4 py-2 text-sm font-medium text-[#3B2314] outline-none transition-colors focus:border-primary"
          >
            {ACTION_OPTIONS[tab].map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
          <DateRangePicker
            from={parseISODate(dateFrom)}
            to={parseISODate(dateTo)}
            onChange={(from, to) => {
              setDateFrom(toISODate(from))
              setDateTo(toISODate(to))
              setPage(0)
            }}
          />
          {filtersActive && (
            <button
              type="button"
              onClick={clearFilters}
              className="inline-flex items-center gap-1 rounded-full px-3 py-2 text-xs font-semibold text-[#6B5C4E] transition-colors hover:text-[#3B2314]"
            >
              <X size={14} /> Clear filters
            </button>
          )}
        </div>
        <div className="relative mt-3">
          <Search size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-[#6B5C4E]" />
          <input
            type="search"
            placeholder={tab === 'seller' ? 'Search admin, applicant, note…' : tab === 'payment' ? 'Search seller, order, reference…' : tab === 'sessions' ? 'Search seller, source, device…' : tab === 'activity' ? 'Search seller, product, store…' : 'Search account, IP, device, place…'}
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(0) }}
            className="w-full rounded-xl border border-[#D9D0C7] bg-[#FBF8F5] py-2.5 pl-10 pr-10 text-sm text-[#3B2314] placeholder-[#6B5C4E] outline-none transition-all focus:border-primary focus:bg-white focus:ring-2 focus:ring-primary/20"
          />
          {search && (
            <button
              type="button"
              onClick={() => setSearch('')}
              aria-label="Clear search"
              className="absolute right-3 top-1/2 -translate-y-1/2 rounded-full p-1 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] hover:text-[#3B2314]"
            >
              <X size={14} />
            </button>
          )}
        </div>
      </div>

      {/* Table */}
      {isLoading && <TableSkeleton cols={4} rows={8} />}
      {isError && (
        <div className="rounded-2xl border border-[#D9D0C7] bg-white p-8 text-center">
          <p className="text-sm text-[#D64545]">{error?.message ?? 'Could not load audit logs.'}</p>
        </div>
      )}
      {!isLoading && !isError && (
        <div className="overflow-x-auto rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
          <table className="min-w-full text-left text-sm">
            <thead className="bg-[#FBF8F5]">
              <tr>
                <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">When</th>
                <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Actor</th>
                <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">{tab === 'security' ? 'Detail' : tab === 'payment' ? 'Order' : tab === 'sessions' ? 'Source' : tab === 'activity' ? 'Item' : 'Applicant'}</th>
                <th className="px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">{tab === 'security' ? 'State' : tab === 'sessions' ? 'Event' : 'Action'}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#F5F0EB]">
              {rows.length === 0 ? (
                <tr>
                  <td colSpan={4} className="p-0">
                    <EmptyState
                      Icon={SearchX}
                      title="No matching events"
                      description="No audit events match the current search and filters."
                      action={filtersActive ? (
                        <button
                          type="button"
                          onClick={clearFilters}
                          className="mt-4 rounded-full bg-primary px-4 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-secondary"
                        >
                          Clear filters
                        </button>
                      ) : undefined}
                    />
                  </td>
                </tr>
              ) : (
                rows.map((row) => (
                  <tr
                    key={row.id}
                    onClick={() => setSelected(row)}
                    className="cursor-pointer transition-colors hover:bg-[#FBF8F5]"
                  >
                    <td className="whitespace-nowrap px-6 py-4 text-[#3B2314]">
                      {formatAuditDateTime(row.at)}
                    </td>
                    <td className="px-6 py-4">
                      <p className="font-medium text-[#3B2314]">{row.actor}</p>
                      {row.actorEmail && <p className="text-xs text-[#6B5C4E]">{row.actorEmail}</p>}
                    </td>
                    <td className="px-6 py-4">
                      <p className="font-medium text-[#3B2314]">{row.subject}</p>
                      {row.subjectEmail && <p className="text-xs text-[#6B5C4E]">{row.subjectEmail}</p>}
                      {tab === 'payment' && row.reference !== '—' && (
                        <p className="text-xs text-[#6B5C4E]">Ref {row.reference}</p>
                      )}
                    </td>
                    <td className="px-6 py-4">
                      <Badge label={humanize(row.action)} variant={toneFor(row.action, row)} dot />
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* Pagination */}
      {!isLoading && !isError && pageCount > 1 && (
        <div className="flex items-center justify-between text-sm text-[#6B5C4E]">
          <p>Page {page + 1} of {pageCount} · {total} events</p>
          <div className="flex gap-2">
            <button
              type="button"
              disabled={page === 0}
              onClick={() => setPage((p) => Math.max(0, p - 1))}
              className="rounded-full border border-[#D9D0C7] bg-white px-4 py-1.5 font-semibold transition-colors hover:border-[#8B5A2B] disabled:opacity-40"
            >
              Previous
            </button>
            <button
              type="button"
              disabled={page >= pageCount - 1}
              onClick={() => setPage((p) => p + 1)}
              className="rounded-full border border-[#D9D0C7] bg-white px-4 py-1.5 font-semibold transition-colors hover:border-[#8B5A2B] disabled:opacity-40"
            >
              Next
            </button>
          </div>
        </div>
      )}

      {/* Coverage note — the gaps are stated, not hidden. */}
      <p className="text-xs leading-relaxed text-[#6B5C4E]">
        Covers seller-application decisions, manual GCash decisions, sign-in
        security, seller sessions and seller activity. Sessions are
        client-reported (a missing sign-out means it was never logged, e.g.
        an older app version). Live GoTrue events sit behind the
        per-account security diagnostics, and account suspensions leave no
        history yet — both are follow-ups, not silent gaps.
      </p>

      {/* Detail */}
      <Modal open={!!selected} onClose={() => setSelected(null)} title="Event detail" size="md">
        {selected && <AuditDetail row={selected} tab={tab} />}
      </Modal>
    </div>
  )
}

function DetailRow({ label, value }) {
  if (value == null || value === '') return null
  return (
    <div className="flex items-start justify-between gap-4 border-b border-[#F5F0EB] py-2.5 last:border-0">
      <p className="text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">{label}</p>
      <p className="text-right text-sm font-medium text-[#3B2314]">{value}</p>
    </div>
  )
}

function AuditDetail({ row, tab }) {
  return (
    <div className="text-sm">
      <div className="mb-3 flex items-center gap-2">
        <Badge label={humanize(row.action)} variant={toneFor(row.action, row)} dot />
        <span className="text-xs text-[#6B5C4E]">{formatAuditDateTime(row.at)}</span>
      </div>
      <DetailRow label="Actor" value={row.actorEmail ? `${row.actor} (${row.actorEmail})` : row.actor} />
      <DetailRow label={tab === 'payment' ? 'Order' : tab === 'security' ? 'Attempts' : tab === 'sessions' ? 'Source' : tab === 'activity' ? 'Item' : 'Applicant'} value={row.subjectEmail ? `${row.subject} (${row.subjectEmail})` : row.subject} />
      {tab === 'seller' && (
        <>
          <DetailRow label="From" value={row.previousStatus} />
          <DetailRow label="To" value={row.newStatus} />
          <DetailRow label="Reviewer note" value={row.notes || '—'} />
        </>
      )}
      {tab === 'payment' && (
        <>
          <DetailRow label="Reference" value={row.reference} />
          <DetailRow
            label="Amount shown"
            value={row.amount != null ? formatCurrency(row.amount) : '—'}
          />
          <DetailRow label="Source" value={row.source} />
        </>
      )}
      {tab === 'security' && (
        <>
          <DetailRow label="IP address" value={row.ip} />
          <DetailRow label="Device" value={row.device} />
          <DetailRow label="Location" value={row.place} />
          <DetailRow label="Locked until" value={row.lockedUntil ? formatAuditDateTime(row.lockedUntil) : '—'} />
        </>
      )}
      {tab === 'sessions' && (
        <>
          <DetailRow label="Role" value={row.role} />
          <DetailRow label="Device" value={row.device} />
        </>
      )}
      {tab === 'activity' && (
        <>
          <DetailRow label="Entity" value={row.entity} />
          {row.entity === 'order' && (
            <>
              <DetailRow label="From" value={row.previousStatus} />
              <DetailRow label="To" value={row.newStatus} />
            </>
          )}
        </>
      )}
    </div>
  )
}
