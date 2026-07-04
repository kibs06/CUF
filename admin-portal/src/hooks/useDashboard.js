import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useDashboardStats() {
  return useQuery({
    queryKey: ['dashboard-stats'],
    queryFn: async () => {
      const [users, pending, products, orders] = await Promise.all([
        supabase.from('profiles').select('*', { count: 'exact', head: true }),
        supabase
          .from('profiles')
          .select('*', { count: 'exact', head: true })
          .eq('seller_status', 'pending'),
        supabase.from('products').select('*', { count: 'exact', head: true }),
        supabase.from('orders').select('*', { count: 'exact', head: true }),
      ])

      if (users.error) throw users.error
      if (pending.error) throw pending.error
      if (products.error) throw products.error
      if (orders.error) throw orders.error

      return {
        totalUsers: users.count ?? 0,
        pendingApplications: pending.count ?? 0,
        totalProducts: products.count ?? 0,
        totalOrders: orders.count ?? 0,
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

export function useRecentOrders(limit = 5) {
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

export function useOrdersSparkline(days = 7) {
  return useQuery({
    queryKey: ['orders-sparkline', days],
    queryFn: async () => {
      const since = new Date()
      since.setDate(since.getDate() - days + 1)
      since.setHours(0, 0, 0, 0)

      const { data, error } = await supabase
        .from('orders')
        .select('created_at')
        .gte('created_at', since.toISOString())
        .order('created_at', { ascending: true })

      if (error) throw error

      const counts = {}
      for (let i = 0; i < days; i++) {
        const d = new Date()
        d.setDate(d.getDate() - (days - 1 - i))
        const key = d.toISOString().slice(0, 10)
        counts[key] = 0
      }

      for (const order of data ?? []) {
        const key = order.created_at?.slice(0, 10)
        if (key && counts[key] !== undefined) counts[key] += 1
      }

      return Object.entries(counts).map(([date, count]) => ({
        date: date.slice(5),
        count,
      }))
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
