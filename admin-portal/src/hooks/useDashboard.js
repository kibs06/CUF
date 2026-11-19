import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

function startOfDay(d) {
  const c = new Date(d)
  c.setHours(0, 0, 0, 0)
  return c
}

/**
 * The timeframe the whole dashboard reads in.
 *
 * One window start — plus the equally long window immediately before it, for
 * the "vs prior" deltas — or `null` boundaries for Overall, which sets no
 * lower bound at all.
 */
export function dashboardWindow(period = 'week') {
  const definition = PAID_PERIODS.find((item) => item.key === period) ?? PAID_PERIODS[0]
  if (definition.days == null) {
    return { definition, days: null, start: null, prevStart: null, prevEnd: null }
  }
  const start = startOfDay(new Date(Date.now() - (definition.days - 1) * 86400000))
  return {
    definition,
    days: definition.days,
    start,
    prevStart: new Date(start.getTime() - definition.days * 86400000),
    prevEnd: start,
  }
}

export function useDashboardStats(period = 'week') {
  return useQuery({
    queryKey: ['dashboard-stats', period],
    queryFn: async () => {
      const window = dashboardWindow(period)
      const since = window.start ? window.start.toISOString() : null
      const prevSince = window.prevStart ? window.prevStart.toISOString() : null
      const prevUntil = window.prevEnd ? window.prevEnd.toISOString() : null

      const count = (table, apply) => {
        const query = supabase.from(table).select('*', { count: 'exact', head: true })
        return apply ? apply(query) : query
      }

      const [users, pending, products, orders, curOrders, prevOrders] = await Promise.all([
        count('profiles'),
        count('profiles', (q) => q.eq('seller_status', 'pending')),
        count('products'),
        count('orders'),
        count('orders', (q) => (since ? q.gte('created_at', since) : q)),
        prevSince
          ? count('orders', (q) => q.gte('created_at', prevSince).lt('created_at', prevUntil))
          : Promise.resolve(null),
      ])

      for (const result of [users, pending, products, orders, curOrders, prevOrders]) {
        if (result?.error) throw result.error
      }

      const current = curOrders?.count ?? 0
      const previous = prevOrders?.count ?? null

      return {
        totalUsers: users.count ?? 0,
        pendingApplications: pending.count ?? 0,
        totalProducts: products.count ?? 0,
        totalOrders: orders.count ?? 0,
        ordersWindow: current,
        ordersPrevWindow: previous,
        ordersDelta: previous == null ? null : current - previous,
        period: window.definition,
      }
    },
  })
}

/**
 * The windows the dashboard's total-paid figure can be read in.
 *
 * Rolling windows, not calendar ones: the rest of the dashboard already talks
 * in "last 7 days", and an admin checking "how much came in this week" means the
 * last seven days rather than a calendar week that may have started yesterday.
 */
export const PAID_PERIODS = [
  {
    key: 'week',
    label: 'Weekly',
    days: 7,
    hint: 'Money that arrived in the last 7 days.',
  },
  {
    key: 'month',
    label: 'Monthly',
    days: 30,
    hint: 'Money that arrived in the last 30 days.',
  },
  {
    key: 'quarter',
    label: 'Quarterly',
    days: 90,
    hint: 'Money that arrived in the last 90 days.',
  },
  {
    key: 'year',
    label: 'Annually',
    days: 365,
    hint: 'Money that arrived in the last 365 days.',
  },
  { key: 'all', label: 'Overall', days: null, hint: 'Every paid sale ever recorded.' },
]

const PAID_PAGE = 1000
const PAID_MAX_PAGES = 10

/**
 * Every paid sale, fetched once and bucketed in the browser.
 *
 * The dashboard needs three numbers from the same rows — this window, the
 * equally long window before it, and the all-time total — and switching periods
 * must not refetch, so the fetch is period-independent and `paidTotals` cuts it
 * up. PostgREST caps a response at 1000 rows, so the rows are paged until a
 * short page comes back; the cap is stated in the UI rather than silently
 * under-reporting a total.
 */
export function usePaidSalesLedger() {
  return useQuery({
    queryKey: ['dashboard-paid-sales', 'ledger'],
    queryFn: async () => {
      const rows = []
      for (let page = 0; page < PAID_MAX_PAGES; page += 1) {
        const { data, error } = await supabase
          .from('orders')
          .select('total_amount, created_at, payment_verified_at, source')
          .eq('payment_status', 'paid')
          .order('created_at', { ascending: false })
          .range(page * PAID_PAGE, page * PAID_PAGE + PAID_PAGE - 1)
        if (error) throw error
        rows.push(...(data ?? []))
        if (!data || data.length < PAID_PAGE) break
      }
      return rows
    },
    staleTime: 60_000,
  })
}

