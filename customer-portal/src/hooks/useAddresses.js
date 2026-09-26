import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import {
  createAddress,
  deleteAddress,
  fetchAddresses,
  setDefaultAddress,
  updateAddress,
} from '../lib/checkout.js'
import { addressUpdatePayload } from '../lib/checkoutRules.js'
import { useAuth } from './useAuth.jsx'

/**
 * The customer's address book.
 *
 * Keyed by user, like the cart, because the book belongs to the account rather
 * than the browser — the whole point of it being `customer_addresses` is that
 * the pair of boots you are sending to your office is the same address on the
 * app and on the site.
 *
 * Every mutation invalidates the same key, so the list, the default badge and
 * the checkout page's prefill all agree after a save. The database enforces the
 * one-default rule with a trigger, so no client-side patch-up is needed or
 * wanted: the refetch is what says what the trigger did.
 */
export const ADDRESSES_KEY = 'addresses'

export function useMyAddresses() {
  const { user } = useAuth()
  return useQuery({
    queryKey: [ADDRESSES_KEY, user?.id ?? null],
    queryFn: () => fetchAddresses(user.id),
    enabled: Boolean(user?.id),
  })
}

export function useSaveAddress() {
  const { user } = useAuth()
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({ id, draft }) =>
      id
        ? updateAddress(id, addressUpdatePayload(draft))
        : createAddress(user.id, addressUpdatePayload(draft)),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: [ADDRESSES_KEY] }),
  })
}

export function useDeleteAddress() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (id) => deleteAddress(id),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: [ADDRESSES_KEY] }),
  })
}

export function useSetDefaultAddress() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (id) => setDefaultAddress(id),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: [ADDRESSES_KEY] }),
  })
}
