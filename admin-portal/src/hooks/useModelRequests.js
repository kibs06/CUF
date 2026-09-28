import { useEffect } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { toPortalError } from '../lib/errors.js'

// ─── The queue ─────────────────────────────────────────────────────
//
// The same embed the Flutter admin queue reads
// (`lib/services/shoe_model_request_service.dart`), so both surfaces show the
// same two names beside a row instead of one of them showing a bare uuid.
const QUEUE_SELECT =
  '*, products!shoe_model_requests_product_id_fkey(name), ' +
  'stores!shoe_model_requests_store_id_fkey(name)'

// The five states the table's CHECK admits.
export const REQUEST_STATUS = {
  REQUESTED: 'requested',
  IN_PROGRESS: 'in_progress',
  FULFILLED: 'fulfilled',
  DECLINED: 'declined',
  CANCELLED: 'cancelled',
}

// The two groupings the tabs use. Written down once, here, because the RPCs and
// the Flutter screen bucket them the same way (Waiting / Fulfilled / Closed) and
// a second opinion about which state belongs where would put an ask in two
// places at once.
export const OPEN_STATUSES = [REQUEST_STATUS.REQUESTED, REQUEST_STATUS.IN_PROGRESS]
export const CLOSED_STATUSES = [REQUEST_STATUS.DECLINED, REQUEST_STATUS.CANCELLED]

export function useModelRequests() {
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['model-requests'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('shoe_model_requests')
        .select(QUEUE_SELECT)
        .order('created_at', { ascending: false })

      // Wrapped, not re-thrown bare: the CODE on this object is what decides
      // whether the page says "the database is behind this build" or "your
      // session expired", and a `new Error(error.message)` copy would throw it
      // away. See `lib/errors.js`.
      if (error) throw toPortalError(error, 'Could not load the model-request queue.')
      return data ?? []
    },
  })

  // Live updates are a nicety here, not a correctness requirement: if the table
  // is not in the realtime publication this channel simply never fires, and the
  // page still shows what it fetched. The queue's real value is that a model the
  // team just published can be closed against straight away, which a manual
  // refresh also covers.
  useEffect(() => {
    const channel = supabase
      .channel('model-requests')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'shoe_model_requests' },
        () => queryClient.invalidateQueries({ queryKey: ['model-requests'] }),
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [queryClient])

  return query
}

// ─── The model picker ──────────────────────────────────────────────

// Every model row a product has, newest version first — the picker's source.
//
// Deliberately NOT filtered to `active`: seeing that the product's only model is
// still a `draft` is the explanation for why "close as done" cannot proceed,
// whereas a filter would return an empty list, which reads as "nothing uploaded".
export function useProductModels(productId) {
  return useQuery({
    queryKey: ['product-models', productId],
    enabled: !!productId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('product_models')
        .select('id, status, version, authored_length_mm, authored_size_eu')
        .eq('product_id', productId)
        .order('version', { ascending: false })

      if (error) throw toPortalError(error, 'Could not read that product’s models.')
      return data ?? []
    },
  })
}

// ─── The three closing RPCs ────────────────────────────────────────

// ⚠️ These RPCs signal a business refusal by RETURNING `{success:false}` — a row
// somebody else already claimed, a model that is still a draft, a decline re-run
// on a closed ask — and only *raise* on an authorisation failure. So `error ===
// null` does not mean it worked, and a missing body is not success either: the
// Flutter side keeps the same rule (`ShoeModelRequestOutcome.fromRpc`, where a
// null body is explicitly not success), and this is that rule in JS.
//
// The two halves fail differently and are kept different:
//   * a RAISED error carries a code, and the code decides what to say — the
//     admin guards raise 42501 deliberately, and a stale database answers 42804
//     or PGRST202 long before the request gets anywhere. Those are wrapped, not
//     re-worded, so the code survives to the page.
//   * a RETURNED refusal is the database's own sentence about this exact ask
//     ("somebody has already taken it"), which is already the right thing to
//     show and must not be replaced by a generic one.
const readOutcome = (data, error, fallback) => {
  if (error) throw toPortalError(error, fallback)
  if (!data || data.success !== true) {
    throw toPortalError(new Error(data?.message ?? fallback), fallback)
  }
  return data
}

const invalidateQueue = (qc) => {
  qc.invalidateQueries({ queryKey: ['model-requests'] })
  qc.invalidateQueries({ queryKey: ['dashboard-stats'] })
}

// Take an ask (`requested` → `in_progress`), so the queue says whose desk it is
// on. Admin-only inside the RPC.
export function useClaimModelRequest() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (requestId) => {
      const { data, error } = await supabase.rpc('claim_shoe_model_request', {
        p_request_id: requestId,
      })
      return readOutcome(data, error, 'That request could not be claimed.')
    },
    onSuccess: () => invalidateQueue(qc),
  })
}

// Close an ask as done, against a model that exists, belongs to THIS product and
// is `active` — the RPC refuses anything else, and the table's own CHECK refuses
// `fulfilled` with a NULL `model_id`. There is no way to close an ask by typing
// a status, which is the property this whole flow exists to keep.
export function useFulfilModelRequest() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ requestId, modelId, note }) => {
      const { data, error } = await supabase.rpc('fulfil_shoe_model_request', {
        p_request_id: requestId,
        p_model_id: modelId,
        ...(note?.trim() ? { p_admin_note: note.trim() } : {}),
      })
      return readOutcome(data, error, 'That request could not be closed.')
    },
    onSuccess: () => invalidateQueue(qc),
  })
}

// Refuse the ask, with the reason the seller reads. The page will not send this
// without one (the Flutter screen does the same), because a decline with no
// reason leaves the seller with nothing to act on.
export function useDeclineModelRequest() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ requestId, reason }) => {
      const { data, error } = await supabase.rpc('decline_shoe_model_request', {
        p_request_id: requestId,
        ...(reason?.trim() ? { p_reason: reason.trim() } : {}),
      })
      return readOutcome(data, error, 'That request could not be declined.')
    },
    onSuccess: () => invalidateQueue(qc),
  })
}
