import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'

import {
  addOrUpdateItem,
  allItemsSelected,
  cartCount,
  cartItemKey,
  cartItemKeys,
  cartSubtotal,
  fetchCart,
  groupByStore,
  removeItem,
  removeItems,
  resolveVariant,
  selectedDeliveryFee,
  selectedItems,
  selectedSubtotal,
  selectedTotal,
  selectedUnitCount,
  storeSelection,
  toggleAllSelection,
  toggleItemSelection,
  toggleStoreSelection,
  updateQuantity,
} from '../lib/cart.js'
import { DELIVERY_FEE } from '../lib/checkoutRules.js'
import { useAuth } from './useAuth.jsx'

const CartContext = createContext(null)

/**
 * The cart, backed by the `cart_items` table.
 *
 * The cart lives on the server (so it is the same cart on the phone), which
 * means every interaction is a round trip — and a quantity stepper that waits
 * for the network before the number changes feels broken. So each mutation
 * writes the cache first and reconciles after:
 *
 *   optimistic write → request → refetch
 *
 * The rollback path matters as much as the happy one: if the write fails, the
 * cache is restored to exactly what it was, so the customer never sees a
 * quantity that does not exist.
 *
 * ## Which pairs are being bought
 *
 * The selection lives here rather than in the cart page, and that is the point
 * of it being a port: `/checkout` is a different route, and a selection held in
 * a page's state would be gone by the time the customer gets there — which is
 * exactly the bug this replaced. It is deliberately **not** persisted: the app
 * keeps `_selectedKeys` in memory too, and a cart that reopens with yesterday's
 * ticks still on it is a cart that will charge for something the customer was
 * not looking at.
 *
 * The four totals below are the ones the checkout must agree with. They come
 * from `cartRules.js` — the same file the tests drive — so "what does the
 * summary say" has one answer, not two.
 */
