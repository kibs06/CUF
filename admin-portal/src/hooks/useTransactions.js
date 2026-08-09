import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

const INTENT_COLUMNS = [
  'id, order_id, customer_id, paymongo_payment_intent_id, checkout_session_id,',
  'amount, fee_amount, paymongo_fee_amount, net_amount, gcash_reference_number,',
  'status, currency, livemode, expires_at, paid_at, created_at, updated_at,',
  'orders!inner(id, status, payment_status, total_amount, gcash_fee_amount,',
  '  gcash_transaction_id, payment_verified_at, created_at, store_id,',
  '  stores(name), profiles!orders_customer_id_fkey(full_name, email))',
].join(' ')

const EVENT_COLUMNS = [
  'id, event_type, status, payment_intent_id, order_id,',
  'amount, redacted_payload, received_at, processed_at',
].join(' ')

const BASE_COLUMNS = [
  'id, order_id, customer_id, paymongo_payment_intent_id, checkout_session_id,',
  'amount, fee_amount, status, currency, livemode, expires_at, paid_at,',
  'created_at, updated_at,',
  'orders!inner(id, status, payment_status, total_amount, gcash_fee_amount,',
  '  gcash_transaction_id, payment_verified_at, created_at, store_id,',
  '  stores(name), profiles!orders_customer_id_fkey(full_name, email))',
].join(' ')

function mapRow(row, feeColumnsAvailable) {
  const order = row.orders
  return {
    ...row,
    order_id: order?.id ?? row.order_id,
    store_id: order?.store_id,
    order_status: order?.status,
    order_payment_status: order?.payment_status,
    order_total_amount: order?.total_amount,
    order_gcash_fee_amount: order?.gcash_fee_amount,
    gcash_transaction_id: order?.gcash_transaction_id,
    payment_verified_at: order?.payment_verified_at,
    order_created_at: order?.created_at,
    store_name: order?.stores?.name ?? '—',
    customer_name: order?.profiles?.full_name ?? 'Unknown',
    customer_email: order?.profiles?.email ?? '',
    paymongo_fee_amount: feeColumnsAvailable ? (row.paymongo_fee_amount ?? null) : null,
    net_amount: feeColumnsAvailable ? (row.net_amount ?? null) : null,
    gcash_reference_number: feeColumnsAvailable ? (row.gcash_reference_number ?? null) : null,
  }
}

export function useTransactions(filters = {}) {
  return useQuery({
    queryKey: ['transactions', filters],
    queryFn: async () => {
      const build = async (columns, feeColumnsAvailable) => {
        let query = supabase
          .from('payment_intents')
          .select(columns)
          .order('created_at', { ascending: false })

        if (filters.status && filters.status !== 'all') {
          query = query.eq('status', filters.status)
        }
        if (filters.dateFrom) {
          const from = new Date(filters.dateFrom)
          from.setHours(0, 0, 0, 0)
          query = query.gte('created_at', from.toISOString())
        }
        if (filters.dateTo) {
          const to = new Date(filters.dateTo)
          to.setHours(23, 59, 59, 999)
          query = query.lte('created_at', to.toISOString())
        }

        const { data, error } = await query
        if (error) throw error

        return {
          rows: (data ?? []).map((r) => mapRow(r, feeColumnsAvailable)),
          feeColumnsAvailable,
        }
      }

      // Prefer the full column set (requires the admin-transactions migration).
      // If the new columns are missing (migration not applied yet), fall back
      // to the base columns so the page still works — fee/net/ref show "—".
      let intents
      try {
        intents = await build(INTENT_COLUMNS, true)
      } catch (err) {
        if (String(err?.message).match(/paymongo_fee_amount|net_amount|gcash_reference_number/)) {
          intents = await build(BASE_COLUMNS, false)
        } else {
          throw err
        }
      }

      const [eventsRes, storesRes] = await Promise.all([
        supabase
          .from('payment_webhook_events')
          .select(EVENT_COLUMNS)
          .order('received_at', { ascending: true }),
        supabase
          .from('stores')
          .select('id, name')
          .eq('is_active', true)
          .order('name', { ascending: true }),
      ])

      if (eventsRes.error) throw eventsRes.error
      if (storesRes.error) throw storesRes.error

      const eventsByOrder = new Map()
      const eventsByPiId = new Map()
      for (const e of eventsRes.data ?? []) {
        if (e.order_id) {
          const list = eventsByOrder.get(e.order_id) ?? []
          list.push(e)
          eventsByOrder.set(e.order_id, list)
        }
        if (e.payment_intent_id) {
          const list = eventsByPiId.get(e.payment_intent_id) ?? []
          list.push(e)
          eventsByPiId.set(e.payment_intent_id, list)
        }
      }

      const rows = intents.rows.map((row) => {
        const orderEvents = eventsByOrder.get(row.order_id) ?? []
        const piEvents = row.paymongo_payment_intent_id
          ? (eventsByPiId.get(row.paymongo_payment_intent_id) ?? [])
          : []
        const merged = new Map()
        for (const e of [...orderEvents, ...piEvents]) merged.set(e.id, e)
        const events = [...merged.values()].sort(
          (a, b) => new Date(a.received_at) - new Date(b.received_at),
        )
        return { ...row, events, events_count: events.length }
      })

      return {
        rows,
        feeColumnsAvailable: intents.feeColumnsAvailable,
        stores: (storesRes.data ?? []).map((s) => ({ id: s.id, name: s.name })),
      }
    },
  })
}
