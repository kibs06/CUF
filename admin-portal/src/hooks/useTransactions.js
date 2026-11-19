import { useQuery } from '@tanstack/react-query'

import { supabase } from '../lib/supabase'

// Transactions = money that actually arrived.
//
// This page used to read `payment_intents`, the PayMongo gateway's log of
// checkout attempts: a counter sale had no row there at all, and every
// abandoned QR stayed in the list for ever, so the page drifted away from what
// the shop had really sold. It now reads **paid orders** — both channels, one
// row per sale — and uses the gateway tables only to explain how an online
// payment was confirmed.
const LIMIT = 1000

const ORDER_COLUMNS = [
  'id, order_code, status, payment_status, payment_method, source, total_amount,',
  'amount_tendered, change_amount, fulfillment,',
  'created_at, payment_verified_at, gcash_transaction_id, gcash_reference_number,',
  'receipt_emailed_at, receipt_email_to, receipt_email_attempts,',
  'receipt_email_last_error, receipt_email_next_attempt_at, receipt_email_sending_since,',
  'store_id, stores(name),',
  'profiles!orders_customer_id_fkey(full_name, email, avatar_url),',
  'order_items(quantity, unit_price, size, products(name)),',
  // The customer's own GCash evidence, when the money came in by transfer.
  'gcash_payment_proofs(id, reference_number, sender_name, amount_paid,',
  '  screenshot_url, attempt_no, status, rejection_reason, submitted_at, paid_at)',
].join(' ')

const INTENT_COLUMNS = [
  'id, order_id, paymongo_payment_intent_id, checkout_session_id, status,',
  'amount, livemode, paid_at, created_at',
].join(' ')

const EVENT_COLUMNS = [
  'id, event_type, status, payment_intent_id, order_id,',
  'amount, redacted_payload, received_at, processed_at',
].join(' ')

function mapOrder(row) {
  return {
    id: row.id,
    order_id: row.id,
    order_code: row.order_code ?? '',
    order_status: row.status ?? '',
    store_id: row.store_id,
    store_name: row.stores?.name ?? '—',
    customer_name: row.profiles?.full_name ?? 'Unknown',
    customer_email: row.profiles?.email ?? '',
    customer_avatar_url: row.profiles?.avatar_url ?? '',
    amount: Number(row.total_amount) || 0,
    method: row.payment_method ?? '',
    source: row.source ?? '',
    fulfillment: row.fulfillment ?? '',
    tendered: row.amount_tendered == null ? null : Number(row.amount_tendered),
    change: row.change_amount == null ? null : Number(row.change_amount),
    // Shaped like the receipt builders expect, so the same sale can be printed.
    items: (row.order_items ?? []).map((item) => ({
      product_name: item.products?.name ?? item.product_name ?? 'Product',
      size: item.size ?? '',
      quantity: Number(item.quantity) || 0,
      unit_price: Number(item.unit_price) || 0,
    })),
    // The latest attempt is the one that decided the payment; earlier ones are
    // history, not evidence anyone needs on the receipt.
    proof: Array.isArray(row.gcash_payment_proofs)
      ? [...row.gcash_payment_proofs].sort(
          (a, b) => (b.attempt_no ?? 0) - (a.attempt_no ?? 0),
        )[0] ?? null
      : null,
    paid_at: row.payment_verified_at ?? null,
    receipt_emailed_at: row.receipt_emailed_at ?? null,
    receipt_email_to: row.receipt_email_to ?? null,
    receipt_email_attempts: Number(row.receipt_email_attempts) || 0,
    receipt_email_last_error: row.receipt_email_last_error ?? null,
    receipt_email_next_attempt_at: row.receipt_email_next_attempt_at ?? null,
    receipt_email_sending_since: row.receipt_email_sending_since ?? null,
    gcash_transaction_id: row.gcash_transaction_id ?? null,
    gcash_reference_number: row.gcash_reference_number ?? null,
    created_at: row.created_at,
    intent: null,
    events: [],
    events_count: 0,
  }
}

/** The intent that explains an order: a succeeded one, else the newest try. */
function pickIntent(intents) {
  if (!intents.length) return null
  const succeeded = intents.find((intent) => intent.status === 'succeeded')
  return succeeded ?? intents[0]
}

export function useTransactions(filters = {}) {
  return useQuery({
    queryKey: ['transactions', filters],
    queryFn: async () => {
      let query = supabase
        .from('orders')
        .select(ORDER_COLUMNS)
        .eq('payment_status', 'paid')
        .order('created_at', { ascending: false })
        .limit(LIMIT)

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

      const rows = (data ?? []).map(mapOrder)
      const orderIds = rows.map((row) => row.id)

      const empty = { data: [], error: null }
      const [intentsRes, eventsRes, storesRes] = await Promise.all([
        orderIds.length
          ? supabase
              .from('payment_intents')
              .select(INTENT_COLUMNS)
              .in('order_id', orderIds)
              .order('created_at', { ascending: false })
          : Promise.resolve(empty),
        orderIds.length
          ? supabase
              .from('payment_webhook_events')
              .select(EVENT_COLUMNS)
              .in('order_id', orderIds)
              .order('received_at', { ascending: true })
          : Promise.resolve(empty),
        supabase
          .from('stores')
          .select('id, name')
          .eq('is_active', true)
          .order('name', { ascending: true }),
      ])

      if (intentsRes.error) throw intentsRes.error
      if (eventsRes.error) throw eventsRes.error
      if (storesRes.error) throw storesRes.error

      const intentsByOrder = new Map()
      for (const intent of intentsRes.data ?? []) {
        const list = intentsByOrder.get(intent.order_id) ?? []
        list.push(intent)
        intentsByOrder.set(intent.order_id, list)
      }

      const eventsByOrder = new Map()
      for (const event of eventsRes.data ?? []) {
        if (!event.order_id) continue
        const list = eventsByOrder.get(event.order_id) ?? []
        list.push(event)
        eventsByOrder.set(event.order_id, list)
      }

      return {
        rows: rows.map((row) => {
          const events = eventsByOrder.get(row.id) ?? []
          return {
            ...row,
            intent: pickIntent(intentsByOrder.get(row.id) ?? []),
            events,
            events_count: events.length,
          }
        }),
        stores: (storesRes.data ?? []).map((store) => ({
          id: store.id,
          name: store.name,
        })),
        limit: LIMIT,
      }
    },
    // A sale is written once; the page does not need to poll for it.
    staleTime: 30_000,
  })
}
