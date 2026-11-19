import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Signed URL for a customer's return photo.
 *
 * Return photos live in their own private bucket, `return-proofs` — signing a
 * path there against `payment-proofs` is what produced "The screenshot could
 * not be signed" on every return row.
 */
export async function returnProofSignedUrl(path) {
  if (!path) return null
  const { data, error } = await supabase.storage.from('return-proofs').createSignedUrl(path, 3600)
  if (error) return null
  return data?.signedUrl ?? null
}

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
      const [owed, returns] = await Promise.all([
        supabase.rpc('admin_list_refund_owed', {
          p_include_refunded: includeRefunded,
        }),
        // Customer return requests live on `orders` (status `return_requested`,
        // written by the request_my_return RPC) and are the seller's call, not
        // a refund the admin owes yet — but they belong in the same queue so
        // nothing waiting on a decision is invisible here.
        supabase
          .from('orders')
          .select(
            'id, order_code, status, payment_status, total_amount, return_reason, return_details, return_requested_at, return_proof_path, return_proof_paths, created_at, profiles!orders_customer_id_fkey(full_name, email), stores(name)',
          )
          .eq('status', 'return_requested')
          .order('return_requested_at', { ascending: false }),
      ])
      if (owed.error) throw owed.error
      if (returns.error) throw returns.error

      const returnRows = (returns.data ?? []).map((row) => ({
        r_kind: 'return',
        r_order_id: row.id,
        r_order_code: row.order_code,
        r_payment_status: row.payment_status ?? 'paid',
        r_total: row.total_amount,
        r_customer_name: row.profiles?.full_name ?? row.profiles?.email ?? null,
        r_store_name: row.stores?.name ?? null,
        r_cancelled_at: null,
        r_requested_at: row.return_requested_at ?? row.created_at,
        r_return_reason: row.return_reason,
        r_return_details: row.return_details,
        // No decline-reason column on this database yet; the UI hides the line
        // when it is null, so a later migration lights it up for free.
        r_decline_reason: null,
        r_screenshot_path: row.return_proof_path,
        // 1-4 photos live in `return_proof_paths`; the legacy single column
        // mirrors the first one, so fall back to it for older orders.
        r_proof_paths:
          Array.isArray(row.return_proof_paths) && row.return_proof_paths.length > 0
            ? row.return_proof_paths
            : row.return_proof_path
              ? [row.return_proof_path]
              : [],
        r_reference: null,
        r_sender: null,
        r_amount_paid: null,
        r_attempt_no: null,
        r_rejection_reason: null,
        r_refund_reference: null,
        r_refunded_at: null,
      }))

      return [...returnRows, ...(owed.data ?? [])]
    },
    refetchInterval: 60_000,
  })
}

/**
 * Closes a customer return as a product replacement.
 *
 * House policy is replacement-only: an approved return is made good with a new
 * pair — on the spot in store, shipped when remote — never with money. So no
 * payment field is touched here (`payment_status` stays `paid`, nothing is
 * marked refunded) and no GCash reference is asked for. The seller app closes
 * the same transition by writing `status = 'replaced'`, and stamps
 * `refunded_at`, whose schema comment says it marks when the seller approved
 * the return (the column kept its legacy name).
 *
 * The `status = 'return_requested'` filter makes it a guarded transition — a
 * second click, or a stale card, changes nothing.
 */
export function useMarkReturnReplaced() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ orderId, notes }) => {
      const { data: userData } = await supabase.auth.getUser()
      const { data, error } = await supabase
        .from('orders')
        .update({
          status: 'replaced',
          refunded_at: new Date().toISOString(),
          refunded_by: userData?.user?.id ?? null,
          refund_note: notes || null,
        })
        .eq('id', orderId)
        .eq('status', 'return_requested')
        .select('id')

      if (error) throw error
      if (!data?.length) throw new Error('That return is no longer waiting — refresh the queue.')
      return data[0]
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['refund-owed'] })
      qc.invalidateQueries({ queryKey: ['orders'] })
    },
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
