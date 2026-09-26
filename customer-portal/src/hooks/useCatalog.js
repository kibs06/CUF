import { useQuery } from '@tanstack/react-query'

import {
  fetchProductById,
  fetchProducts,
  fetchStoreById,
  fetchStores,
} from '../lib/catalog'
import { purchasableProducts } from '../lib/stock'

/**
 * The customer catalog.
 *
 * `select` applies the browse rule (`purchasableProducts`) AFTER the fetch, so
 * the rule lives in exactly one place and the raw rows stay cached — a future
 * seller-facing view of the same cache can ask for the unfiltered list without
 * a second round trip.
 *
 * The query key includes `storeId` because a store page and the global catalog
 * are genuinely different results, not the same result filtered twice.
 *
 * `enabled` exists for the header's search field, which is the one caller that
 * needs the catalog *sometimes*: that component renders on every page, so
 * fetching the whole catalog whenever it mounts would make a visit to `/signin`
 * pay for a catalog nobody asked to see. It stays asleep until the customer has
 * actually typed something with a suggestion panel open, and reads the shared
 * cache after that (the key is the same, so whoever needs it first pays once).
 */
export function useProducts({ storeId, enabled = true } = {}) {
  return useQuery({
    queryKey: ['products', storeId ?? 'all'],
    queryFn: () => fetchProducts({ storeId }),
    select: purchasableProducts,
    enabled,
  })
}

export function useProduct(productId) {
  return useQuery({
    queryKey: ['product', productId ?? null],
    queryFn: () => fetchProductById(productId),
    enabled: Boolean(productId),
  })
}

export function useStores() {
  return useQuery({
    queryKey: ['stores'],
    queryFn: fetchStores,
  })
}

export function useStore(storeId) {
  return useQuery({
    queryKey: ['store', storeId ?? null],
    queryFn: () => fetchStoreById(storeId),
    enabled: Boolean(storeId),
  })
}
