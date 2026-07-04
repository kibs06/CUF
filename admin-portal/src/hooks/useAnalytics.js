import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

function daysAgo(n) {
  const d = new Date()
  d.setDate(d.getDate() - n)
  d.setHours(0, 0, 0, 0)
  return d
}

function dateKey(date) {
  return date.toISOString().slice(0, 10)
}

function buildDayRange(days) {
  const keys = []
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date()
    d.setDate(d.getDate() - i)
    keys.push(dateKey(d))
  }
  return keys
}

export function useAnalytics(days = 30) {
  return useQuery({
    queryKey: ['analytics', days],
    queryFn: async () => {
      const since = daysAgo(days - 1)

      const [ordersRes, profilesRes] = await Promise.all([
        supabase
          .from('orders')
          .select('id, status, total_amount, created_at')
          .gte('created_at', since.toISOString()),
        supabase
          .from('profiles')
          .select('id, seller_status, created_at')
          .gte('created_at', since.toISOString()),
      ])

      if (ordersRes.error) throw ordersRes.error
      if (profilesRes.error) throw profilesRes.error

      const orders = ordersRes.data ?? []
      const profiles = profilesRes.data ?? []
      const dayKeys = buildDayRange(days)

      const ordersByDay = Object.fromEntries(dayKeys.map((k) => [k, 0]))
      const revenueByDay = Object.fromEntries(dayKeys.map((k) => [k, 0]))
      const usersByDay = Object.fromEntries(dayKeys.map((k) => [k, 0]))

      for (const order of orders) {
        const key = order.created_at?.slice(0, 10)
        if (ordersByDay[key] !== undefined) {
          ordersByDay[key] += 1
          revenueByDay[key] += Number(order.total_amount) || 0
        }
      }

      for (const profile of profiles) {
        const key = profile.created_at?.slice(0, 10)
        if (usersByDay[key] !== undefined) usersByDay[key] += 1
      }

      const ordersOverTime = dayKeys.map((k) => ({
        date: k.slice(5),
        orders: ordersByDay[k],
      }))

      const revenueOverTime = dayKeys.map((k) => ({
        date: k.slice(5),
        revenue: revenueByDay[k],
      }))

      const usersOverTime = dayKeys.map((k) => ({
        date: k.slice(5),
        users: usersByDay[k],
      }))

      const statusCounts = {}
      for (const order of orders) {
        const s = order.status ?? 'unknown'
        statusCounts[s] = (statusCounts[s] ?? 0) + 1
      }

      const ordersByStatus = Object.entries(statusCounts).map(([name, value]) => ({
        name,
        value,
      }))

      const productCounts = {}
      const orderIds = orders.map((o) => o.id)
      if (orderIds.length) {
        const { data: orderItems } = await supabase
          .from('order_items')
          .select('product_id, quantity, products(name)')
          .in('order_id', orderIds)

        for (const item of orderItems ?? []) {
          const name = item.products?.name ?? 'Unknown'
          productCounts[name] = (productCounts[name] ?? 0) + (item.quantity ?? 1)
        }
      }

      const topProducts = Object.entries(productCounts)
        .map(([name, count]) => ({ name, count }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 10)

      const sellerTrend = {}
      for (const profile of profiles) {
        if (!['pending', 'approved', 'rejected'].includes(profile.seller_status)) continue
        const month = profile.created_at?.slice(0, 7) ?? 'unknown'
        if (!sellerTrend[month]) {
          sellerTrend[month] = { pending: 0, approved: 0, rejected: 0 }
        }
        sellerTrend[month][profile.seller_status] += 1
      }

      const sellerApplicationTrend = Object.entries(sellerTrend)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([month, counts]) => ({
          month,
          ...counts,
        }))

      return {
        ordersOverTime,
        revenueOverTime,
        usersOverTime,
        ordersByStatus,
        topProducts,
        sellerApplicationTrend,
      }
    },
  })
}
