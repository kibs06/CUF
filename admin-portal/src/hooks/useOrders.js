import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

// A line row always represents at least one item, so a missing quantity
// falls back to 1 instead of zeroing out the whole order.
function countItems(items) {
  return (items ?? []).reduce((sum, item) => {
    const q = Number(item.quantity)
    return sum + (Number.isFinite(q) && q > 0 ? q : 1)
  }, 0)
}

function mapOrder(row) {
  const items = row.order_items ?? []
  return {
    ...row,
    customer_name: row.profiles?.full_name ?? 'Unknown',
    customer_email: row.profiles?.email ?? '',
    customer_avatar_url: row.profiles?.avatar_url ?? '',
    store_name: row.stores?.name ?? '—',
    items_count: countItems(items),
    order_items: items.map((item) => ({
      ...item,
      product_name: item.products?.name ?? item.product_name ?? 'Product',
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
          '*, profiles!orders_customer_id_fkey(full_name, email, avatar_url), stores(name), order_items(*, products(name, product_images(image_url, display_order)))',
        )
        .order('created_at', { ascending: false })

      if (error) throw error
      const mapped = (data ?? []).map(mapOrder)
      // Fallback: if the embedded order_items join came back empty, fetch the
      // lines directly in one query and merge the counts in. If the direct
      // read is also blocked, this is a no-op and counts stay as mapped.
      const missing = mapped.filter((m) => m.order_items.length === 0)
      if (missing.length > 0) {
        try {
          const { data: lines, error: linesError } = await supabase
            .from('order_items')
            .select('order_id, quantity, product_id, products(name)')
            .in('order_id', missing.map((m) => m.id))
          if (linesError) throw linesError
          const byOrder = new Map()
          for (const line of lines ?? []) {
            const arr = byOrder.get(line.order_id) ?? []
            arr.push({
              ...line,
              product_name: line.products?.name ?? 'Product',
            })
            byOrder.set(line.order_id, arr)
          }
          for (const m of missing) {
            const arr = byOrder.get(m.id) ?? []
            if (arr.length > 0) {
              m.order_items = arr
              m.items_count = countItems(arr)
            }
          }
        } catch {
          // Keep the embedded results on any direct-read failure.
        }
      }
      return mapped
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
