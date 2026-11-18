import { useMemo, useState } from 'react'
import {
  Activity,
  ChevronLeft,
  ChevronRight,
  Download,
  Gavel,
  LogIn,
  Search,
  SearchX,
  ShieldAlert,
  Wallet,
  X,
} from 'lucide-react'
import Badge from '../components/ui/Badge.jsx'
import DateRangePicker, {
  parseISODate,
  toISODate,
} from '../components/ui/DateRangePicker.jsx'
import Modal from '../components/ui/Modal.jsx'
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
const TAB_ICONS = { seller: Gavel, payment: Wallet, security: ShieldAlert, sessions: LogIn, activity: Activity }

const TRAIL_META = {
  seller: {
    actor: 'Admin',
    subject: 'Applicant',
    description: 'Database-written seller status decisions. Admins can read, never write.',
  },
  payment: {
    actor: 'Seller',
    subject: 'Order',
    description: 'Database-written manual GCash confirmations and rejections.',
  },
  security: {
    actor: 'Account',
    subject: 'Attempts',
    description: 'Database-written failed sign-ins and lockouts. Locations are approximate.',
  },
  sessions: {
    actor: 'Account',
    subject: 'Source',
    description: 'Client-reported sign-ins and sign-outs. Treat them as claims, not proof.',
  },
  activity: {
    actor: 'Seller',
    subject: 'Item',
    description: 'Database-written product, store, and order changes from sellers.',
  },
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
  const activeMeta = TRAIL_META[tab] ?? TRAIL_META.seller
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
        { label: 'Matching events', value: total, scope: 'All pages' },
        { label: 'Approved', value: count((r) => r.action === 'approved'), scope: 'This page' },
        { label: 'Rejected', value: count((r) => r.action === 'rejected'), scope: 'This page' },
      ]
    }
    if (tab === 'payment') {
      return [
        { label: 'Matching events', value: total, scope: 'All pages' },
        { label: 'Confirmed', value: count((r) => r.action === 'confirmed'), scope: 'This page' },
        { label: 'Rejected', value: count((r) => r.action === 'rejected'), scope: 'This page' },
      ]
    }
    if (tab === 'sessions') {
      return [
        { label: 'Matching events', value: total, scope: 'All pages' },
        { label: 'Sign-ins', value: count((r) => r.action === 'sign_in'), scope: 'This page' },
        { label: 'Sign-outs', value: count((r) => r.action === 'sign_out'), scope: 'This page' },
      ]
    }
    if (tab === 'activity') {
      return [
        { label: 'Matching events', value: total, scope: 'All pages' },
        { label: 'Products', value: count((r) => String(r.action).startsWith('product_')), scope: 'This page' },
        { label: 'Orders', value: count((r) => r.action === 'order_status_changed'), scope: 'This page' },
      ]
    }
    return [
      { label: 'Matching events', value: total, scope: 'All pages' },
      { label: 'Locked', value: count((r) => r.action === 'locked'), scope: 'This page' },
      { label: 'Active watch', value: count((r) => r.action === 'active'), scope: 'This page' },
    ]
  }, [rows, total, tab])

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <nav
          aria-label="Audit trails"
          className="min-w-0 w-full max-w-full overflow-x-auto rounded-xl border border-border/80 bg-faint/40 p-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden sm:w-fit"
        >
          <div className="flex min-w-max items-center gap-1">
            {AUDIT_TABS.map((trail) => {
              const Icon = TAB_ICONS[trail.id]
              const active = tab === trail.id
              return (
                <button
                  key={trail.id}
                  type="button"
                  onClick={() => switchTab(trail.id)}
                  aria-pressed={active}
                  className={`inline-flex h-8 items-center gap-1.5 rounded-lg px-3 text-[12px] font-semibold transition-colors duration-200 ease-[cubic-bezier(0.32,0.72,0,1)] ${
                    active
                      ? 'bg-card text-ink ring-1 ring-border/80'
                      : 'text-muted hover:bg-card/70 hover:text-ink'
                  }`}
                >
                  <Icon size={14} strokeWidth={1.6} aria-hidden="true" />
                  {trail.label}
                </button>
              )
            })}
          </div>
        </nav>
        <button
          type="button"
          onClick={handleExport}
          disabled={!rows.length || exporting}
          aria-label="Export filtered audit events as CSV"
          className="inline-flex h-9 shrink-0 items-center justify-center gap-1.5 self-end rounded-lg bg-secondary px-3.5 text-[12px] font-semibold text-white transition-colors duration-200 ease-[cubic-bezier(0.32,0.72,0,1)] hover:bg-primaryDeep disabled:cursor-not-allowed disabled:opacity-40 sm:self-auto"
        >
          <Download size={14} strokeWidth={1.7} aria-hidden="true" />
          {exporting ? 'Exporting…' : 'Export CSV'}
        </button>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2 px-0.5">
        <p className="max-w-3xl text-[12.5px] leading-relaxed text-muted">{activeMeta.description}</p>
        <p className="text-[11.5px] text-muted/70">Refreshed every minute</p>
      </div>

      <section
        aria-label="Audit summary"
        className="grid grid-cols-3 gap-px overflow-hidden rounded-xl border border-border bg-border"
      >
        {isLoading
          ? Array.from({ length: 3 }).map((_, index) => <AuditMetric key={index} loading />)
          : stats.map((stat) => <AuditMetric key={stat.label} {...stat} />)}
      </section>

      <section aria-label="Filter audit events" className="rounded-xl border border-border bg-card p-3">
        <div className="grid items-end gap-2.5 sm:grid-cols-2 xl:grid-cols-[minmax(240px,1fr)_170px_240px_auto]">
          <label className="block sm:col-span-2 xl:col-span-1">
            <span className="mb-1 block text-[12px] font-medium text-muted">Search</span>
            <span className="relative block">
              <Search
                size={14}
                strokeWidth={1.6}
                className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-muted"
                aria-hidden="true"
              />
              <input
                type="search"
                placeholder={
                  tab === 'seller'
                    ? 'Search admin, applicant, note…'
                    : tab === 'payment'
                      ? 'Search seller, order, reference…'
                      : tab === 'sessions'
                        ? 'Search seller, source, device…'
                        : tab === 'activity'
                          ? 'Search seller, product, store…'
                          : 'Search account, IP, device, place…'
                }
                value={search}
                onChange={(event) => {
                  setSearch(event.target.value)
                  setPage(0)
                }}
                className="h-9 w-full rounded-lg border border-border bg-card pl-8 pr-9 text-[12.5px] text-ink outline-none transition-colors placeholder:text-muted/70 focus:border-primary focus:ring-2 focus:ring-primary/15"
              />
              {search && (
                <button
                  type="button"
                  onClick={() => {
                    setSearch('')
                    setPage(0)
                  }}
                  aria-label="Clear search"
                  className="absolute right-1.5 top-1/2 inline-flex h-6 w-6 -translate-y-1/2 items-center justify-center rounded-md text-muted transition-colors hover:bg-canvas hover:text-ink"
                >
                  <X size={13} />
                </button>
              )}
            </span>
          </label>

          <label className="block">
            <span className="mb-1 block text-[12px] font-medium text-muted">Action</span>
            <select
              value={action}
              onChange={(event) => {
                setAction(event.target.value)
                setPage(0)
              }}
              className="h-9 w-full rounded-lg border border-border bg-card px-2.5 text-[12.5px] text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
            >
              {ACTION_OPTIONS[tab].map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>

          <div className="col-span-2 block xl:col-span-1">
            <span className="mb-1 block text-[12px] font-medium text-muted">Date</span>
            <DateRangePicker
              from={parseISODate(dateFrom)}
              to={parseISODate(dateTo)}
              onChange={(nextFrom, nextTo) => {
                setDateFrom(toISODate(nextFrom))
                setDateTo(toISODate(nextTo))
                setPage(0)
              }}
            />
          </div>

          {filtersActive && (
            <button
              type="button"
              onClick={clearFilters}
              className="inline-flex h-9 items-center justify-center gap-1 rounded-lg px-2.5 text-[12px] font-semibold text-muted transition-colors hover:bg-canvas hover:text-ink"
            >
              <X size={13} aria-hidden="true" /> Clear filters
            </button>
          )}
        </div>
      </section>

      {isLoading && <AuditSkeleton />}
      {isError && (
        <div className="rounded-xl border border-error/20 bg-card px-6 py-10 text-center">
          <p className="text-[14px] font-semibold text-ink">Could not load this trail</p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted">
            {error?.message ?? 'Could not load audit logs.'}
          </p>
        </div>
      )}

      {!isLoading && !isError && (
        <section className="overflow-hidden rounded-xl border border-border bg-card">
          <div className="px-4 py-3.5">
            <h2 className="text-[15px] font-bold text-ink">Events</h2>
            <p className="mt-0.5 text-[12px] text-muted">
              {total.toLocaleString('en-PH')} event{total === 1 ? '' : 's'} in this trail · newest first
            </p>
          </div>

          {rows.length === 0 ? (
            <div className="flex flex-col items-center border-t border-border px-6 py-16 text-center">
              <SearchX size={22} strokeWidth={1.5} className="text-muted" aria-hidden="true" />
              <p className="mt-2 text-[15px] font-semibold text-ink">
                {filtersActive ? 'No events match these filters' : 'No events in this trail yet'}
              </p>
              <p className="mt-1 max-w-sm text-[12.5px] leading-relaxed text-muted">
                {filtersActive
                  ? 'Search and filters apply to the loaded page. Try a wider date range or clear the filters.'
                  : 'New events will appear here as they are recorded.'}
              </p>
              {filtersActive && (
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
                <table className="w-full min-w-[760px] table-fixed text-left">
                  <colgroup>
                    <col className="w-[196px]" />
                    <col className="w-[220px]" />
                    <col />
                    <col className="w-[200px]" />
                    <col className="w-[44px]" />
                  </colgroup>
                  <thead className="border-y border-border bg-canvas/60">
                    <tr>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">When</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">{activeMeta.actor}</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">{activeMeta.subject}</th>
                      <th className="px-4 py-2 text-[12px] font-semibold text-muted">Action</th>
                      <th className="w-10 px-3 py-2">
                        <span className="sr-only">Open event</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {rows.map((row) => (
                      <tr
                        key={row.id}
                        onClick={() => setSelected(row)}
                        className="admin-list-item admin-list-row cursor-pointer"
                      >
                        <td className="whitespace-nowrap px-4 py-3 font-mono text-[11.5px] text-muted">
                          {formatAuditDateTime(row.at)}
                        </td>
                        <td className="max-w-[220px] px-4 py-3">
                          <p className="truncate text-[12.5px] font-semibold text-ink">{row.actor}</p>
                          {row.actorEmail && (
                            <p className="truncate text-[12px] text-muted">{row.actorEmail}</p>
                          )}
                        </td>
                        <td className="max-w-[240px] px-4 py-3">
                          <p className="truncate text-[12.5px] font-medium text-ink">{row.subject}</p>
                          {row.subjectEmail && (
                            <p className="truncate text-[12px] text-muted">{row.subjectEmail}</p>
                          )}
                          {tab === 'payment' && row.reference !== '—' && (
                            <p className="mt-0.5 text-[11.5px] text-muted/80">Ref {row.reference}</p>
                          )}
                        </td>
                        <td className="px-4 py-3">
                          <Badge label={humanize(row.action)} variant={toneFor(row.action, row)} dot />
                        </td>
                        <td className="px-3 py-3">
                          <button
                            type="button"
                            onClick={(event) => {
                              event.stopPropagation()
                              setSelected(row)
                            }}
                            aria-label={`Open event ${shortId(row.id)}`}
                            className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-muted/60 transition-colors hover:bg-canvas hover:text-ink"
                          >
                            <ChevronRight size={15} aria-hidden="true" />
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div className="divide-y divide-border border-t border-border lg:hidden">
                {rows.map((row) => (
                  <button
                    key={row.id}
                    type="button"
                    onClick={() => setSelected(row)}
                    className="admin-list-item admin-list-card block w-full px-4 py-3 text-left"
                  >
                    <span className="flex items-start justify-between gap-2">
                      <Badge label={humanize(row.action)} variant={toneFor(row.action, row)} dot />
                      <span className="shrink-0 text-right font-mono text-[11px] leading-relaxed text-muted">
                        {formatAuditDateTime(row.at)}
                      </span>
                    </span>
                    <span className="mt-2 block truncate text-[13px] font-semibold text-ink">
                      {row.actor}
                    </span>
                    {row.actorEmail && (
                      <span className="block truncate text-[12px] text-muted">{row.actorEmail}</span>
                    )}
                    <span className="mt-1 block truncate text-[12px] text-muted">
                      {row.subject}
                      {row.subjectEmail ? ` · ${row.subjectEmail}` : ''}
                      {tab === 'payment' && row.reference !== '—' ? ` · Ref ${row.reference}` : ''}
                    </span>
                  </button>
                ))}
              </div>

              {total > 0 && (
                <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-3">
                  <p className="text-[12px] text-muted">
                    <span className="font-semibold text-secondary">{rows.length}</span> row
                    {rows.length === 1 ? '' : 's'} on this page · {total.toLocaleString('en-PH')} event
                    {total === 1 ? '' : 's'} in trail
                  </p>
                  <div className="flex items-center gap-1">
                    <button
                      type="button"
                      disabled={page === 0}
                      onClick={() => setPage((current) => Math.max(0, current - 1))}
                      aria-label="Previous page"
                      className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-card text-muted transition-colors hover:border-primary/40 hover:text-ink disabled:cursor-not-allowed disabled:opacity-35"
                    >
                      <ChevronLeft size={14} />
                    </button>
                    <span className="px-2 font-mono text-[11px] text-muted">
                      {page + 1} / {pageCount}
                    </span>
                    <button
                      type="button"
                      disabled={page >= pageCount - 1}
                      onClick={() => setPage((current) => Math.min(pageCount - 1, current + 1))}
                      aria-label="Next page"
                      className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-card text-muted transition-colors hover:border-primary/40 hover:text-ink disabled:cursor-not-allowed disabled:opacity-35"
                    >
                      <ChevronRight size={14} />
                    </button>
                  </div>
                </div>
              )}
            </>
          )}
        </section>
      )}

      <section aria-label="Audit coverage" className="rounded-xl border border-border bg-card px-4 py-3.5">
        <p className="text-[12px] font-semibold text-ink">Coverage</p>
        <p className="mt-1 max-w-[900px] text-[12px] leading-relaxed text-muted">
          Covers seller application decisions, manual GCash decisions, sign-in security, seller
          sessions, and seller activity. Four trails are written server-side and cannot be edited from
          a client. Sessions are reported by the apps, so a missing sign-out means it was never
          logged. Live GoTrue events sit in per-account security diagnostics; suspensions still have
          no history.
        </p>
      </section>

      <Modal open={!!selected} onClose={() => setSelected(null)} title="Event detail" size="md">
        {selected && <AuditDetail row={selected} tab={tab} />}
      </Modal>
    </div>
  )
}

function AuditMetric({ label, value, scope, loading = false }) {
  return (
    <div className="bg-card px-3.5 py-3.5">
      {loading ? (
        <>
          <div className="h-3 w-20 animate-pulse rounded bg-canvas" />
          <div className="mt-2 h-6 w-14 animate-pulse rounded bg-canvas" />
          <div className="mt-1.5 h-3 w-16 animate-pulse rounded bg-canvas" />
        </>
      ) : (
        <>
          <p className="text-[12px] font-medium text-muted">{label}</p>
          <p className="mt-1.5 font-mono text-[24px] font-semibold leading-none tracking-tight text-ink tnum">
            {Number(value ?? 0).toLocaleString('en-PH')}
          </p>
          <p className="mt-1.5 text-[11.5px] text-muted/80">{scope}</p>
        </>
      )}
    </div>
  )
}

function AuditSkeleton() {
  return (
    <div className="overflow-hidden rounded-xl border border-border bg-card">
      <div className="px-4 py-3.5">
        <div className="h-4 w-20 animate-pulse rounded bg-canvas" />
        <div className="mt-1.5 h-3 w-40 animate-pulse rounded bg-canvas" />
      </div>
      <div className="border-y border-border bg-canvas/60 px-4 py-2.5">
        <div className="h-3 w-full animate-pulse rounded bg-sand" />
      </div>
      <div className="divide-y divide-border">
        {Array.from({ length: 6 }).map((_, index) => (
          <div key={index} className="flex items-center gap-4 px-4 py-3">
            <div className="h-3 w-28 animate-pulse rounded bg-canvas" />
            <div className="h-3 flex-1 animate-pulse rounded bg-canvas" />
            <div className="h-5 w-20 animate-pulse rounded-full bg-canvas" />
          </div>
        ))}
      </div>
    </div>
  )
}

function DetailRow({ label, value }) {
  if (value == null || value === '') return null
  return (
    <div className="grid grid-cols-[110px_1fr] gap-3 border-b border-border/70 py-2.5 last:border-0">
      <p className="text-[12px] text-muted">{label}</p>
      <p className="break-words text-right text-[13px] font-medium text-ink">{value}</p>
    </div>
  )
}

function AuditDetail({ row, tab }) {
  const meta = TRAIL_META[tab] ?? TRAIL_META.seller
  return (
    <div className="text-sm">
      <div className="mb-1 flex flex-wrap items-center gap-2 border-b border-border pb-3">
        <Badge label={humanize(row.action)} variant={toneFor(row.action, row)} dot />
        <span className="font-mono text-[11px] text-muted">#{shortId(row.id)}</span>
        <span className="text-[12px] text-muted">{formatAuditDateTime(row.at)}</span>
      </div>
      <DetailRow label={meta.actor} value={row.actorEmail ? `${row.actor} (${row.actorEmail})` : row.actor} />
      <DetailRow label={meta.subject} value={row.subjectEmail ? `${row.subject} (${row.subjectEmail})` : row.subject} />
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
