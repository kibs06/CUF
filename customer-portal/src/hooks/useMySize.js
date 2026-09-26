import { useMemo } from 'react'

import { useAuth } from './useAuth.jsx'
import { shoppingEuSizeFrom } from '../lib/sizeMatchRules'

/**
 * The customer's size for shopping, in EU — or null.
 *
 * One hook rather than the same two lines in every size-aware surface, because
 * "where does my size come from" has exactly one answer (`shoppingEuSizeFrom`
 * over the profile) and four surfaces now ask: the home shelf, the catalog's
 * filter, a product page's advice line and a product card's tag. Four copies of
 * a derivation is four places to fix when the profile column changes.
 *
 * No fetch: the profile is already in the auth context for a signed-in
 * customer, and a browse surface must never wait on — or fail because of — a
 * network call. Null means every caller renders nothing.
 */
export function useMySize() {
  const { profile } = useAuth()
  return useMemo(() => shoppingEuSizeFrom(profile), [profile])
}
