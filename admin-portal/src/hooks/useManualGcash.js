import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

// ─── Platform receiving account + payout settings ───────────────────

export function usePlatformAccounts() {
  return useQuery({
    queryKey: ['platform-payment-accounts'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('platform_payment_accounts')
        .select('id, label, gcash_number, account_name, qr_url, is_active, created_at')
        .order('created_at', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })
}

export function useSavePlatformAccount() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ label, gcashNumber, accountName, qrUrl, activate }) => {
      const { data, error } = await supabase
        .from('platform_payment_accounts')
        .insert({
          label: label?.trim() || 'Platform GCash',
          gcash_number: gcashNumber.trim(),
          account_name: accountName.trim(),
          qr_url: qrUrl || null,
          is_active: false,
        })
        .select('id')
        .single()
      if (error) throw error
      if (activate) {
        // One active row is enforced by a partial unique index, so retire
        // the current one BEFORE activating the new one.
        const { error: offErr } = await supabase
          .from('platform_payment_accounts')
          .update({ is_active: false })
          .eq('is_active', true)
        if (offErr) throw offErr
        const { error: onErr } = await supabase
          .from('platform_payment_accounts')
          .update({ is_active: true })
          .eq('id', data.id)
        if (onErr) throw onErr
      }
      return data.id
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['platform-payment-accounts'] })
    },
  })
}

export function useActivatePlatformAccount() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id) => {
      const { error: offErr } = await supabase
        .from('platform_payment_accounts')
        .update({ is_active: false })
        .eq('is_active', true)
      if (offErr) throw offErr
      const { error } = await supabase
        .from('platform_payment_accounts')
        .update({ is_active: true })
        .eq('id', id)
      if (error) throw error
      return id
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['platform-payment-accounts'] })
    },
  })
}

export function usePlatformSettings() {
  return useQuery({
    queryKey: ['platform-settings'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('platform_settings')
        .select('platform_fee_bps, delivery_fee_amount, updated_at')
        .eq('id', 1)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
}

export function useUpdatePlatformSettings() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ platformFeeBps, deliveryFeeAmount }) => {
      const { error } = await supabase
        .from('platform_settings')
        .update({
          platform_fee_bps: Number(platformFeeBps) || 0,
          delivery_fee_amount: Number(deliveryFeeAmount) || 0,
          updated_at: new Date().toISOString(),
        })
        .eq('id', 1)
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['platform-settings'] }),
  })
}

// ─── Verification queue ─────────────────────────────────────────────

const MANUAL_COLUMNS = [
  'id, status, payment_status, total_amount, order_code, created_at,',
  'review_deadline, payment_flagged, payment_flag_reason, seller_verified_at,',
  // How the money was confirmed when there is no proof row: payment_verified_at
  // is the webhook/verification timestamp, gcash_transaction_id is PayMongo's
  // payment id (pay_xxx) for gateway-confirmed orders, and
  // gcash_reference_number is the POS/legacy manual reference. Without these
  // an older order with no screenshot is indistinguishable from a customer who
  // never submitted — and those are not the same thing to an admin.
  'payment_verified_at, gcash_transaction_id, gcash_reference_number,',
  'funds_reconciled_at, payment_account_id,',
  'stores(name), profiles!orders_customer_id_fkey(full_name),',
  // submitted_at is the server's arrival stamp (pinned by trigger, immutable);
  // paid_at is what the receipt claims and is customer-influenced.
  'gcash_payment_proofs(id, reference_number, sender_name, amount_paid,',
  '  screenshot_url, screenshot_hash, attempt_no, status, rejection_reason,',
  '  submitted_at, paid_at)',
].join(' ')

export function useManualPayments() {
  return useQuery({
    queryKey: ['manual-gcash-payments'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('orders')
        .select(MANUAL_COLUMNS)
        .eq('payment_method', 'gcash')
        .eq('source', 'online')
        .in('status', ['payment_under_review', 'pending', 'placed', 'preparing'])
        .order('created_at', { ascending: false })
        .limit(100)
      if (error) throw error
      return (data ?? []).map((row) => {
        const proofs = Array.isArray(row.gcash_payment_proofs)
          ? [...row.gcash_payment_proofs].sort(
              (a, b) => (b.attempt_no ?? 0) - (a.attempt_no ?? 0),
            )
          : []
        return {
          ...row,
          proof: proofs[0] ?? null,
          store_name: row.stores?.name ?? '—',
          customer_name: row['profiles']?.full_name ?? 'Customer',
        }
      })
    },
    refetchInterval: 45_000,
  })
}

function usePaymentMutation(rpc, invalidate = ['manual-gcash-payments']) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params) => {
      const { error } = await supabase.rpc(rpc, params)
      if (error) throw error
    },
    onSuccess: () => {
      invalidate.forEach((key) => qc.invalidateQueries({ queryKey: [key] }))
    },
  })
}

export function useFlagPayment() {
  return usePaymentMutation('admin_flag_payment')
}

export function useClearPaymentFlag() {
  return usePaymentMutation('admin_clear_payment_flag')
}

export function useAdminVerifyPayment() {
  return usePaymentMutation('admin_verify_payment')
}

export function useReconcileOrder() {
  return usePaymentMutation('admin_reconcile_order', [
    'manual-gcash-payments',
    'seller-payables',
  ])
}

/** Short-lived signed URL for a private proof screenshot. */
export async function proofSignedUrl(path) {
  if (!path) return null
  const { data, error } = await supabase.storage
    .from('payment-proofs')
    .createSignedUrl(path, 3600)
  if (error) return null
  return data?.signedUrl ?? null
}

// ─── Payouts ────────────────────────────────────────────────────────

export function usePayables() {
  return useQuery({
    queryKey: ['seller-payables'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('v_seller_payables')
        .select('store_id, store_name, order_count, gross_amount, delivery_fees, platform_fee, net_amount')
        .order('net_amount', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })
}

export function usePayouts() {
  return useQuery({
    queryKey: ['seller-payouts'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('v_seller_payout_summary')
        .select('id, store_id, store_name, period_date, gross_amount, delivery_fees, platform_fee, net_amount, status, paid_at, paid_reference, receipt_path, order_count, requested_at, seller_name, seller_phone, payout_method, payout_details')
        .order('period_date', { ascending: false })
        .limit(60)
      if (error) throw error
      return data ?? []
    },
  })
}

export function useGeneratePayouts() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (date) => {
      const { data, error } = await supabase.rpc('generate_daily_payouts', {
        p_date: date ?? null,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['seller-payouts'] })
      qc.invalidateQueries({ queryKey: ['seller-payables'] })
    },
  })
}

export function useMarkPayoutPaid() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ payoutId, reference, receiptPath }) => {
      const { error } = await supabase.rpc('mark_payout_paid', {
        p_payout_id: payoutId,
        p_reference: reference,
        p_receipt: receiptPath ?? '',
      })
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['seller-payouts'] })
    },
  })
}

export async function uploadPayoutReceipt(payoutId, file) {
  const path = `${payoutId}/${Date.now()}-${file.name.replace(/[^\w.\-]/g, '_')}`
  const { error } = await supabase.storage
    .from('payout-receipts')
    .upload(path, file, { upsert: false })
  if (error) throw error
  return path
}
