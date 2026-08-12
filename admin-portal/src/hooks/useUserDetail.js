import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Order history for a single customer (admin RLS grants full read).
 * Used in the UserDetailModal "Orders" tab.
 */
export function useUserOrders(userId) {
  return useQuery({
    queryKey: ['user-orders', userId],
    enabled: !!userId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('orders')
        .select('*, stores(name), order_items(quantity, unit_price, products(name))')
        .eq('customer_id', userId)
        .order('created_at', { ascending: false })
      if (error) throw error

      return (data ?? []).map((order) => ({
        ...order,
        store_name: order.stores?.name ?? '—',
        items_count: (order.order_items ?? []).reduce(
          (sum, it) => sum + (it.quantity ?? 0),
          0,
        ),
        items_total: (order.order_items ?? []).reduce(
          (sum, it) => sum + (it.quantity ?? 0) * (it.unit_price ?? 0),
          0,
        ),
      }))
    },
  })
}

/**
 * A seller's storefront + sales performance:
 *   - stores they own
 *   - product listings (with stock)
 *   - online orders for their stores
 *   - POS sales transactions
 */
export function useSellerPortfolio(sellerId) {
  return useQuery({
    queryKey: ['seller-portfolio', sellerId],
    enabled: !!sellerId,
    queryFn: async () => {
      const [storesRes, productsRes, ordersRes, salesRes] = await Promise.all([
        supabase
          .from('stores')
          .select('id, name, tagline, location, is_open, is_active, rating, created_at')
          .eq('owner_id', sellerId),
        supabase
          .from('products')
          .select('id, name, price, sale_price, category, is_published, is_active, inventory(size, stock), product_images(image_url, display_order)')
          .eq('seller_id', sellerId)
          .order('created_at', { ascending: false }),
        supabase
          .from('orders')
          .select('id, status, total_amount, payment_status, created_at, stores(owner_id)')
          .order('created_at', { ascending: false }),
        supabase
          .from('sales_transactions')
          .select('id, total_amount, payment_method, created_at')
          .eq('seller_id', sellerId)
          .order('created_at', { ascending: false }),
      ])

      if (storesRes.error) throw storesRes.error
      if (productsRes.error) throw productsRes.error
      if (ordersRes.error) throw ordersRes.error
      if (salesRes.error) throw salesRes.error

      const stores = storesRes.data ?? []
      const storeIds = new Set(stores.map((s) => s.id))

      const products = (productsRes.data ?? []).map((p) => {
        const images = p.product_images ?? []
        const stock = (p.inventory ?? []).reduce((sum, v) => sum + (v.stock ?? 0), 0)
        return {
          ...p,
          thumbnail: images
            .sort((a, b) => (a.display_order ?? 0) - (b.display_order ?? 0))[0]
            ?.image_url,
          total_stock: stock,
          price: Number(p.price ?? 0),
          sale_price: p.sale_price != null ? Number(p.sale_price) : null,
        }
      })

      const orders = (ordersRes.data ?? []).filter((o) => storeIds.has(o.stores?.owner_id))

      const revenue = orders.reduce((sum, o) => sum + Number(o.total_amount ?? 0), 0)
      const posRevenue = (salesRes.data ?? []).reduce(
        (sum, t) => sum + Number(t.total_amount ?? 0),
        0,
      )

      return {
        stores,
        products,
        orders,
        posSales: salesRes.data ?? [],
        totalOrders: orders.length,
        revenue,
        totalPosSales: (salesRes.data ?? []).length,
        posRevenue,
        totalRevenue: revenue + posRevenue,
      }
    },
  })
}
