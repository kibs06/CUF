import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useUsers() {
  return useQuery({
    queryKey: ['admin-users'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name, email, role, seller_status, avatar_url, created_at, phone')
        .order('created_at', { ascending: false })

      if (error) throw error

      return {
        all: data ?? [],
        customers: (data ?? []).filter((u) => u.role === 'customer'),
        sellers: (data ?? []).filter((u) => u.role === 'seller'),
        admins: (data ?? []).filter((u) => u.role === 'admin'),
      }
    },
  })
}
