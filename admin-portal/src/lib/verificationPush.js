import { supabase } from './supabase'

/**
 * Fire-and-forget verified-seller push through the shared FCM function.
 *
 * Used after any action that lands `seller_business_docs` on `verified`:
 * the Documents-tab verdict and application approval (which auto-verifies
 * the docs in the same transaction). The in-app notices are written by the
 * DB trigger, so this is only the lock-screen channel — a failed push must
 * never fail or delay the admin action.
 */
export function triggerVerificationPush(userId) {
  if (!userId) return
  supabase.functions
    .invoke('send-notification-push', {
      body: {
        recipientUserId: userId,
        title: "You're a verified seller ✅",
        body: 'Your business documents were approved. Your Verified Seller badge is now showing on your profile and store page.',
        type: 'verified_seller',
        screen: 'seller_notifications',
      },
    })
    .then(({ error }) => {
      if (error) console.error('Verification push trigger failed:', error)
    })
    .catch((err) => console.error('Verification push trigger failed:', err))
}
