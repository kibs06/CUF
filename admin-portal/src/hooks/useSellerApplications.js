import { useEffect } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useSellerApplications(status = 'pending') {
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['seller-applications', status],
    queryFn: async () => {
      let q = supabase
        .from('profiles')
        .select('id, full_name, email, seller_status, created_at, avatar_url, role')
        .order('created_at', { ascending: false })

      if (status !== 'all') {
        q = q.eq('seller_status', status)
      } else {
        q = q.in('seller_status', ['pending', 'approved', 'rejected'])
      }

      const { data, error } = await q
      if (error) throw error
      return data ?? []
    },
  })

  useEffect(() => {
    const channel = supabase
      .channel('seller-applications')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'profiles',
          filter: 'seller_status=eq.pending',
        },
        () => {
          queryClient.invalidateQueries({ queryKey: ['seller-applications'] })
          queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] })
        },
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [queryClient])

  return query
}

export function useApproveApplication() {
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
      queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
    },
  })
}

export function useRejectApplication() {
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
      queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
    },
  })
}
