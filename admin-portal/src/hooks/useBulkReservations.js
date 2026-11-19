import { useQuery } from '@tanstack/react-query'

import { supabase } from '../lib/supabase'

// Bulk buying = reseller holds requested from a product page, plus the GCash
// deposit that secures them.
//
// Bulk reservations are NOT orders: nothing was sold, no stock has moved while
// the request is pending, and the only money that changes hands up front is the
// non-refundable deposit. That is why they cannot be shown by the Paid sales
// ledger (which reads `orders` with payment_status = 'paid') and why this hook
// reads the reservation table directly. Admins have a SELECT policy on both
// tables ("Admins can view all reservations" / "...all deposit proofs").
const LIMIT = 1000

const COLUMNS = [
  'id, quantity, requested_sizes, note, status, deposit_amount, deposit_status,',
  'deposit_deadline, expires_at, fulfilled_at, rejection_reason, created_at,',
  'store_id, stores(name),',
  // No FK hint: `bulk_reservations` has exactly one foreign key to profiles,
  // so PostgREST resolves the embed on its own (the same form the app uses).
  'profiles(full_name, email),',
  'products(name, price),',
  // At most one proof per reservation (the table has a unique index), so this
  // arrives as a 0- or 1-element array.
  'bulk_reservation_deposits(reference_number, submitted_at)',
].join(' ')

/** What the customer asked for, in one line: "EU 40 × 20 · Black EU 41 × 43". */
function sizesText(sizes) {
  return sizes
    .map((entry) => {
      const size = String(entry?.size ?? '').trim()
      const colour = String(entry?.color ?? '').trim()
      const quantity = Number(entry?.quantity) || 0
      const label = [colour, size].filter(Boolean).join(' ')
      return label ? `${label} × ${quantity}` : `${quantity}`
    })
    .filter(Boolean)
    .join(' · ')
}

function mapReservation(row) {
  const sizes = Array.isArray(row.requested_sizes) ? row.requested_sizes : []
  const proof = (row.bulk_reservation_deposits ?? [])[0] ?? null
  const quantity = Number(row.quantity) || 0
  const unitPrice = Number(row.products?.price) || 0

  return {
    id: row.id,
    created_at: row.created_at,
    status: row.status ?? 'pending',
    store_id: row.store_id,
    store_name: row.stores?.name ?? '—',
    customer_name: row.profiles?.full_name ?? 'Unknown',
    customer_email: row.profiles?.email ?? '',
    product_name: row.products?.name ?? 'Product',
    quantity,
    unit_price: unitPrice,
    // What the hold is worth if it is picked up — NOT money received.
    estimated_value: unitPrice * quantity,
    sizes,
    sizes_text: sizesText(sizes),
    note: row.note ?? '',
    deposit_amount: row.deposit_amount == null ? null : Number(row.deposit_amount),
    deposit_status: row.deposit_status ?? 'not_required',
    deposit_deadline: row.deposit_deadline ?? null,
    deposit_reference: proof?.reference_number ?? null,
    deposit_submitted_at: proof?.submitted_at ?? null,
    expires_at: row.expires_at ?? null,
    fulfilled_at: row.fulfilled_at ?? null,
    rejection_reason: row.rejection_reason ?? '',
  }
}

export function useBulkReservations(filters = {}) {
  return useQuery({
    queryKey: ['bulk-reservations', filters],
    queryFn: async () => {
      let query = supabase
        .from('bulk_reservations')
        .select(COLUMNS)
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

      return {
        rows: (data ?? []).map(mapReservation),
        limit: LIMIT,
      }
    },
    // A reservation changes on a seller decision, not continuously; a short
    // stale window keeps the page calm without hiding a fresh deposit.
    staleTime: 30_000,
  })
}
