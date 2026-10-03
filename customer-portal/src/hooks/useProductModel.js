import { useQuery } from '@tanstack/react-query'

import { fetchProductModel } from '../lib/catalog'
import { activeProductModel, modelFileUrl } from '../lib/shoeModel'

/**
 * The product's live 3D model, ready to draw — or null.
 *
 * Three decisions, and each one is about the page this sits on: a product page
 * whose job is selling, with a viewer as a bonus.
 *
 *  1. **`retry: false`.** A failed read here is *silence*, not a fault to retry
 *     through: the entry simply does not appear, which is the same thing a
 *     product with no model shows. React Query's default three attempts would
 *     spend the visitor's connection on a decoration, on a page that has already
 *     made its real requests.
 *  2. **The row is selected through `activeProductModel`** rather than trusted
 *     as-is, so the "active only, newest version" rule lives in one tested place
 *     (`shoeModel.js`) instead of being spread across a query string.
 *  3. **The URL is built here, not stored.** The bucket is public
 *     (`modelFileUrl`), so there is nothing to sign, nothing to expire and
 *     nothing to fetch twice: the row plus the project URL is the whole answer.
 *
 * `enabled` keeps it asleep until a product id exists — the hook runs while the
 * page is still loading its own product, and a query for `null` would be a
 * request nobody can answer.
 */
export default function useProductModel(productId) {
  const query = useQuery({
    queryKey: ['product-model', productId ?? null],
    queryFn: () => fetchProductModel(productId),
    enabled: Boolean(productId),
    retry: false,
    // A published model changes on the seller's schedule, not the visitor's:
    // five minutes of staleness costs nothing and saves a read per page view.
    staleTime: 5 * 60 * 1000,
  })

  const row = query.data ? activeProductModel([query.data]) : null
  const url = row
    ? modelFileUrl(row.storage_path, import.meta.env.VITE_SUPABASE_URL)
    : null

  return { model: url ? { url, row } : null, isLoading: query.isLoading }
}
