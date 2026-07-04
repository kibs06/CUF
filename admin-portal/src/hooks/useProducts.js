import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useProducts(filters = {}) {
  return useQuery({
    queryKey: ['admin-products', filters],
    queryFn: async () => {
      // Fetch all active stores
      const { data: stores, error: storesErr } = await supabase
        .from('stores')
        .select('id, name, tagline, location, logo_url, banner_url, brand_color, is_open, is_active, rating')
        .eq('is_active', true)
        .order('created_at', { ascending: false })

      if (storesErr) throw storesErr

      // Fetch all products with relations
      let query = supabase
        .from('products')
        .select(
          '*, stores(name, brand_color, logo_url), product_images(image_url, is_primary, display_order), inventory(size, stock)',
        )
        .order('created_at', { ascending: false })

      if (filters.search) {
        query = query.ilike('name', `%${filters.search}%`)
      }
      if (filters.category) {
        query = query.eq('category', filters.category)
      }
      if (filters.status === 'active') {
        query = query.eq('is_published', true)
      } else if (filters.status === 'inactive') {
        query = query.eq('is_published', false)
      }

      const { data: products, error: productsErr } = await query

      if (productsErr) throw productsErr

      // Enrich products with computed fields
      const enriched = (products ?? []).map((p) => {
        const images = p.product_images ?? []
        const inv = p.inventory ?? []
        const totalStock = inv.reduce((sum, v) => sum + (v.stock ?? 0), 0)
        const thumbnail = images
          .sort((a, b) => (a.display_order ?? 0) - (b.display_order ?? 0))[0]
          ?.image_url
        return {
          ...p,
          store_name: p.stores?.name ?? '—',
          store_brand_color: p.stores?.brand_color,
          store_logo: p.stores?.logo_url,
          thumbnail,
          totalStock,
          isActive: p.is_published !== false,
        }
      })

      // Group by store_id
      const storeMap = new Map()
      for (const store of stores ?? []) {
        storeMap.set(store.id, { store, products: [] })
      }
      for (const p of enriched) {
        const group = storeMap.get(p.store_id)
        if (group) {
          group.products.push(p)
        } else {
          // Products without a matching active store go into an "Unassigned" group
          if (!storeMap.has('__unassigned__')) {
            storeMap.set('__unassigned__', {
              store: { id: '__unassigned__', name: 'Unassigned', tagline: 'Products without a store' },
              products: [],
            })
          }
          storeMap.get('__unassigned__').products.push(p)
        }
      }

      const grouped = [...storeMap.values()].filter(
        (g) => g.products.length > 0 || g.store.id !== '__unassigned__',
      )

      // Compute category list from products
      const categorySet = new Set(enriched.map((p) => p.category).filter(Boolean))
      const categories = [...categorySet].sort()

      return {
        grouped,
        total: enriched.length,
        storeCount: grouped.length,
        categories,
      }
    },
  })
}

export function useToggleProductStatus() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ productId, isPublished }) => {
      const { error } = await supabase
        .from('products')
        .update({ is_published: isPublished })
        .eq('id', productId)
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-products'] }),
  })
}

export function useDeleteProduct() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (productId) => {
      const { error } = await supabase
        .from('products')
        .update({ is_published: false })
        .eq('id', productId)
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-products'] }),
  })
}
