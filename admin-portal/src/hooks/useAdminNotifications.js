import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Counts the queues that need an admin's attention. Head-only queries keep
 * the bell cheap: no rows cross the wire, only counts.
 *
 * `gcashProofs` drives the badge on the GCash Verification rail entry — an
 * order sits in `payment_under_review` only while a customer's money may
 * already have landed, so it is the most time-sensitive queue here.
 */
export function useAdminNotifications() {
  return useQuery({
    queryKey: ['admin-notifications'],
    queryFn: async () => {
      const [reports, applications, modelRequests, orders, gcashProofs] =
        await Promise.all([
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
        supabase
          .from('orders')
          .select('*', { count: 'exact', head: true })
          .eq('payment_method', 'gcash')
          .eq('status', 'payment_under_review'),
        ])

      if (reports.error) throw reports.error
      if (applications.error) throw applications.error
      if (modelRequests.error) throw modelRequests.error
      if (orders.error) throw orders.error
      if (gcashProofs.error) throw gcashProofs.error

      return {
        reports: reports.count ?? 0,
        applications: applications.count ?? 0,
        modelRequests: modelRequests.count ?? 0,
        orders: orders.count ?? 0,
        gcashProofs: gcashProofs.count ?? 0,
      }
    },
    staleTime: 30_000,
    refetchInterval: 60_000,
  })
}

const FEED_COLUMNS = 'id, type, title, body, metadata, is_read, created_at'

/**
 * The per-admin message feed (`admin_notifications`).
 *
 * Unlike the queue counts above, these are real rows: a PayMongo mode guard
 * tripped, or a seller resubmitted business documents. RLS lets an admin read
 * and mark read only their OWN rows, so no user id is passed here — the
 * session's identity is the filter, and a demoted account stops seeing them.
 *
 * The unread count is a separate head-only query so the bell badge is exact
 * even when the list is capped at `limit`.
 */
export function useAdminNotificationFeed({ limit = 8 } = {}) {
  return useQuery({
    queryKey: ['admin-notification-feed', limit],
    queryFn: async () => {
      const [rows, unread] = await Promise.all([
        supabase
          .from('admin_notifications')
          .select(FEED_COLUMNS)
          .order('created_at', { ascending: false })
          .limit(limit),
        supabase
          .from('admin_notifications')
          .select('id', { count: 'exact', head: true })
          .eq('is_read', false),
      ])

      if (rows.error) throw rows.error
      if (unread.error) throw unread.error

      return { rows: rows.data ?? [], unread: unread.count ?? 0 }
    },
    staleTime: 15_000,
    refetchInterval: 60_000,
  })
}

/**
 * Mark one or many of the caller's notices read.
 *
 * The policy only permits the read flag on the caller's own rows, so a forged
 * id in the list simply updates nothing. The feed is invalidated afterwards
 * (not optimistically patched) so the badge always reflects the server.
 */
export function useMarkAdminNotificationRead() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (ids) => {
      const list = (Array.isArray(ids) ? ids : [ids]).filter(Boolean)
      if (list.length === 0) return 0
      const { error } = await supabase
        .from('admin_notifications')
        .update({ is_read: true })
        .in('id', list)
        .eq('is_read', false)
      if (error) throw error
      return list.length
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-notification-feed'] })
    },
  })
}
