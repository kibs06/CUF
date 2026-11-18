import { useEffect, useMemo, useState } from 'react'
import { CheckCircle2, Landmark, Plus, QrCode, ShieldCheck, Upload } from 'lucide-react'
import {
  useActivatePlatformAccount,
  usePlatformAccounts,
  usePlatformSettings,
  useSavePlatformAccount,
  useUpdatePlatformSettings,
} from '../hooks/useManualGcash.js'
import { supabase } from '../lib/supabase'
import { formatDateTime } from '../lib/constants'
import Badge from '../components/ui/Badge.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'

const NUMBER_PATTERN = /^[0-9+][0-9 \-]{6,19}$/

const BTN =
  'inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-white px-2.5 text-[12px] font-semibold text-secondary transition-colors hover:bg-canvas disabled:cursor-not-allowed disabled:opacity-50'
const BTN_PRIMARY =
  'inline-flex h-9 items-center gap-1.5 rounded-lg bg-secondary px-3.5 text-[12px] font-semibold text-white transition-colors hover:bg-primaryDeep disabled:cursor-not-allowed disabled:opacity-50'

const INPUT =
  'h-9 w-full rounded-lg border border-border bg-white px-2.5 text-[12px] text-ink outline-none transition-colors placeholder:text-muted/60 focus:border-primary focus:ring-2 focus:ring-primary/15'
const INPUT_MONO = `${INPUT} font-mono tracking-wide`

/** Label, control, hint — the same field shape the other forms use. */
function Field({ label, hint, error, htmlFor, children }) {
  return (
    <label className="block" htmlFor={htmlFor}>
      <span className="mb-1 block text-[12px] font-medium text-muted">{label}</span>
      {children}
      <span
        className={`mt-1 block text-[11.5px] ${error ? 'text-error' : 'text-muted'}`}
      >
        {error || hint}
      </span>
    </label>
  )
}