/** A till sale is `source = 'pos'`; everything else came through the app. */
function paidChannel(source) {
  return (source ?? '').toString().toLowerCase() === 'pos' ? 'pos' : 'online'
}

/** When the money arrived: the verification stamp, or the order date if none. */
function paidStamp(row) {
  const stamp = row.payment_verified_at ?? row.created_at
  const time = stamp ? new Date(stamp).getTime() : NaN
  return Number.isFinite(time) ? time : null
}

/**
 * Totals for one window, the window before it and all time, from the ledger.
 *
 * A sale belongs to the window its *money* arrived in — an order placed last
 * month and paid today is this week's income, not last month's. Rows with no
 * verification stamp (legacy/POS rows written before the column existed) fall
 * back to the order date so they still land somewhere. Rows with neither stamp
 * still count towards all time, since they are paid either way.
 */
export function paidTotals(rows, period = 'week', channels = { pos: true, online: true }) {
  const window = dashboardWindow(period)
  const start =
    window.days == null
      ? null
      : startOfDay(new Date(Date.now() - (window.days - 1) * 86400000)).getTime()
  const prevStart = start == null ? null : start - window.days * 86400000

  let total = 0
  let count = 0
  let previous = 0
  let previousCount = 0
  let allTime = 0
  let allTimeCount = 0

  for (const row of rows ?? []) {
    if (!channels[paidChannel(row.source)]) continue

    const amount = Number(row.total_amount) || 0
    allTime += amount
    allTimeCount += 1

    const stamp = paidStamp(row)
    if (stamp == null) continue
    if (start == null) {
      total += amount
      count += 1
    } else if (stamp >= start) {
      total += amount
      count += 1
    } else if (prevStart != null && stamp >= prevStart) {
      previous += amount
      previousCount += 1
    }
  }

  return {
    total,
    count,
    average: count ? total / count : 0,
    previous: window.days == null ? null : previous,
    previousCount,
    delta: window.days == null ? null : total - previous,
    allTime,
    allTimeCount,
    period: window.definition,
    capped: (rows?.length ?? 0) === PAID_PAGE * PAID_MAX_PAGES,
  }
}

/**
 * The dashboard's request table: refund requests and open reports, normalised
 * into one shape so they can share a table.
 *
 * Refunds lead because the customer's money is already with the platform and
 * someone has to send it back; reports follow, high priority first. The caller
 * only renders the first few rows, so they are capped here rather than fetching
 * whole queues.
 */
export function useRequestTable() {
  return useQuery({
    queryKey: ['dashboard-requests'],
    queryFn: async () => {
      const [reports, refunds] = await Promise.all([
        supabase
          .from('reports')
          .select(
            'id, type, category, custom_details, priority, status, created_at, profiles!reports_reporter_id_fkey(full_name, email)',
          )
          .in('status', ['pending', 'under_review'])
          .order('created_at', { ascending: false })
          .limit(50),
        supabase.rpc('admin_list_refund_owed', { p_include_refunded: false }),
      ])
      if (reports.error) throw reports.error
      if (refunds.error) throw refunds.error

      const refundRows = (refunds.data ?? [])
        .filter((row) => row.r_payment_status === 'refund_pending')
        .map((row) => ({
          id: `refund-${row.r_order_id}`,
          kind: 'refund',
          title: row.r_order_code ? `Order ${row.r_order_code}` : 'Refund owed',
          who: row.r_customer_name ?? 'Customer',
          email: null,
          amount: Number(row.r_total) || 0,
          status: 'Awaiting refund',
          critical: true,
          to: '/refunds',
          at: row.r_cancelled_at ?? row.r_proof_submitted_at ?? null,
        }))

      const reportRows = (reports.data ?? []).map((row) => ({
        id: `report-${row.id}`,
        kind: 'report',
        title: (row.category ?? row.type ?? 'Report').toString().replace(/_/g, ' '),
        who: row.profiles?.full_name ?? row.profiles?.email ?? 'Unknown reporter',
        email: row.profiles?.email ?? null,
        amount: null,
        status: (row.status ?? 'pending').toString().replace(/_/g, ' '),
        critical: row.priority === 'high',
        to: '/reports',
        at: row.created_at ?? null,
      }))

      return [...refundRows, ...reportRows]
        .sort(
          (a, b) =>
            (a.kind === 'refund' ? 0 : 1) - (b.kind === 'refund' ? 0 : 1) ||
            Number(b.critical) - Number(a.critical) ||
            new Date(b.at ?? 0).getTime() - new Date(a.at ?? 0).getTime(),
        )
    },
    refetchInterval: 60_000,
  })
}

