import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import {
  createSellerProduct,
  deleteSellerProduct,
  fetchMyStore,
  fetchSellerOrder,
  fetchSellerOrders,
  fetchSellerProduct,
  fetchSellerProducts,
  isApprovedSeller,
  removeColourImage,
  removeProductImage,
  saveProductColourImages,
  saveProductCustomizations,
  saveProductVariants,
  updateSellerOrderStatus,
  updateSellerProduct,
  updateSellerStore,
  uploadProductImages,
  uploadStoreAsset,
} from '../lib/seller.js'
import { useAuth } from './useAuth.jsx'

/**
 * The seller portal's queries and mutations.
 *
 * Keys are their own namespace (`seller-orders`, `seller-products`, …) and not
 * shared with the customer's `my-orders` / `products`. That is not tidiness:
 * the two select different columns for different questions — a seller's order
 * row carries the customer and the whole history, a customer's carries the
 * store — so one cache entry serving both would hand whichever screen asked
 * second the wrong shape.
 *
 * Every hook takes its identity from the auth context rather than from its
 * caller, and every one is gated on that identity being real. A seller page that
 * forgot to wait for the store would otherwise fire `fetchSellerOrders(null)`,
 * which reads as "no orders" and paints an empty state over a page that has
 * simply not loaded.
 */

/**
 * The store this seller owns.
 *
 * The single source of truth for the rest of the portal: every other seller
 * query needs a `storeId`, and this is where it comes from. `null` is a real
 * answer — an approved seller who has not finished Create Store — so callers
 * must handle it rather than treat it as an error.
 */
export function useMyStore() {
  const { user, profile } = useAuth()
  const userId = user?.id ?? null
  const allowed = isApprovedSeller(profile)

  return useQuery({
    queryKey: ['seller-store', userId],
    queryFn: () => fetchMyStore(userId),
    enabled: Boolean(userId) && allowed,
  })
}

/** Every order placed against this seller's store, newest first. */
export function useSellerOrders(storeId) {
  return useQuery({
    queryKey: ['seller-orders', storeId ?? null],
    queryFn: () => fetchSellerOrders(storeId),
    enabled: Boolean(storeId),
  })
}

/** One order, scoped to the store so a foreign id reads as "not found". */
export function useSellerOrder(orderId, storeId) {
  return useQuery({
    queryKey: ['seller-order', orderId ?? null],
    queryFn: () => fetchSellerOrder(orderId, storeId),
    enabled: Boolean(orderId) && Boolean(storeId),
  })
}

/**
 * Change an order's status.
 *
 * Deliberately NOT optimistic, for the same reason `useCancelOrder` is not: an
 * order claiming to be delivered before the server recorded it is a claim about
 * somebody's shoes. On success every view of the order is refetched — the list,
 * the detail, and the seller's own store query, whose dashboard totals are
 * computed from all of them.
 */
export function useUpdateSellerOrderStatus(storeId) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) => updateSellerOrderStatus(payload),
    onSuccess: (order) => {
      queryClient.invalidateQueries({ queryKey: ['seller-orders', storeId] })
      queryClient.invalidateQueries({ queryKey: ['seller-order', order?.id] })
    },
  })
}

/** The store's products, with inventory and variants. */
export function useSellerProducts(storeId) {
  return useQuery({
    queryKey: ['seller-products', storeId ?? null],
    queryFn: () => fetchSellerProducts(storeId),
    enabled: Boolean(storeId),
  })
}

export function useSellerProduct(productId) {
  return useQuery({
    queryKey: ['seller-product', productId ?? null],
    queryFn: () => fetchSellerProduct(productId),
    enabled: Boolean(productId),
  })
}

/** Create a product, then re-read the list so the new row appears with stock. */
export function useCreateSellerProduct(storeId) {
  const { user } = useAuth()
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (draft) =>
      createSellerProduct({ storeId, sellerId: user?.id, draft }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['seller-products', storeId] })
    },
  })
}

export function useUpdateSellerProduct(storeId) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ productId, patch }) => updateSellerProduct(productId, patch),
    onSuccess: (product) => {
      queryClient.invalidateQueries({ queryKey: ['seller-products', storeId] })
      queryClient.invalidateQueries({ queryKey: ['seller-product', product?.id] })
    },
  })
}

export function useDeleteSellerProduct(storeId) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (productId) => deleteSellerProduct(productId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['seller-products', storeId] })
    },
  })
}

/**
 * Replace a product's variants, and re-derive its inventory and availability.
 *
 * One hook for both callers — the form's colour/size grid and the list's quick
 * restock panel — because they write the same tables by the same rules. Two
 * hooks would be two places for the delete-then-insert order to drift, and the
 * inventory row is what the customer's size grid reads.
 */
