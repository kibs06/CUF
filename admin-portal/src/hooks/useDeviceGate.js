import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

// ─── "Empty", or "hidden"? ────────────────────────────────────────
//
// The device gate draws its policy as
// `USING (public.device_is_trusted() OR public.is_admin())`, and a policy like
// that hides ROWS rather than raising: a session it refuses sees an empty list
// and no error at all. So a gated page cannot tell a queue with nothing in it
// from a queue it is not allowed to see — and "Nothing waiting" is the one
// sentence an admin must not be told when the truth is "you are not an admin's
// session".
//
// That is the same failure shape V2.14 was about: news written to a table
// nobody reads. Correct, and invisible.
//
// `public.device_gate_open()` is the database's own answer to it — its comment
// in `20260915150000_enforce_trusted_devices.sql` says it exists precisely so an
// app can "distinguish 'empty' from 'gated'", and the Flutter client calls it on
// startup for the same reason.
//
// It never throws, deliberately. A probe whose whole job is to explain a blank
// screen must not be able to blank the screen itself, so a missing function (an
// older database) or a failed call reports `null` — *unknown* — and the page
// keeps its ordinary empty state rather than claiming a gate it cannot see.
//
// Returns: `true` (this session may read the gated tables), `false` (it may
// not), or `null` (unknown).
export function useDeviceGate({ enabled = true } = {}) {
  return useQuery({
    queryKey: ['device-gate'],
    enabled,
    // Cheap and stable: the answer changes when a device is trusted, which is
    // not something a page needs to notice within the minute.
    staleTime: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('device_gate_open')
      if (error) return null
      return data === true
    },
  })
}
