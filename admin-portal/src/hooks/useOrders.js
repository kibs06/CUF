import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

function mapOrder(row) {
  const items = row.order_items ?? []
  const itemsCount = items.reduce((sum, item) => sum + (item.quantity ?? 0), 0)
  return {
    ...row,
    customer_name: row.profiles?.full_name ?? 'Unknown',
    customer_email: row.profiles?.email ?? '',
    store_name: row.stores?.name ?? '—',
    items_count: itemsCount,
    order_items: items.map((item) => ({
      ...item,
      product_name: item.products?.name ?? 'Product',
    })),
  }
}

export function useOrders() {
  return useQuery({
    queryKey: ['orders'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('orders')
        .select(
          '*, profiles!orders_customer_id_fkey(full_name, email), stores(name), order_items(*, products(name, product_images(image_url, display_order)))',
        )
        .order('created_at', { ascending: false })

      if (error) throw error
      return (data ?? []).map(mapOrder)
    },
  })
}

export function useUpdateOrderStatus() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ orderId, status }) => {
      const { error } = await supabase
        .from('orders')
        .update({ status: status.toLowerCase() })
        .eq('id', orderId)
      if (error) throw error
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['orders'] })
      queryClient.invalidateQueries({ queryKey: ['recent-orders'] })
    },
  })
}