export function useSaveProductVariants(storeId) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) => saveProductVariants(payload),
    onSuccess: (_rows, payload) => {
      queryClient.invalidateQueries({ queryKey: ['seller-products', storeId] })
      queryClient.invalidateQueries({
        queryKey: ['seller-product', payload?.productId],
      })
      /*
        The storefront's own catalog is invalidated too, and this is the one
        place a seller write reaches a customer surface. A seller who drops a
        size to zero has changed what the product page offers — leaving the
        storefront's cache alone would show a buyable size for as long as that
        cache lives.
      */
      queryClient.invalidateQueries({ queryKey: ['products'] })
      queryClient.invalidateQueries({ queryKey: ['product'] })
    },
  })
}

/** Replace a product's customisation options. */
export function useSaveProductCustomizations(storeId) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) => saveProductCustomizations(payload),
    onSuccess: (_rows, payload) => {
      queryClient.invalidateQueries({ queryKey: ['seller-products', storeId] })
      queryClient.invalidateQueries({
        queryKey: ['seller-product', payload?.productId],
      })
      /*
        The storefront's own reads are invalidated even though nothing on the web
        draws an option yet: the columns are public, the app reads them for the
        same product, and a customer-facing cache that keeps serving a set the
        seller just replaced is the one thing this invalidation is for.
      */
      queryClient.invalidateQueries({ queryKey: ['products'] })
      queryClient.invalidateQueries({ queryKey: ['product'] })
    },
  })
}

export function useUploadProductImages(storeId) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) => uploadProductImages(payload),
    onSuccess: (_urls, payload) => {
      queryClient.invalidateQueries({ queryKey: ['seller-products', storeId] })
      queryClient.invalidateQueries({
        queryKey: ['seller-product', payload?.productId],
      })
      queryClient.invalidateQueries({ queryKey: ['products'] })
    },
  })
}

export function useRemoveProductImage(storeId) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) => removeProductImage(payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['seller-products', storeId] })
      queryClient.invalidateQueries({ queryKey: ['products'] })
    },
  })
}

/**
 * Replace a product's per-colour galleries.
 *
 * The invalidations are the customisations one's, for the same reason: a colour's
 * photos are read by the app's product page (and by the web storefront the moment
 * it grows a colour picker), which is a public cache this write has to move even
 * though nothing on the seller's own screens reads it afterwards.
 *
 * The seller's id is added here rather than asked of every caller, the same way
 * `useCreateSellerProduct` does it: it is the first segment of every colour photo's
 * storage path, and the bucket's own policy checks it.
 */
export function useSaveProductColourImages(storeId) {
  const { user } = useAuth()
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) =>
      saveProductColourImages({ sellerId: user?.id, ...payload }),
    onSuccess: (_rows, payload) => {
      queryClient.invalidateQueries({ queryKey: ['seller-products', storeId] })
      queryClient.invalidateQueries({
        queryKey: ['seller-product', payload?.productId],
      })
      queryClient.invalidateQueries({ queryKey: ['products'] })
      queryClient.invalidateQueries({ queryKey: ['product'] })
    },
  })
}

/** Remove one stored colour photo — the row and the object, together. */
export function useRemoveColourImage(storeId) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) => removeColourImage(payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['seller-products', storeId] })
      queryClient.invalidateQueries({ queryKey: ['products'] })
    },
  })
}

/** Save the storefront, and adopt the row the database returns. */
export function useUpdateSellerStore(storeId) {
  const { user } = useAuth()
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (patch) => updateSellerStore(storeId, patch),
    onSuccess: (store) => {
      queryClient.setQueryData(['seller-store', user?.id ?? null], store)
      /*
        The store's name and brand colour are painted on the storefront — the
        makers gallery, the store page, every product card's store line — so a
        rename that only updated the seller's own cache would leave the
        marketplace advertising the old name.
      */
      queryClient.invalidateQueries({ queryKey: ['stores'] })
      queryClient.invalidateQueries({ queryKey: ['products'] })
    },
  })
}

/** Upload a logo or a banner, and adopt the updated store row. */
export function useUploadStoreAsset(storeId) {
  const { user } = useAuth()
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (payload) =>
      uploadStoreAsset({ storeId, sellerId: user?.id, ...payload }),
    onSuccess: (result) => {
      queryClient.setQueryData(['seller-store', user?.id ?? null], result.store)
      queryClient.invalidateQueries({ queryKey: ['stores'] })
    },
  })
}
