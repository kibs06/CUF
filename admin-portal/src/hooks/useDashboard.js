import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

function startOfDay(d) {
  const c = new Date(d)
  c.setHours(0, 0, 0, 0)
  return c
}

export function useDashboardStats() {
  return useQuery({
    queryKey: ['dashboard-stats'],
    queryFn: async () => {
      const now = new Date()
      const curStart = startOfDay(new Date(now.getTime() - 6 * 86400000))
      const prevStart = startOfDay(new Date(now.getTime() - 13 * 86400000))
      const prevEnd = startOfDay(new Date(now.getTime() - 7 * 86400000))

      const [users, pending, products, orders, curOrders, prevOrders] = await Promise.all([
        supabase.from('profiles').select('*', { count: 'exact', head: true }),
        supabase
          .from('profiles')
          .select('*', { count: 'exact', head: true })
          .eq('seller_status', 'pending'),
        supabase.from('products').select('*', { count: 'exact', head: true }),
        supabase.from('orders').select('*', { count: 'exact', head: true }),
        supabase
          .from('orders')
          .select('total_amount, created_at')
          .gte('created_at', curStart.toISOString()),
        supabase
          .from('orders')
          .select('total_amount, created_at')
          .gte('created_at', prevStart.toISOString())
          .lt('created_at', prevEnd.toISOString()),
      ])

      if (users.error) throw users.error
      if (pending.error) throw pending.error
      if (products.error) throw products.error
      if (orders.error) throw orders.error
      if (curOrders.error) throw curOrders.error
      if (prevOrders.error) throw prevOrders.error

      const curRows = curOrders.data ?? []
      const prevRows = prevOrders.data ?? []
      const curRevenue = curRows.reduce((s, r) => s + (Number(r.total_amount) || 0), 0)
      const prevRevenue = prevRows.reduce((s, r) => s + (Number(r.total_amount) || 0), 0)

      return {
        totalUsers: users.count ?? 0,
        pendingApplications: pending.count ?? 0,
        totalProducts: products.count ?? 0,
        totalOrders: orders.count ?? 0,
        orders7d: curRows.length,
        ordersPrev7d: prevRows.length,
        ordersDelta: curRows.length - prevRows.length,
        revenue7d: curRevenue,
        revenueDelta: curRevenue - prevRevenue,
      }
    },
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

export function useRecentOrders(limit = 6) {
  return useQuery({
    queryKey: ['recent-orders', limit],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('orders')
        .select(
          'id, status, total_amount, created_at, profiles!orders_customer_id_fkey(full_name, email), stores(name)',
        )
        .order('created_at', { ascending: false })
        .limit(limit)

      if (error) throw error
      return data ?? []
    },
  })
}

export function useOrderPipeline() {
  return useQuery({
    queryKey: ['order-pipeline'],
    queryFn: async () => {
      const { data, error } = await supabase.from('orders').select('status')
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
      const since = new Date()
      since.setDate(since.getDate() - days + 1)
      since.setHours(0, 0, 0, 0)

      const { data, error } = await supabase
        .from('orders')
        .select('created_at, total_amount')
        .gte('created_at', since.toISOString())
        .order('created_at', { ascending: true })

      if (error) throw error

      const half = Math.ceil(days / 2)
      const cur = []
      const prev = []
      for (let i = 0; i < days; i++) {
        const d = new Date()
        d.setDate(d.getDate() - (days - 1 - i))
        const key = d.toISOString().slice(0, 10)
        const entry = { date: key.slice(5), full: key, count: 0, revenue: 0 }
        if (i < days - half) prev.push(entry)
        else cur.push({ ...entry })
      }
      const curMap = Object.fromEntries(cur.map((e) => [e.full, e]))
      const prevMap = Object.fromEntries(prev.map((e) => [e.full, e]))
      for (const order of data ?? []) {
        const key = order.created_at?.slice(0, 10)
        const target = curMap[key] ?? prevMap[key]
        if (target) {
          target.count += 1
          target.revenue += Number(order.total_amount) || 0
        }
      }

      return {
        current: cur,
        previous: prev,
        chart: [...prev.slice(-half), ...cur].map((e) => ({ date: e.date, count: e.count })),
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
