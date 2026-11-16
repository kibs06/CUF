import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  ArrowUpDown,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  RefreshCw,
  Search,
  ShieldCheck,
  Users as UsersIcon,
  X,
} from 'lucide-react'
import { useUsers } from '../hooks/useUsers.js'
import { useFailedLogins } from '../hooks/useFailedLogins.js'
import { useAuth } from '../hooks/useAuth.jsx'
import UserRow from '../components/users/UserRow.jsx'
import UserDetailModal from '../components/users/UserDetailModal.jsx'
import {
  ROLE_META,
  ROLE_ORDER,
  UserAvatar,
  accessState,
} from '../components/users/userMeta.jsx'

const PAGE_SIZE = 10

const STATUS_TABS = [
  { key: 'all', label: 'Any status', dot: 'bg-secondary' },
  { key: 'active', label: 'Active', dot: 'bg-accent' },
  { key: 'suspended', label: 'Suspended', dot: 'bg-error' },
  { key: 'locked', label: 'Locked', dot: 'bg-error' },
]

const SORT_OPTIONS = [
  { value: 'newest', label: 'Newest first' },
  { value: 'oldest', label: 'Oldest first' },
  { value: 'name', label: 'Name A–Z' },
  { value: 'role', label: 'Role' },
]

export default function Users() {
  const { data, isLoading, isError, error, refetch, isFetching } = useUsers()
  const {
    data: failedLogins = {},
    refetch: refetchLogins,
    isFetching: isFetchingLogins,
  } = useFailedLogins()
  const { profile } = useAuth()

  const [activeTab, setActiveTab] = useState('all')
  const [statusFilter, setStatusFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState('newest')
  const [page, setPage] = useState(1)
  const [selectedUser, setSelectedUser] = useState(null)
  const searchRef = useRef(null)

  const { all = [], customers = [], sellers = [], admins = [] } = data ?? {}

  const total = all.length
  const suspendedCount = all.filter((user) => user.suspended).length
  const lockedCount = all.filter(
    (user) => !user.suspended && failedLogins[user.id]?.status === 'locked',
  ).length
  const activeCount = Math.max(0, total - suspendedCount - lockedCount)
  const activePct = total > 0 ? Math.round((activeCount / total) * 100) : 0

  const now = Date.now()
  const newThisMonth = all.filter((user) => {
    const joined = new Date(user.created_at).getTime()
    return Number.isFinite(joined) && now - joined >= 0 && now - joined < 30 * 86_400_000
  }).length

  const sellerApproved = sellers.filter((user) => user.seller_status === 'approved').length
  const sellerPending = sellers.filter((user) => user.seller_status === 'pending').length
  const sellerRejected = sellers.filter((user) => user.seller_status === 'rejected').length

  const attentionUsers = useMemo(() => {
    const rank = (user) => {
      if (user.suspended) return 0
      if (failedLogins[user.id]?.status === 'locked') return 1
      return 2
    }
    return all
      .filter(
        (user) =>
          user.suspended ||
          failedLogins[user.id]?.status === 'locked' ||
          (failedLogins[user.id]?.attemptCount ?? 0) > 0,
      )
      .sort(
        (a, b) =>
          rank(a) - rank(b) ||
          (failedLogins[b.id]?.attemptCount ?? 0) -
            (failedLogins[a.id]?.attemptCount ?? 0),
      )
  }, [all, failedLogins])

  const filteredUsers = useMemo(() => {
    const term = search.trim().toLowerCase()
    let out = all

    if (activeTab !== 'all') out = out.filter((user) => user.role === activeTab)
    if (statusFilter !== 'all') {
      out = out.filter(
        (user) => accessState(user, failedLogins[user.id]).filter === statusFilter,
      )
    }
    if (term) {
      out = out.filter((user) =>
        `${user.full_name ?? ''} ${user.email ?? ''}`.toLowerCase().includes(term),
      )
    }

    return [...out].sort((a, b) => {
      if (sort === 'name') {
        return (a.full_name || a.email || '').localeCompare(b.full_name || b.email || '')
      }
      if (sort === 'role') {
        return (
          (ROLE_ORDER[a.role] ?? 9) - (ROLE_ORDER[b.role] ?? 9) ||
          (a.full_name || a.email || '').localeCompare(b.full_name || b.email || '')
        )
      }
      const aJoined = new Date(a.created_at).getTime() || 0
      const bJoined = new Date(b.created_at).getTime() || 0
      return sort === 'oldest' ? aJoined - bJoined : bJoined - aJoined
    })
  }, [all, activeTab, statusFilter, search, sort, failedLogins])

  useEffect(() => {
    setPage(1)
  }, [activeTab, statusFilter, search, sort])

  useEffect(() => {
    const onKeyDown = (event) => {
      const tag = event.target?.tagName
      if (
        event.key === '/' &&
        !event.metaKey &&
        !event.ctrlKey &&
        !['INPUT', 'TEXTAREA', 'SELECT'].includes(tag)
      ) {
        event.preventDefault()
        searchRef.current?.focus()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])

  const pageCount = Math.max(1, Math.ceil(filteredUsers.length / PAGE_SIZE))
  const safePage = Math.min(page, pageCount)
  const pageStart = (safePage - 1) * PAGE_SIZE
  const pageUsers = filteredUsers.slice(pageStart, pageStart + PAGE_SIZE)
  const rangeStart = filteredUsers.length === 0 ? 0 : pageStart + 1
  const rangeEnd = Math.min(pageStart + PAGE_SIZE, filteredUsers.length)
  const isRefreshing = isFetching || isFetchingLogins

  const roleTabs = [
    { key: 'all', label: 'All accounts', Icon: UsersIcon, count: total },
    {
      key: 'customer',
      label: 'Customers',
      Icon: ROLE_META.customer.Icon,
      count: customers.length,
      hex: ROLE_META.customer.hex,
    },
    {
      key: 'seller',
      label: 'Sellers',
      Icon: ROLE_META.seller.Icon,
      count: sellers.length,
      hex: ROLE_META.seller.hex,
    },
    {
      key: 'admin',
      label: 'Admins',
      Icon: ROLE_META.admin.Icon,
      count: admins.length,
      hex: ROLE_META.admin.hex,
    },
  ]

  const roleRows = [
    { ...ROLE_META.customer, key: 'customer', label: 'Customers', count: customers.length },
    { ...ROLE_META.seller, key: 'seller', label: 'Sellers', count: sellers.length },
    { ...ROLE_META.admin, key: 'admin', label: 'Admins', count: admins.length },
  ]

  const clearFilters = () => {
    setActiveTab('all')
    setStatusFilter('all')
    setSearch('')
    setSort('newest')
    setPage(1)
    searchRef.current?.focus()
  }

  if (isLoading) return <UsersSkeleton />

  if (isError) {
    return (
      <div className="rounded-xl border border-error/20 bg-white p-10 text-center">
        <span className="mx-auto flex h-11 w-11 items-center justify-center rounded-lg bg-errorSoft text-error">
          <AlertTriangle size={20} />
        </span>
        <h2 className="mt-3 text-[16px] font-bold text-ink">The directory didn’t load.</h2>
        <p className="mt-1 text-sm text-muted">{error?.message ?? 'Please try again.'}</p>
        <button
          type="button"
          onClick={() => refetch()}
          className="mt-4 rounded-xl bg-secondary px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-primaryDeep"
        >
          Try again
        </button>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* Account summary */}
      <section
        aria-label="Account summary"
        className="overflow-hidden rounded-xl border border-border bg-white"
      >
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3">
          <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
            <h2 className="text-[15px] font-bold text-ink">Accounts</h2>
            <p className="text-[12px] text-muted">
              {total} total · {newThisMonth} joined in 30 days
            </p>
          </div>
          <button
            type="button"
            onClick={() => {
              refetch()
              refetchLogins()
            }}
            disabled={isRefreshing}
            aria-label="Refresh accounts"
            className="inline-flex h-8 w-8 shrink-0 items-center justify-center gap-1.5 rounded-lg border border-border bg-white text-[12px] font-semibold text-secondary transition-colors hover:bg-canvas disabled:opacity-50 sm:w-auto sm:px-2.5"
          >
            <RefreshCw
              size={13}
              className={isRefreshing ? 'animate-spin' : ''}
              aria-hidden="true"
            />
            <span className="hidden sm:inline">{isRefreshing ? 'Refreshing' : 'Refresh'}</span>
          </button>
        </div>

        <div className="grid grid-cols-2 gap-px bg-border lg:grid-cols-4">
          <SummaryStat
            label="Total accounts"
            value={total}
            caption="Across every role"
          />
          <SummaryStat
            label="Active access"
            value={activeCount}
            caption={`${activePct}% of all accounts`}
          />
          <SummaryStat
            label="Sellers"
            value={sellers.length}
            caption={`${sellerApproved} approved${sellerPending > 0 ? ` · ${sellerPending} pending` : ''}${sellerRejected > 0 ? ` · ${sellerRejected} rejected` : ''}`}
          />
          <SummaryStat
            label="Restricted"
            value={suspendedCount + lockedCount}
            caption={`${suspendedCount} suspended · ${lockedCount} locked`}
            alert={suspendedCount + lockedCount > 0}
          />
        </div>
      </section>

      <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_300px]">
        {/* Directory */}
        <section className="overflow-hidden rounded-xl border border-border bg-white">
          <div className="border-b border-border px-4 py-4 sm:px-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="w-full sm:w-auto">
                <h2 className="text-[15px] font-bold text-ink">Directory</h2>
                <p className="mt-0.5 text-[12px] text-muted">
                  {filteredUsers.length === total
                    ? `${total} people`
                    : `${filteredUsers.length} of ${total} people`}
                </p>
              </div>

              <div className="flex w-full flex-wrap items-center gap-2 sm:w-auto sm:flex-none">
                <div className="relative min-w-0 flex-1 sm:w-[238px] sm:flex-none">
                  <label htmlFor="user-search" className="sr-only">
                    Search accounts
                  </label>
                  <Search
                    size={14}
                    className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted"
                  />
                  <input
                    id="user-search"
                    ref={searchRef}
                    type="text"
                    inputMode="search"
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    placeholder="Search accounts"
                    className="h-9 w-full rounded-xl border border-border bg-white pl-9 pr-9 text-[13px] text-ink outline-none transition-colors placeholder:text-muted/70 focus:border-primary focus:ring-2 focus:ring-primary/15"
                  />
                  {search ? (
                    <button
                      type="button"
                      onClick={() => {
                        setSearch('')
                        searchRef.current?.focus()
                      }}
                      aria-label="Clear search"
                      className="absolute right-2 top-1/2 -translate-y-1/2 rounded-md p-1 text-muted transition-colors hover:bg-canvas hover:text-ink"
                    >
                      <X size={13} />
                    </button>
                  ) : (
                    <kbd className="pointer-events-none absolute right-2.5 top-1/2 hidden -translate-y-1/2 rounded border border-border bg-canvas px-1.5 py-0.5 font-mono text-[10px] text-muted sm:block">
                      /
                    </kbd>
                  )}
                </div>

                <div className="relative w-[136px] sm:w-[148px]">
                  <label htmlFor="user-sort" className="sr-only">
                    Sort accounts
                  </label>
                  <ArrowUpDown
                    size={13}
                    className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted"
                  />
                  <select
                    id="user-sort"
                    value={sort}
                    onChange={(event) => setSort(event.target.value)}
                    className="h-9 w-full appearance-none rounded-xl border border-border bg-white pl-8 pr-7 text-[12px] font-semibold text-secondary outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/15"
                  >
                    {SORT_OPTIONS.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </select>
                  <ChevronDown
                    size={12}
                    className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-muted"
                  />
                </div>
              </div>
            </div>

            <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
              <div
                role="group"
                aria-label="Filter by role"
                className="flex max-w-full flex-wrap items-center gap-1 rounded-xl border border-border bg-canvas p-1"
              >
                {roleTabs.map((tab) => {
                  const Icon = tab.Icon
                  const active = activeTab === tab.key
                  return (
                    <button
                      key={tab.key}
                      type="button"
                      onClick={() => setActiveTab(tab.key)}
                      aria-pressed={active}
                      className={`inline-flex h-8 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-lg px-2.5 text-[12px] font-semibold transition-colors ${
                        active
                          ? 'bg-white text-ink shadow-sm ring-1 ring-border'
                          : 'text-muted hover:bg-white/60 hover:text-ink'
                      }`}
                    >
                      <Icon
                        size={13}
                        strokeWidth={2.2}
                        style={active && tab.hex ? { color: tab.hex } : undefined}
                      />
                      {tab.label}
                      <span
                        className={`rounded-full px-1.5 py-0.5 font-mono text-[11px] font-semibold ${
                          active ? 'bg-canvas text-secondary' : 'bg-white text-muted'
                        }`}
                      >
                        {tab.count}
                      </span>
                    </button>
                  )
                })}
              </div>

              <div className="flex items-center gap-1.5">
                <span className="hidden text-[12px] font-semibold text-muted lg:inline">
                  Status
                </span>
                <div
                  role="group"
                  aria-label="Filter by status"
                  className="flex flex-wrap items-center gap-0.5 rounded-xl border border-border bg-white p-1"
                >
                  {STATUS_TABS.map((status) => {
                    const active = statusFilter === status.key
                    const urgent = status.key === 'suspended' || status.key === 'locked'
                    return (
                      <button
                        key={status.key}
                        type="button"
                        onClick={() => setStatusFilter(status.key)}
                        aria-pressed={active}
                        className={`inline-flex h-7 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 text-[11px] font-semibold transition-colors ${
                          active
                            ? urgent
                              ? 'bg-error text-white'
                              : 'bg-secondary text-white'
                            : 'text-muted hover:bg-canvas hover:text-ink'
                        }`}
                      >
                        <span
                          className={`h-1.5 w-1.5 rounded-full ${
                            active ? 'bg-white/80' : status.dot
                          }`}
                          aria-hidden="true"
                        />
                        {status.label}
                      </button>
                    )
                  })}
                </div>
              </div>
            </div>
          </div>

          <div className="hidden grid-cols-[minmax(0,1fr)_170px_112px_44px] gap-4 border-b border-border bg-canvas/60 px-5 py-2 md:grid">
            <span className="text-[12px] font-semibold text-muted">Person</span>
            <span className="text-[12px] font-semibold text-muted">Role &amp; access</span>
            <span className="text-[12px] font-semibold text-muted">Joined</span>
            <span className="sr-only">Actions</span>
          </div>

          {filteredUsers.length === 0 ? (
            <EmptyDirectory onClear={clearFilters} />
          ) : (
            <div role="list" className="divide-y divide-[#F1EAE2]">
              {pageUsers.map((user) => (
                <UserRow
                  key={user.id}
                  user={user}
                  lockout={failedLogins[user.id]}
                  onView={setSelectedUser}
                  isSelf={profile?.id === user.id}
                />
              ))}
            </div>
          )}

          {filteredUsers.length > 0 && (
            <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-3 sm:px-5">
              <p className="text-[12px] text-muted">
                Showing{' '}
                <span className="font-semibold text-secondary">
                  {rangeStart}–{rangeEnd}
                </span>{' '}
                of {filteredUsers.length}
              </p>
              {pageCount > 1 && (
                <div className="flex items-center gap-1">
                  <button
                    type="button"
                    onClick={() => setPage((current) => Math.max(1, current - 1))}
                    disabled={safePage === 1}
                    aria-label="Previous page"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-white text-muted transition-colors hover:border-primary/40 hover:text-ink disabled:cursor-not-allowed disabled:opacity-35"
                  >
                    <ChevronLeft size={14} />
                  </button>
                  <span className="px-2 font-mono text-[11px] text-muted">
                    {safePage} / {pageCount}
                  </span>
                  <button
                    type="button"
                    onClick={() => setPage((current) => Math.min(pageCount, current + 1))}
                    disabled={safePage === pageCount}
                    aria-label="Next page"
                    className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-white text-muted transition-colors hover:border-primary/40 hover:text-ink disabled:cursor-not-allowed disabled:opacity-35"
                  >
                    <ChevronRight size={14} />
                  </button>
                </div>
              )}
            </div>
          )}
        </section>

        {/* Context rail */}
        <aside className="space-y-4 xl:sticky xl:top-4 xl:self-start">
          <section className="rounded-xl border border-border bg-white p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-[14px] font-bold text-ink">Account mix</h2>
                <p className="mt-0.5 text-[12px] text-muted">Who makes up the directory.</p>
              </div>
              <span className="rounded-full bg-canvas px-2 py-1 font-mono text-[11px] font-semibold text-secondary ring-1 ring-border">
                {total}
              </span>
            </div>

            <div className="mt-4 flex h-2 overflow-hidden rounded-full bg-canvas ring-1 ring-inset ring-border/70">
              {roleRows.map((row) =>
                row.count > 0 ? (
                  <span
                    key={row.key}
                    className="h-full"
                    style={{
                      width: `${(row.count / (total || 1)) * 100}%`,
                      backgroundColor: row.hex,
                    }}
                  />
                ) : null,
              )}
            </div>

            <div className="mt-3 space-y-0.5">
              {roleRows.map((row) => (
                <button
                  key={row.key}
                  type="button"
                  onClick={() => setActiveTab(row.key)}
                  aria-label={`Show ${row.label.toLowerCase()}`}
                  className="flex w-full items-center gap-2 rounded-lg px-1.5 py-1.5 text-left transition-colors hover:bg-canvas"
                >
                  <span
                    className="h-2 w-2 rounded-full"
                    style={{ backgroundColor: row.hex }}
                    aria-hidden="true"
                  />
                  <span className="flex-1 text-[12.5px] font-medium text-secondary">
                    {row.label}
                  </span>
                  <span className="font-mono text-[12px] text-muted">{row.count}</span>
                  <span className="w-9 text-right font-mono text-[11px] text-muted">
                    {total > 0 ? Math.round((row.count / total) * 100) : 0}%
                  </span>
                </button>
              ))}
            </div>
          </section>

          <section className="rounded-xl border border-border bg-white p-4">
            <div className="flex items-start gap-3">
              <span
                className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-lg ${
                  attentionUsers.length > 0
                    ? 'bg-pendingSoft text-pending'
                    : 'bg-accentSoft text-accent'
                }`}
              >
                {attentionUsers.length > 0 ? (
                  <AlertTriangle size={16} />
                ) : (
                  <ShieldCheck size={16} />
                )}
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <h2 className="text-[14px] font-bold text-ink">Security watch</h2>
                  <span
                    className={`rounded-full px-2 py-0.5 font-mono text-[11px] font-bold ${
                      attentionUsers.length > 0
                        ? 'bg-pendingSoft text-pending'
                        : 'bg-accentSoft text-accent'
                    }`}
                  >
                    {attentionUsers.length > 0 ? attentionUsers.length : 'Clear'}
                  </span>
                </div>
                <p className="mt-0.5 text-[12px] text-muted">Suspended, locked or repeated failures.</p>
              </div>
            </div>

            {attentionUsers.length > 0 ? (
              <ul className="mt-2 divide-y divide-border">
                {attentionUsers.slice(0, 4).map((user) => {
                  const reason = attentionReason(user, failedLogins[user.id])
                  return (
                    <li key={user.id}>
                      <button
                        type="button"
                        onClick={() => setSelectedUser(user)}
                        className="admin-list-item admin-list-card flex w-full items-center gap-2.5 py-2.5 text-left hover:text-primary"
                      >
                        <UserAvatar user={user} size="sm" />
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-[13px] font-semibold text-ink">
                            {user.full_name || 'Unnamed user'}
                          </span>
                          <span className={`block truncate text-[12px] font-medium ${reason.tone}`}>
                            {reason.label}
                          </span>
                        </span>
                        <ChevronRight size={13} className="shrink-0 text-muted/50" />
                      </button>
                    </li>
                  )
                })}
              </ul>
            ) : (
              <div className="mt-3 flex items-start gap-2">
                <ShieldCheck size={15} className="mt-0.5 shrink-0 text-accent" />
                <p className="text-[12px] leading-relaxed text-secondary">
                  No suspended accounts, locked sign-ins, or failed attempts.
                </p>
              </div>
            )}

            {attentionUsers.length > 4 && (
              <p className="mt-2 text-[12px] text-muted">
                +{attentionUsers.length - 4} more in the directory
              </p>
            )}
          </section>
        </aside>
      </div>

      <UserDetailModal user={selectedUser} onClose={() => setSelectedUser(null)} />
    </div>
  )
}

function SummaryStat({ label, value, caption, alert = false }) {
  return (
    <div className="bg-white px-4 py-4">
      <p className="text-[12px] font-medium text-muted">{label}</p>
      <p
        className={`mt-1.5 font-mono text-[24px] font-semibold leading-none tracking-tight tnum ${
          alert ? 'text-error' : 'text-ink'
        }`}
      >
        {value}
      </p>
      <p className="mt-2 text-[12px] leading-relaxed text-muted">{caption}</p>
    </div>
  )
}

function attentionReason(user, lockout) {
  if (user.suspended) return { label: 'Suspended account', tone: 'text-error' }
  if (lockout?.status === 'locked') return { label: 'Sign-in locked', tone: 'text-error' }
  const attempts = Number(lockout?.attemptCount) || 0
  return {
    label: `${attempts} failed attempt${attempts === 1 ? '' : 's'}`,
    tone: 'text-pending',
  }
}

function EmptyDirectory({ onClear }) {
  return (
    <div className="flex flex-col items-center px-6 py-14 text-center">
      <span className="flex h-11 w-11 items-center justify-center rounded-lg bg-canvas text-muted ring-1 ring-border">
        <Search size={19} />
      </span>
      <p className="mt-3 text-[16px] font-bold text-ink">No accounts match that view</p>
      <p className="mt-1 max-w-sm text-[12.5px] text-muted">
        Try a different name, role or status — or reset the directory.
      </p>
      <button
        type="button"
        onClick={onClear}
        className="mt-4 rounded-lg bg-secondary px-3.5 py-2 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep"
      >
        Clear filters
      </button>
    </div>
  )
}

function UsersSkeleton() {
  return (
    <div className="space-y-4">
      <div className="h-[116px] animate-pulse rounded-xl border border-border bg-white" />
      <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_300px]">
        <div className="overflow-hidden rounded-xl border border-border bg-white">
          <div className="border-b border-border p-4 sm:p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="h-5 w-28 animate-pulse rounded bg-[#E8DDD5]" />
              <div className="flex gap-2">
                <div className="h-9 w-52 animate-pulse rounded-lg bg-[#E8DDD5]" />
                <div className="h-9 w-36 animate-pulse rounded-lg bg-[#E8DDD5]" />
              </div>
            </div>
            <div className="mt-3 h-9 w-full animate-pulse rounded-lg bg-[#E8DDD5]" />
          </div>
          <div className="divide-y divide-border">
            {Array.from({ length: 7 }).map((_, index) => (
              <div key={index} className="flex items-center gap-3 px-4 py-3 md:px-5">
                <div className="h-10 w-10 shrink-0 animate-pulse rounded-xl bg-[#E8DDD5]" />
                <div className="flex-1 space-y-2">
                  <div className="h-3 w-28 animate-pulse rounded bg-[#E8DDD5]" />
                  <div className="h-2.5 w-40 animate-pulse rounded bg-[#E8DDD5]" />
                </div>
                <div className="h-5 w-16 animate-pulse rounded-full bg-[#E8DDD5]" />
              </div>
            ))}
          </div>
        </div>
        <div className="space-y-4">
          {[0, 1].map((index) => (
            <div
              key={index}
              className="h-36 animate-pulse rounded-xl border border-border bg-white"
            />
          ))}
        </div>
      </div>
    </div>
  )
}
