import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Orders that may be owed money back.
 *
 * A proof rejected three times cancels the order, but the customer's transfer
 * is already in the platform GCash account — so the row is `refund_pending`
 * rather than `failed`. This is the queue an admin works through by hand:
 * each row carries the reference, amount and screenshot of the attempt that
 * cancelled it, so the refund can be matched to a real transfer instead of
 * guessed from a name.
 */
export function useRefundOwed(includeRefunded = false) {
  return useQuery({
    queryKey: ['refund-owed', includeRefunded],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('admin_list_refund_owed', {
        p_include_refunded: includeRefunded,
      })
      if (error) throw error
      return data ?? []
    },
    refetchInterval: 60_000,
  })
}

/** Closes a refund with the GCash reference of the transfer that was sent. */
export function useMarkRefunded() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ orderId, reference, notes }) => {
      const { data, error } = await supabase.rpc('admin_mark_refund_refunded', {
        p_order_id: orderId,
        p_reference: reference,
        p_notes: notes || null,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['refund-owed'] })
    },
  })
}