export function CartProvider({ children }) {
  const { user } = useAuth()
  const userId = user?.id ?? null
  const queryClient = useQueryClient()
  const [error, setError] = useState(null)
  const [pendingIds, setPendingIds] = useState(() => new Set())

  /*
    Which lines are ticked. A Set of `productId-size-color` keys (see
    `cartItemKey`), never the cart row's id: a line whose quantity changes keeps
    its identity, so a tick survives the stepper.
  */
  const [selectedKeys, setSelectedKeys] = useState(() => new Set())

  const cartQuery = useQuery({
    queryKey: ['cart', userId],
    queryFn: () => fetchCart(userId),
    enabled: Boolean(userId),
  })

  const items = cartQuery.data ?? []

  const markPending = useCallback((id, pending) => {
    setPendingIds((current) => {
      const next = new Set(current)
      if (pending) next.add(id)
      else next.delete(id)
      return next
    })
  }, [])

  /**
   * Write the cache, then the database. A failure restores the previous cache
   * rather than refetching: the snapshot is exactly what the customer saw, so
   * rolling back to it is instant and truthful.
   */
  const mutate = useCallback(
    async (applyOptimistic, request, lineId) => {
      if (!userId) return

      const key = ['cart', userId]
      const previous = queryClient.getQueryData(key)

      if (applyOptimistic) {
        queryClient.setQueryData(key, applyOptimistic)
      }
      if (lineId) markPending(lineId, true)
      setError(null)

      try {
        await request()
      } catch (caught) {
        if (applyOptimistic) queryClient.setQueryData(key, previous)
        setError(caught?.message ?? 'Something went wrong with your cart.')
        throw caught
      } finally {
        if (lineId) markPending(lineId, false)
        // Reconcile with the server: prices and stock move, and the cart is
        // the one place a customer will notice a stale number.
        queryClient.invalidateQueries({ queryKey: key })
      }
    },
    [userId, queryClient, markPending],
  )

  const setQuantity = useCallback(
    (item, nextQuantity) =>
      mutate(
        (current) =>
          nextQuantity <= 0
            ? (current ?? []).filter((row) => row.id !== item.id)
            : (current ?? []).map((row) =>
                row.id === item.id ? { ...row, quantity: nextQuantity } : row,
              ),
        () => updateQuantity({ cartItemId: item.id, newQuantity: nextQuantity }),
        item.id,
      ),
    [mutate],
  )

  const removeLine = useCallback(
    (item) =>
      mutate(
        (current) => (current ?? []).filter((row) => row.id !== item.id),
        () => removeItem(item.id),
        item.id,
      ),
    [mutate],
  )

  /**
   * Remove several lines at once — what checkout does after an order is placed.
   *
   * One request rather than a loop: a partially-cleared cart after a successful
   * order is the worst possible outcome, and the customer would be looking at
   * pairs they have already paid for.
   */
  const removeLines = useCallback(
    (lines) => {
      const ids = (lines ?? []).map((line) => line.id)
      if (ids.length === 0) return Promise.resolve()

      return mutate(
        (current) => (current ?? []).filter((row) => !ids.includes(row.id)),
        () => removeItems(userId, ids),
        null,
      )
    },
    [mutate, userId],
  )

  /**
   * Add a product in a chosen size.
   *
   * The variant is resolved here rather than by the caller, so no screen can
   * forget it and write a cart row with a null `variant_id` — the same reason
   * the app routes every add through `resolveVariant`.
   */
  const addItem = useCallback(
    async ({ product, size, color, quantity = 1 }) => {
      if (!userId) throw new Error('sign-in-required')

      const { variantId } = resolveVariant({
        variants: product?.product_variants ?? [],
        size,
        color,
      })

      await addOrUpdateItem({
        userId,
        productId: product.id,
        variantId,
        quantity,
        size,
      })

      /*
        The pair just added is ticked — `CartProvider.addToCart` does the same
        (`_selectedKeys.add(cartKey)`), and it is what makes the common path
        "add a pair → check out that pair" work without a detour through the
        cart's checkboxes.
      */
      setSelectedKeys((current) =>
        new Set(current).add(cartItemKey({ productId: product.id, size, color })),
      )

      await queryClient.invalidateQueries({ queryKey: ['cart', userId] })
    },
    [userId, queryClient],
  )

  /** Drop keys for lines that are no longer in the cart, so the totals cannot count a ghost. */
  useEffect(() => {
    const live = new Set(cartItemKeys(items))
    setSelectedKeys((current) => {
      if (current.size === 0) return current
      const next = new Set([...current].filter((key) => live.has(key)))
      return next.size === current.size ? current : next
    })
  }, [items])

  const selection = useMemo(
    () => ({
      selectedKeys,
      selectedItems: selectedItems(items, selectedKeys),
      selectedUnitCount: selectedUnitCount(items, selectedKeys),
      selectedSubtotal: selectedSubtotal(items, selectedKeys),
      selectedDeliveryFee: selectedDeliveryFee(items, selectedKeys, DELIVERY_FEE),
      selectedTotal: selectedTotal(items, selectedKeys, DELIVERY_FEE),
      allSelected: allItemsSelected(items, selectedKeys),
      storeSelection: (storeId) => storeSelection(items, selectedKeys, storeId),
      toggleItem: (item) => setSelectedKeys((current) => toggleItemSelection(current, item)),
      toggleStore: (storeId) =>
        setSelectedKeys((current) => toggleStoreSelection(current, items, storeId)),
      toggleAll: () => setSelectedKeys((current) => toggleAllSelection(current, items)),
    }),
    [items, selectedKeys],
  )

  // `groups`, `count` and `subtotal` are all derived from `items`, so `items`
  // is the only dependency they need.
  const value = useMemo(
    () => ({
      items,
      groups: groupByStore(items),
      count: cartCount(items),
      subtotal: cartSubtotal(items),
      isLoading: cartQuery.isLoading && Boolean(userId),
      error,
      clearError: () => setError(null),
      pendingIds,
      addItem,
      setQuantity,
      removeLine,
      removeLines,
      refetch: cartQuery.refetch,
      ...selection,
    }),
    [
      items,
      userId,
      error,
      pendingIds,
      addItem,
      setQuantity,
      removeLine,
      removeLines,
      cartQuery.refetch,
      cartQuery.isLoading,
      selection,
    ],
  )

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>
}

export function useCart() {
  const context = useContext(CartContext)
  if (!context) throw new Error('useCart must be used within CartProvider')
  return context
}
