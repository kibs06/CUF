import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

const PROFILE_FIELDS =
  'id, full_name, email, role, seller_status, avatar_url, created_at, phone, suspended, suspended_reason, suspended_at'

export function useUsers() {
  return useQuery({
    queryKey: ['admin-users'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select(PROFILE_FIELDS)
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

function invalidateUsers(queryClient) {
  queryClient.invalidateQueries({ queryKey: ['admin-users'] })
  queryClient.invalidateQueries({ queryKey: ['seller-applications'] })
  queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] })
  queryClient.invalidateQueries({ queryKey: ['recent-pending-applications'] })
}

/**
 * Suspend or reactivate a user account.
 * `suspended: true`  → sets suspended, suspended_reason, suspended_at
 * `suspended: false` → clears the flag and audit fields
 */
export function useUpdateUserStatus() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ userId, suspended, reason = '' }) => {
      const update = suspended
        ? {
            suspended: true,
            suspended_reason: reason?.trim() || null,
            suspended_at: new Date().toISOString(),
          }
        : {
            suspended: false,
            suspended_reason: null,
            suspended_at: null,
          }
      const { error } = await supabase
        .from('profiles')
        .update(update)
        .eq('id', userId)
      if (error) throw error
    },
    onSuccess: () => invalidateUsers(queryClient),
  })
}

/** Change a user's role (customer / seller / admin). */
export function useUpdateUserRole() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ userId, role }) => {
      const { error } = await supabase
        .from('profiles')
        .update({ role })
        .eq('id', userId)
      if (error) throw error
    },
    onSuccess: () => invalidateUsers(queryClient),
  })
}
