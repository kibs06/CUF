import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { triggerApprovalEmail } from './useSellerApplications.js'
import { triggerVerificationPush } from '../lib/verificationPush.js'

/**
 * Admin verdict on a seller's Tier 2 business documents, from the portal.
 *
 * Uses the same SECURITY DEFINER RPC as the Flutter admin console rather than
 * writing `seller_business_docs` directly. The RPC re-checks `is_admin()`, and
 * the triggers it fires own the rest of the contract: stamping
 * `profiles.seller_verified_at`, writing the "You're a verified seller ✅"
 * notice, and withdrawing the badge on rejection. The portal sends only the
 * verdict, then the same fire-and-forget email and push the app sends.
 *
 * The email keeps `outcome: 'approved'` and adds `verified: true`, exactly like
 * `OrderProvider` and the Flutter Business Docs screen — an older deployed copy
 * of the function then still sends an approval rather than mis-reading a new
 * outcome as a rejection.
 */
export function useBusinessDocsVerdict() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({ docId, profileId, verified }) => {
      const { error } = await supabase.rpc('set_business_verification_status', {
        p_doc_id: docId,
        p_status: verified ? 'verified' : 'rejected',
      })
      if (error) throw error

      // A failed email or push must never fail the verdict.
      if (verified && profileId) {
        triggerApprovalEmail(profileId, 'approved', undefined, true)
        triggerVerificationPush(profileId)
      }
    },
    onSuccess: (_data, { profileId }) => {
      queryClient.invalidateQueries({ queryKey: ['user-documents', profileId] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
      queryClient.invalidateQueries({ queryKey: ['seller-applications'] })
      queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] })
    },
  })
}
