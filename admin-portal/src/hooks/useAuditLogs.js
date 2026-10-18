import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import {
  mapActivityRow,
  mapFailedLoginRow,
  mapPaymentAuditRow,
  mapSellerAuditRow,
  mapSessionRow,
} from '../lib/audit'

const PAGE_SIZE = 50

function dayBounds(dateFrom, dateTo) {
  const bounds = {}
  if (dateFrom) {
    const from = new Date(dateFrom)
    from.setHours(0, 0, 0, 0)
    bounds.from = from.toISOString()
  }
  if (dateTo) {
    const to = new Date(dateTo)
    to.setHours(23, 59, 59, 999)
    bounds.to = to.toISOString()
  }
  return bounds
}

/**
 * Batch-resolve profile ids to names in one query.
 *
 * The audit tables store actor/subject as bare ids; joining per row would be
 * N+1 queries, so the ids are collected first and resolved together. Unknown
 * (deleted) accounts stay unresolved and render as "Unknown account" — a
 * deleted row's history outliving its profile is expected, not an error.
 */
async function resolveNames(ids) {
  const unique = [...new Set(ids.filter(Boolean))]
  if (unique.length === 0) return {}
  const { data, error } = await supabase
    .from('profiles')
    .select('id, full_name, email')
    .in('id', unique)
  if (error) throw error
  const names = {}
  for (const row of data ?? []) names[row.id] = row
  return names
}

function matchesSearch(row, query) {
  const q = query.trim().toLowerCase()
  if (!q) return true
  return [row.actor, row.actorEmail, row.subject, row.subjectEmail, row.notes, row.reference, row.ip, row.device, row.place, row.role, row.detail, row.entity]
    .filter(Boolean)
    .some((value) => String(value).toLowerCase().includes(q))
}

/**
 * Seller application decisions — the immutable trigger log, newest first.
 *
 * Text search runs over the fetched page (actor/applicant names live only in
 * `profiles`, so there is no server-side column to filter on). The page is
 * deliberately wide (50) so the common "find this week's decision" case lands
 * on the first page.
 */
export function useSellerAudit({ action = 'all', dateFrom = null, dateTo = null, search = '', page = 0 } = {}) {
  return useQuery({
    queryKey: ['audit-seller', action, dateFrom, dateTo, search, page],
    queryFn: async () => {
      const { from, to } = dayBounds(dateFrom, dateTo)
      let query = supabase
        .from('seller_application_audit_log')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })
      if (action !== 'all') query = query.eq('action', action)
      if (from) query = query.gte('created_at', from)
      if (to) query = query.lte('created_at', to)
      query = query.range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1)
      const { data, error, count } = await query
      if (error) throw error

      const names = await resolveNames((data ?? []).flatMap((r) => [r.actor_id, r.profile_id]))
      const rows = (data ?? []).map((r) => mapSellerAuditRow(r, names)).filter((r) => matchesSearch(r, search))
      return { rows, total: count ?? 0, pageSize: PAGE_SIZE }
    },
    refetchInterval: 60_000,
  })
}

/** Manual GCash confirm/reject decisions, newest first. */
export function usePaymentAudit({ decision = 'all', dateFrom = null, dateTo = null, search = '', page = 0 } = {}) {
  return useQuery({
    queryKey: ['audit-payment', decision, dateFrom, dateTo, search, page],
    queryFn: async () => {
      const { from, to } = dayBounds(dateFrom, dateTo)
      let query = supabase
        .from('gcash_payment_decision_audit')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })
      if (decision !== 'all') query = query.eq('decision', decision)
      if (from) query = query.gte('created_at', from)
      if (to) query = query.lte('created_at', to)
      query = query.range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1)
      const { data, error, count } = await query
      if (error) throw error

      const names = await resolveNames((data ?? []).map((r) => r.seller_id))
      const rows = (data ?? []).map((r) => mapPaymentAuditRow(r, names)).filter((r) => matchesSearch(r, search))
      return { rows, total: count ?? 0, pageSize: PAGE_SIZE }
    },
    refetchInterval: 60_000,
  })
}

/**
 * Seller sign-ins and sign-outs, newest first.
 *
 * The role filter is server-side on the client's role CLAIM (see the
 * migration): rows whose claim failed (role NULL) do not appear here, so a
 * missing sign-out is "never logged", never "deleted". Text search runs
 * over the fetched page, same as the seller tab.
 */
export function useSessionAudit({ event = 'all', dateFrom = null, dateTo = null, search = '', page = 0 } = {}) {
  return useQuery({
    queryKey: ['audit-sessions', event, dateFrom, dateTo, search, page],
    queryFn: async () => {
      const { from, to } = dayBounds(dateFrom, dateTo)
      let query = supabase
        .from('account_session_log')
        .select('*', { count: 'exact' })
        .eq('role', 'seller')
        .order('created_at', { ascending: false })
      if (event !== 'all') query = query.eq('event', event)
      if (from) query = query.gte('created_at', from)
      if (to) query = query.lte('created_at', to)
      query = query.range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1)
      const { data, error, count } = await query
      if (error) throw error

      const names = await resolveNames((data ?? []).map((r) => r.user_id))
      const rows = (data ?? []).map((r) => mapSessionRow(r, names)).filter((r) => matchesSearch(r, search))
      return { rows, total: count ?? 0, pageSize: PAGE_SIZE }
    },
    refetchInterval: 60_000,
  })
}

/** Seller-side product / store / order-status writes, newest first. */
export function useActivityAudit({ action = 'all', dateFrom = null, dateTo = null, search = '', page = 0 } = {}) {
  return useQuery({
    queryKey: ['audit-activity', action, dateFrom, dateTo, search, page],
    queryFn: async () => {
      const { from, to } = dayBounds(dateFrom, dateTo)
      let query = supabase
        .from('seller_activity_log')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })
      if (action !== 'all') query = query.eq('action', action)
      if (from) query = query.gte('created_at', from)
      if (to) query = query.lte('created_at', to)
      query = query.range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1)
      const { data, error, count } = await query
      if (error) throw error

      const names = await resolveNames((data ?? []).map((r) => r.actor_id))
      const rows = (data ?? []).map((r) => mapActivityRow(r, names)).filter((r) => matchesSearch(r, search))
      return { rows, total: count ?? 0, pageSize: PAGE_SIZE }
    },
    refetchInterval: 60_000,
  })
}

/** Accounts under brute-force watch — failed attempts and lockouts. */
export function useSecurityAudit({ status = 'all', dateFrom = null, dateTo = null, search = '', page = 0 } = {}) {
  return useQuery({
    queryKey: ['audit-security', status, dateFrom, dateTo, search, page],
    queryFn: async () => {
      const { from, to } = dayBounds(dateFrom, dateTo)
      let query = supabase
        .from('failed_logins')
        .select('*', { count: 'exact' })
        .order('failed_at', { ascending: false })
      if (status !== 'all') query = query.eq('status', status)
      if (from) query = query.gte('failed_at', from)
      if (to) query = query.lte('failed_at', to)
      query = query.range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1)
      const { data, error, count } = await query
      if (error) throw error

      const names = await resolveNames((data ?? []).map((r) => r.user_id))
      const rows = (data ?? []).map((r) => mapFailedLoginRow(r, names)).filter((r) => matchesSearch(r, search))
      return { rows, total: count ?? 0, pageSize: PAGE_SIZE }
    },
    refetchInterval: 30_000,
  })
}
