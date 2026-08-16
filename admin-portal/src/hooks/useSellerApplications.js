import { useEffect } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useSellerApplications(status = 'pending') {
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['seller-applications', status],
    queryFn: async () => {
      // Every field the application review modal renders: identity docs,
      // community proof, personal details + location, business docs,
      // store name/description/tags and the store photos.
      let q = supabase
        .from('profiles')
        .select(
          'id, full_name, email, seller_status, created_at, avatar_url, role, phone, ' +
            'id_type, id_document_url, selfie_url, cufmai_member_id, barangay_proof_url, ' +
            'birthday, gender, store_location, store_tags, ' +
            'store_name, store_description, store_front_url, product_photo_urls, rejection_reason, ' +
            'seller_business_docs(id, dti_cert_url, bir_cor_url, permit_url, verification_status)',
        )
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

// Fire-and-forget: email the applicant the admin's decision via the
// send-approval-email edge function (Gmail SMTP). Runs after the DB update
// succeeds; a failed email must never fail the approval/rejection itself.
const triggerApprovalEmail = (userId, outcome, reason) => {
  supabase.functions
    .invoke('send-approval-email', {
      body: { userId, outcome, ...(reason?.trim() ? { rejectionReason: reason.trim() } : {}) },
    })
    .catch((err) => console.error('Approval email trigger failed:', err))
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
      triggerApprovalEmail(userId, 'approved')
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
      triggerApprovalEmail(userId, 'rejected', reason)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['seller-applications'] })
      queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
    },
  })
}
