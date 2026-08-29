import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Fetch all failed_logins rows joined with profiles.
 * Returns a map of userId → lockout info for quick lookup in UserRow.
 */
export function useFailedLogins() {
  return useQuery({
    queryKey: ['failed-logins'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('failed_logins')
        .select('user_id, attempt_count, status, locked_until, failed_at')
        .order('failed_at', { ascending: false })

      if (error) throw error

      // Build a map: userId → lockout info
      const map = {}
      for (const row of data ?? []) {
        map[row.user_id] = {
          attemptCount: row.attempt_count ?? 0,
          status: row.status ?? 'active',
          lockedUntil: row.locked_until,
          failedAt: row.failed_at,
        }
      }
      return map
    },
    refetchInterval: 30_000, // auto-refresh every 30s
  })
}
