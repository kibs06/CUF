import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import { cancelOrder, fetchMyOrder, fetchMyOrders } from '../lib/orders.js'
import { useAuth } from './useAuth.jsx'

/**
 * The order history's queries and mutations.
 *
 * Keys are `my-orders` / `my-order`, distinct from `checkout.js`'s `order` key
 * on purpose: that one is the payment page's projection of a single in-flight
 * order (it carries the stored fee rate and VAT), this one is the history view.
 * Sharing a key between two different fetchers would let each one serve the
 * other's cached shape.
 */

/** Every order this customer has placed, newest first. */
export function useMyOrders() {
  const { user } = useAuth()
  const userId = user?.id ?? null

  return useQuery({
    queryKey: ['my-orders', userId],
    queryFn: () => fetchMyOrders(userId),
    enabled: Boolean(userId),
  })
}

/** One order, with its lines and its status timeline. */
export function useMyOrder(orderId) {
  return useQuery({
    queryKey: ['my-order', orderId ?? null],
    queryFn: () => fetchMyOrder(orderId),
    enabled: Boolean(orderId),
  })
}

/**
 * Cancel an order, or ask the maker to.
 *
 * Deliberately NOT optimistic, unlike the cart. A cart line appearing before
 * the server confirms it is a convenience; an order reporting itself cancelled
 * before the server has recorded it is a claim about a pair of shoes and a
 * refund. The screen waits, then shows exactly which of the two transitions
 * happened — which is also why the mutation resolves to the server's own
 * `status` rather than to a boolean.
 *
 * On success both views are refetched, plus `checkout.js`'s single-order query
 * so the payment page cannot keep showing a live countdown for an order the
 * customer has just cancelled in another tab.
 */
export function useCancelOrder() {
  const { user } = useAuth()
  const userId = user?.id ?? null
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) => cancelOrder(payload),
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ['my-orders', userId] })
      queryClient.invalidateQueries({ queryKey: ['my-order', result?.orderId] })
      queryClient.invalidateQueries({ queryKey: ['order', result?.orderId] })
      queryClient.invalidateQueries({ queryKey: ['pending-intent', userId] })
    },
  })
}
