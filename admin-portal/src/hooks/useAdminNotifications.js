import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Counts the queues that need an admin's attention. Four head-only queries
 * keep the bell cheap: no rows cross the wire, only counts.
 */
export function useAdminNotifications() {
  return useQuery({
    queryKey: ['admin-notifications'],
    queryFn: async () => {
      const [reports, applications, modelRequests, orders] = await Promise.all([
        supabase
          .from('reports')
          .select('*', { count: 'exact', head: true })
          .eq('priority', 'high')
          .in('status', ['pending', 'under_review']),
        supabase
          .from('profiles')
          .select('*', { count: 'exact', head: true })
          .eq('seller_status', 'pending'),
        supabase
          .from('shoe_model_requests')
          .select('*', { count: 'exact', head: true })
          .in('status', ['requested', 'in_progress']),
        supabase
          .from('orders')
          .select('*', { count: 'exact', head: true })
          .in('status', ['pending', 'placed', 'confirmed']),
      ])

      if (reports.error) throw reports.error
      if (applications.error) throw applications.error
      if (modelRequests.error) throw modelRequests.error
      if (orders.error) throw orders.error

      return {
        reports: reports.count ?? 0,
        applications: applications.count ?? 0,
        modelRequests: modelRequests.count ?? 0,
        orders: orders.count ?? 0,
      }
    },
    staleTime: 30_000,
    refetchInterval: 60_000,
  })
}