export default function PlatformPayments() {
  const { data: accounts = [], isLoading } = usePlatformAccounts()
  const { data: settings } = usePlatformSettings()
  const saveAccount = useSavePlatformAccount()
  const activateAccount = useActivatePlatformAccount()
  const saveSettings = useUpdatePlatformSettings()

  const [form, setForm] = useState({
    label: 'Platform GCash',
    gcashNumber: '',
    accountName: '',
    qrUrl: '',
    activate: true,
  })
  const [fee, setFee] = useState({ bps: 0, delivery: 100 })
  const [qrFile, setQrFile] = useState(null)
  const [message, setMessage] = useState(null)
  const [touched, setTouched] = useState({})

  useEffect(() => {
    if (!settings) return
    setFee({
      bps: settings.platform_fee_bps ?? 0,
      delivery: Number(settings.delivery_fee_amount ?? 100),
    })
  }, [settings])

  const activeAccount = accounts.find((account) => account.is_active) ?? null

  // Live object URL for a QR picked but not saved yet, so the preview shows
  // exactly the image that will go live.
  const localQr = useMemo(
    () => (qrFile ? URL.createObjectURL(qrFile) : null),
    [qrFile],
  )
  useEffect(() => () => localQr && URL.revokeObjectURL(localQr), [localQr])

  const numberError =
    touched.number && !NUMBER_PATTERN.test(form.gcashNumber.trim())
      ? 'Use the 09XXXXXXXXX format, 7–20 digits.'
      : null
  const nameError =
    touched.name && form.accountName.trim().length < 2
      ? 'Enter the account name exactly as GCash shows it.'
      : null

  const canSave =
    NUMBER_PATTERN.test(form.gcashNumber.trim()) &&
    form.accountName.trim().length >= 2

  // The preview mirrors what the customer's payment screen renders: a typed
  // value wins, otherwise the live account.
  const previewNumber = form.gcashNumber.trim() || activeAccount?.gcash_number
  const previewName = form.accountName.trim() || activeAccount?.account_name
  const previewQr = localQr || form.qrUrl || activeAccount?.qr_url

  const uploadQr = async (file) => {
    const path = `platform/${Date.now()}-${file.name.replace(/[^\w.\-]/g, '_')}`
    const { error } = await supabase.storage
      .from('platform-payment-qr')
      .upload(path, file, { upsert: false })
    if (error) throw error
    const { data } = supabase.storage.from('platform-payment-qr').getPublicUrl(path)
    return data?.publicUrl ?? null
  }

  const submitAccount = async (event) => {
    event.preventDefault()
    setMessage(null)
    try {
      let qrUrl = form.qrUrl.trim() || null
      if (qrFile) qrUrl = await uploadQr(qrFile)
      await saveAccount.mutateAsync({ ...form, qrUrl })
      setForm((prev) => ({ ...prev, gcashNumber: '', accountName: '', qrUrl: '' }))
      setQrFile(null)
      setTouched({})
      setMessage({ tone: 'ok', text: 'Account saved. Customers now see it at checkout.' })
    } catch (error) {
      setMessage({ tone: 'error', text: error.message })
    }
  }

  const submitSettings = async (event) => {
    event.preventDefault()
    setMessage(null)
    try {
      await saveSettings.mutateAsync({
        platformFeeBps: fee.bps,
        deliveryFeeAmount: fee.delivery,
      })
      setMessage({ tone: 'ok', text: 'Payout settings saved.' })
    } catch (error) {
      setMessage({ tone: 'error', text: error.message })
    }
  }

  return (
    <div className="space-y-4">
      {message ? (
        <div
          role="status"
          className={`rounded-xl border px-4 py-3 text-[12px] ${
            message.tone === 'ok'
              ? 'border-accent/25 bg-accentSoft/70 text-ink'
              : 'border-error/25 bg-errorSoft text-error'
          }`}
        >
          {message.text}
        </div>
      ) : null}

      <div className="grid gap-4 xl:grid-cols-[minmax(0,1.55fr)_minmax(300px,0.95fr)]">
        <div className="space-y-4">
          <section className="overflow-hidden rounded-xl border border-border bg-white">
            <div className="border-b border-border px-4 py-3.5">
              <h2 className="text-[15px] font-bold text-ink">Where the money lands</h2>
              <p className="mt-0.5 text-[12px] text-muted">
                Customers see this number with the exact amount and an order code. Only one
                account can be active.
              </p>
            </div>

            <form onSubmit={submitAccount} className="grid gap-4 px-4 py-4 sm:grid-cols-2">
              <Field label="Label" hint="Internal name. Never shown to customers." htmlFor="gcash-label">
                <input
                  id="gcash-label"
                  className={INPUT}
                  value={form.label}
                  onChange={(e) => setForm({ ...form, label: e.target.value })}
                />
              </Field>

              <Field
                label="GCash number"
                hint="The wallet that receives every online payment."
                error={numberError}
                htmlFor="gcash-number"
              >
                <input
                  id="gcash-number"
                  required
                  inputMode="numeric"
                  aria-invalid={Boolean(numberError)}
                  placeholder="09XXXXXXXXX"
                  className={INPUT_MONO}
                  value={form.gcashNumber}
                  onChange={(e) => setForm({ ...form, gcashNumber: e.target.value })}
                  onBlur={() => setTouched((t) => ({ ...t, number: true }))}
                />
              </Field>

              <Field
                label="Account name"
                hint="Customers match this against their GCash receipt."
                error={nameError}
                htmlFor="gcash-name"
              >
                <input
                  id="gcash-name"
                  required
                  aria-invalid={Boolean(nameError)}
                  className={INPUT}
                  value={form.accountName}
                  onChange={(e) => setForm({ ...form, accountName: e.target.value })}
                  onBlur={() => setTouched((t) => ({ ...t, name: true }))}
                />
              </Field>

              <Field label="QR image" hint="Optional. A screenshot of your receive-money QR." htmlFor="gcash-qr">
                <div className="flex h-9 items-center gap-2 rounded-lg border border-dashed border-border bg-canvas px-2.5">
                  <Upload size={13} strokeWidth={1.7} className="shrink-0 text-muted" />
                  <input
                    id="gcash-qr"
                    type="file"
                    accept="image/*"
                    className="w-full text-[11.5px] text-muted file:mr-2 file:rounded-md file:border-0 file:bg-white file:px-2 file:py-1 file:text-[11px] file:font-semibold file:text-ink"
                    onChange={(e) => setQrFile(e.target.files?.[0] ?? null)}
                  />
                </div>
              </Field>

              <label className="flex items-center gap-2.5 text-[12px] text-ink sm:col-span-2">
                <input
                  type="checkbox"
                  className="h-4 w-4 rounded border-border accent-primary"
                  checked={form.activate}
                  onChange={(e) => setForm({ ...form, activate: e.target.checked })}
                />
                Make this the active account
              </label>

              <div className="flex flex-wrap items-center gap-3 sm:col-span-2">
                <button
                  type="submit"
                  className={BTN_PRIMARY}
                  disabled={saveAccount.isPending || !canSave}
                >
                  <Plus size={13} strokeWidth={1.8} aria-hidden="true" />
                  {saveAccount.isPending ? 'Saving…' : 'Save account'}
                </button>
                <p className="text-[11.5px] text-muted">
                  Saving with the box ticked retires the previous active row.
                </p>
              </div>
            </form>
          </section>

          <section className="overflow-hidden rounded-xl border border-border bg-white">
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3.5">
              <div>
                <h2 className="text-[15px] font-bold text-ink">Receiving history</h2>
                <p className="mt-0.5 text-[12px] text-muted">
                  Only the active row is shown to customers. Older rows stay for the audit trail.
                </p>
              </div>
              <Badge
                label={activeAccount ? 'Active' : 'Inactive'}
                variant={activeAccount ? 'approved' : 'none'}
                dot
              />
            </div>

            {isLoading ? (
              <p className="px-4 py-6 text-[12px] text-muted">Loading…</p>
            ) : accounts.length === 0 ? (
              <div className="px-4 py-4">
                <EmptyState
                  Icon={Landmark}
                  title="No account yet"
                  description="Checkout refuses every GCash order until one is active."
                />
              </div>
            ) : (
              <ul className="divide-y divide-border">
                {accounts.map((account) => (
                  <li
                    key={account.id}
                    className="flex flex-wrap items-center gap-3 px-4 py-3 transition-colors hover:bg-canvas/60"
                  >
                    <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-canvas text-muted">
                      <Landmark size={15} strokeWidth={1.6} aria-hidden="true" />
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[13px] font-semibold text-ink">
                        {account.account_name}
                      </p>
                      <p className="font-mono text-[11.5px] tracking-wide text-muted">
                        {account.gcash_number} · {account.label}
                      </p>
                    </div>
                    <p className="hidden text-[11.5px] text-muted sm:block">
                      added {formatDateTime(account.created_at)}
                    </p>
                    {account.is_active ? (
                      <Badge label="Active" variant="approved" dot />
                    ) : (
                      <button
                        type="button"
                        className={BTN}
                        onClick={() => activateAccount.mutate(account.id)}
                        disabled={activateAccount.isPending}
                      >
                        Make active
                      </button>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="overflow-hidden rounded-xl border border-border bg-white">
            <div className="border-b border-border px-4 py-3.5">
              <h2 className="text-[15px] font-bold text-ink">What each store receives</h2>
              <p className="mt-0.5 text-[12px] text-muted">
                Commission applies to goods value only. The ₱100 delivery fee stays with the
                platform to pay the courier.
              </p>
            </div>

            <form onSubmit={submitSettings} className="flex flex-wrap items-start gap-4 px-4 py-4">
              <div className="w-40">
                <Field
                  label="Commission"
                  hint={`${(Number(fee.bps) / 100).toFixed(2)}% of goods value`}
                  htmlFor="fee-bps"
                >
                  <div className="flex h-9 items-center rounded-lg border border-border bg-white px-2.5 focus-within:border-primary focus-within:ring-2 focus-within:ring-primary/15">
                    <input
                      id="fee-bps"
                      type="number"
                      min="0"
                      max="5000"
                      className="w-full bg-transparent font-mono text-[12px] tabular-nums text-ink outline-none"
                      value={fee.bps}
                      onChange={(e) => setFee({ ...fee, bps: e.target.value })}
                    />
                    <span className="ml-1 text-[10px] font-semibold uppercase tracking-wider text-muted">
                      bps
                    </span>
                  </div>
                </Field>
              </div>

              <div className="w-40">
                <Field label="Delivery fee" hint="Charged once per order" htmlFor="fee-delivery">
                  <div className="flex h-9 items-center rounded-lg border border-border bg-white px-2.5 focus-within:border-primary focus-within:ring-2 focus-within:ring-primary/15">
                    <span className="mr-1 font-mono text-[12px] text-muted">₱</span>
                    <input
                      id="fee-delivery"
                      type="number"
                      min="0"
                      step="0.01"
                      className="w-full bg-transparent font-mono text-[12px] tabular-nums text-ink outline-none"
                      value={fee.delivery}
                      onChange={(e) => setFee({ ...fee, delivery: e.target.value })}
                    />
                  </div>
                </Field>
              </div>

              <button
                type="submit"
                className={`${BTN_PRIMARY} mt-[22px]`}
                disabled={saveSettings.isPending}
              >
                <CheckCircle2 size={13} strokeWidth={1.8} aria-hidden="true" />
                {saveSettings.isPending ? 'Saving…' : 'Save settings'}
              </button>
            </form>
          </section>
        </div>

        <aside className="space-y-4">
          <section className="overflow-hidden rounded-xl border border-border bg-white">
            <div className="border-b border-border px-4 py-3.5">
              <h2 className="text-[15px] font-bold text-ink">Customer view</h2>
              <p className="mt-0.5 text-[12px] text-muted">
                What the buyer sees after tapping Complete Order.
              </p>
            </div>

            <div className="px-4 py-4">
              <div className="rounded-lg bg-secondary p-4">
                <p className="text-[10px] font-semibold uppercase tracking-wider text-white/50">
                  Send to
                </p>
                <p className="mt-1 select-all font-mono text-[16px] tracking-[0.06em] text-white">
                  {previewNumber || '09XXXXXXXXX'}
                </p>
                <p className="mt-0.5 text-[12px] text-white/60">
                  {previewName || 'Account name appears here'}
                </p>

                <div className="mt-4 flex items-center gap-3">
                  <div className="flex h-[68px] w-[68px] shrink-0 items-center justify-center overflow-hidden rounded-lg bg-white">
                    {previewQr ? (
                      <img
                        src={previewQr}
                        alt="Platform GCash QR as shown to customers"
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <QrCode size={24} strokeWidth={1.5} className="text-muted" />
                    )}
                  </div>
                  <div className="min-w-0">
                    <p className="text-[10px] font-semibold uppercase tracking-wider text-white/50">
                      Order code
                    </p>
                    <p className="mt-1 inline-flex rounded-md bg-white/10 px-2 py-0.5 font-mono text-[12px] tracking-[0.12em] text-white">
                      A7K2M9QX
                    </p>
                    <p className="mt-1 text-[11px] leading-snug text-white/60">
                      Pasted into the GCash note so the payment matches the order.
                    </p>
                  </div>
                </div>
              </div>

              <div
                className={`mt-3 flex items-start gap-2 rounded-lg px-3 py-2.5 text-[11.5px] leading-snug ${
                  activeAccount
                    ? 'bg-accentSoft text-accent'
                    : 'bg-errorSoft text-error'
                }`}
              >
                <ShieldCheck size={14} strokeWidth={1.6} className="mt-px shrink-0" />
                <span>
                  {activeAccount
                    ? `Live — payments land in ${activeAccount.account_name}.`
                    : 'No active account. Checkout refuses every GCash order.'}
                </span>
              </div>
            </div>
          </section>
        </aside>
      </div>
    </div>
  )
}
