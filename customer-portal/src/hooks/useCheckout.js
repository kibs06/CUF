import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import {
  cancelPendingPaymentIntent,
  createAddress,
  createPaymentIntent,
  fetchAddresses,
  fetchGcashFee,
  fetchOrder,
  fetchPaymentStatus,
  fetchPendingIntent,
  placeCashOrder,
} from '../lib/checkout.js'
import { useAuth } from './useAuth.jsx'

/**
 * Checkout's queries and mutations.
 *
 * The write mutations are deliberately NOT optimistic, unlike the cart's. A cart
 * line appearing before the server confirms it is a convenience; a payment
 * session existing before the server says it does is a claim about money.
 * Every one of these waits for the server and reports exactly what came back.
 */

/** The customer's saved addresses, default first. */
export function useAddresses() {
  const { user } = useAuth()
  const userId = user?.id ?? null

  return useQuery({
    queryKey: ['addresses', userId],
    queryFn: () => fetchAddresses(userId),
    enabled: Boolean(userId),
  })
}

/** Save an address to the book. Resolves to the inserted row. */
export function useSaveAddress() {
  const { user } = useAuth()
  const userId = user?.id ?? null
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) => createAddress(userId, payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['addresses', userId] })
    },
  })
}

/**
 * The Model B GCash fee for a given order total.
 *
 * Keyed on the total, so changing the cart (or picking a different maker)
 * fetches the fee for the new amount rather than showing a stale surcharge. It
 * is not an error state if it fails — `fetchGcashFee` throws and the checkout
 * says the fee is added at payment instead of blocking the order.
 */
export function useGcashFee(orderTotal) {
  return useQuery({
    queryKey: ['gcash-fee', orderTotal],
    queryFn: () => fetchGcashFee(orderTotal),
    enabled: Number(orderTotal) > 0,
    retry: 1,
    // A rate change should reach the next checkout, not the next page load.
    staleTime: 60_000,
  })
}

/** Create the order + hosted PayMongo session. Resolves to the intent result. */
export function useCreatePaymentIntent() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const userId = user?.id ?? null

  return useMutation({
    mutationFn: (payload) => createPaymentIntent(payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pending-intent', userId] })
    },
  })
}

/**
 * Place a Cash on Pickup order — the immediate path.
 *
 * Not optimistic, for the same reason the intent is not: it is a claim about
 * money, and the server is the thing that decides whether the pair was reserved
 * (`decrement_inventory_on_order` runs inside the item inserts). What the caller
 * gets back is the order id the database actually created.
 *
 * On success both caches are invalidated: the order list gains a row, and the
 * cart is about to lose the lines it just bought — the page clears those through
 * `useCart`'s `removeLines`, which is the same path the cart itself writes with.
 */
export function usePlaceCashOrder() {
  const { user } = useAuth()
  const userId = user?.id ?? null
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) => placeCashOrder(payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['my-orders', userId] })
      queryClient.invalidateQueries({ queryKey: ['cart', userId] })
    },
  })
}

/**
 * The authoritative payment status, polled while a payment is pending.
 *
 * The interval is a function of the answer, not a constant: once the server
 * says paid, cancelled or expired, the page has its final state and continuing
 * to poll would be noise (and a request every few seconds forever on a tab left
 * open). Five seconds is chosen against the 15-minute window — a customer
 * waiting on a GCash confirmation should see the result almost immediately,
 * while the server stays the thing that decides.
 */
export function usePaymentStatus(orderId, { enabled = true } = {}) {
  return useQuery({
    queryKey: ['payment-status', orderId],
    queryFn: () => fetchPaymentStatus(orderId),
    enabled: Boolean(orderId) && enabled,
    refetchInterval: (query) => {
      const data = query?.state?.data
      if (!data) return 5000
      return data.paid ? false : 5000
    },
    refetchOnWindowFocus: true,
  })
}

/** Cancel an unpaid intent and release its order. Resolves to a boolean. */
export function useCancelPaymentIntent() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const userId = user?.id ?? null

  return useMutation({
    mutationFn: (orderId) => cancelPendingPaymentIntent(orderId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pending-intent', userId] })
      queryClient.invalidateQueries({ queryKey: ['cart', userId] })
    },
  })
}

/**
 * The customer's currently-open checkout, if any.
 *
 * Used for one thing: when a new checkout is refused because a payment is
 * already pending, send the customer to that order instead of showing them a
 * dead end.
 */
export function usePendingIntent(enabled = true) {
  const { user } = useAuth()
  const userId = user?.id ?? null

  return useQuery({
    queryKey: ['pending-intent', userId],
    queryFn: () => fetchPendingIntent(userId),
    enabled: Boolean(userId) && enabled,
  })
}

/** One order with its lines, for the states after payment resolves. */
export function useOrder(orderId) {
  return useQuery({
    queryKey: ['order', orderId],
    queryFn: () => fetchOrder(orderId),
    enabled: Boolean(orderId),
  })
}
