// admin-portal/src/lib/features.js
//
// Feature switches for portal flows that are temporarily off.
//
// One flag per flow, read by every place that would otherwise link to it — the
// sidebar, the route and any cross-page buttons — so hiding a page cannot leave
// a dead link behind. Flip to `true` to bring the flow back; nothing else needs
// to change.

/**
 * GCash Verification (manual GCash proof review) is hidden for now.
 *
 * While false: no sidebar entry, `/payment-verification` redirects to Payouts,
 * and the empty-payout state points at Orders instead. The page, its hooks and
 * its data are untouched, so turning it back on restores all of it.
 */
export const SHOW_GCASH_VERIFICATION = false
