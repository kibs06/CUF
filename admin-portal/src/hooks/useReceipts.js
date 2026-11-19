import { useQuery } from '@tanstack/react-query'

import { supabase } from '../lib/supabase'

// The receipt trail lives on `orders`, so the monitor reads orders — every sale,
// whichever channel made it, is a receipt. Only the recent window is fetched:
// a monitor answers "what is happening now", and the Orders screen is still
// there for anything older.
const LIMIT = 500

const COLUMNS =
  'id, order_code, status, source, created_at, total_amount, payment_method, ' +
  'receipt_emailed_at, receipt_email_to, receipt_email_attempts, ' +
  'receipt_email_last_attempt_at, receipt_email_last_error, ' +
  'receipt_email_next_attempt_at, receipt_email_sending_since, customer_email, ' +
  'profiles!orders_customer_id_fkey(full_name, email), stores(name)'

// `orders.customer_email` arrives with migration 20261119100000; a portal
// pointed at an older server should still show the trail it does have.
const LEGACY_COLUMNS = COLUMNS.replace(' customer_email,', '')

function mapReceipt(row) {
  return {
    ...row,
    customer_name: row.profiles?.full_name ?? 'Unknown',
    customer_email: row.customer_email ?? row.profiles?.email ?? '',
    store_name: row.stores?.name ?? '—',
  }
}

function fetchReceipts(columns) {
  return supabase
    .from('orders')
    .select(columns)
    .order('created_at', { ascending: false })
    .limit(LIMIT)
}

export function useReceipts() {
  return useQuery({
    queryKey: ['receipts'],
    queryFn: async () => {
      let { data, error } = await fetchReceipts(COLUMNS)
      if (error && /customer_email/i.test(error.message ?? '')) {
        ({ data, error } = await fetchReceipts(LEGACY_COLUMNS))
      }
      if (error) throw error
      return (data ?? []).map(mapReceipt)
    },
    // The trail changes when a send lands, not when a page is looked at.
    staleTime: 30_000,
  })
}