export function useRecentPendingApplications(limit = 5) {
  return useQuery({
    queryKey: ['recent-pending-applications', limit],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name, email, seller_status, created_at, avatar_url')
        .eq('seller_status', 'pending')
        .order('created_at', { ascending: false })
        .limit(limit)

      if (error) throw error
      return data ?? []
    },
  })
}

export function useRecentOrders(limit = 6, period = 'week') {
  return useQuery({
    queryKey: ['recent-orders', limit, period],
    queryFn: async () => {
      const window = dashboardWindow(period)
      let query = supabase
        .from('orders')
        .select(
          'id, status, total_amount, created_at, profiles!orders_customer_id_fkey(full_name, email), stores(name)',
        )
        .order('created_at', { ascending: false })
        .limit(limit)
      if (window.start) query = query.gte('created_at', window.start.toISOString())

      const { data, error } = await query
      if (error) throw error
      return data ?? []
    },
  })
}

export function useOrderPipeline(period = 'week') {
  return useQuery({
    queryKey: ['order-pipeline', period],
    queryFn: async () => {
      const window = dashboardWindow(period)
      let query = supabase.from('orders').select('status')
      if (window.start) query = query.gte('created_at', window.start.toISOString())

      const { data, error } = await query
      if (error) throw error
      const rows = data ?? []
      const count = (list) => rows.filter((r) => list.includes((r.status ?? '').toLowerCase())).length
      return {
        needsAction: count(['pending', 'placed', 'confirmed']),
        inKitchen: count(['preparing', 'ready']),
        onTheWay: count(['shipped']),
        done: count(['received', 'delivered']),
      }
    },
  })
}

export function useOrdersSparkline(days = 14) {
  return useQuery({
    queryKey: ['orders-sparkline', days],
    queryFn: async () => {
      // The whole selected window for the plotted line, plus the equally long
      // window before it for the dashed comparison — the chart's caption names
      // the timeframe, so the line has to cover all of it rather than a slice.
      const from = new Date(Date.now() - (2 * days - 1) * 86400000)
      from.setHours(0, 0, 0, 0)

      const { data, error } = await supabase
        .from('orders')
        .select('created_at, total_amount')
        .gte('created_at', from.toISOString())
        .order('created_at', { ascending: true })

      if (error) throw error

      const buckets = []
      for (let i = 0; i < 2 * days; i++) {
        const key = new Date(Date.now() - (2 * days - 1 - i) * 86400000)
          .toISOString()
          .slice(0, 10)
        buckets.push({ date: key.slice(5), full: key, count: 0, revenue: 0 })
      }
      const byDay = Object.fromEntries(buckets.map((entry) => [entry.full, entry]))
      for (const order of data ?? []) {
        const target = byDay[order.created_at?.slice(0, 10)]
        if (target) {
          target.count += 1
          target.revenue += Number(order.total_amount) || 0
        }
      }

      const prev = buckets.slice(0, days)
      const cur = buckets.slice(days)

      return {
        current: cur,
        previous: prev,
        total: cur.reduce((s, e) => s + e.count, 0),
        totalRevenue: cur.reduce((s, e) => s + e.revenue, 0),
      }
    },
  })
}

export function useApproveSeller() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (userId) => {
      const { error } = await supabase
        .from('profiles')
        .update({ role: 'seller', seller_status: 'approved' })
        .eq('id', userId)
      if (error) throw error
      // Same mail as the applications queue: approving verifies the
      // applicant's business documents server-side, so lead with the badge
      // when the verdict came back verified. Fire-and-forget.
      const { data: docs } = await supabase
        .from('seller_business_docs')
        .select('verification_status')
        .eq('profile_id', userId)
        .maybeSingle()
      supabase.functions
        .invoke('send-approval-email', {
          body: {
            userId,
            outcome: 'approved',
            ...(docs?.verification_status === 'verified' ? { verified: true } : {}),
          },
        })
        .catch((err) => console.error('Approval email trigger failed:', err))
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['seller-applications'] })
      queryClient.invalidateQueries({ queryKey: ['recent-pending-applications'] })
      queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
    },
  })
}

export function useRejectSeller() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ userId, reason }) => {
      const update = { seller_status: 'rejected' }
      if (reason?.trim()) update.rejection_reason = reason.trim()
      const { error } = await supabase.from('profiles').update(update).eq('id', userId)
      if (error) throw error
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['seller-applications'] })
      queryClient.invalidateQueries({ queryKey: ['recent-pending-applications'] })
      queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
    },
  })
}
