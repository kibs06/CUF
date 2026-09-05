import { useEffect, useState } from 'react'
import { Shield, ShieldOff, X } from 'lucide-react'
import { useToast } from './ui/Toast.jsx'
import {
  enrollMfa,
  listMfaFactors,
  unenrollMfa,
  verifyLogin,
} from '../lib/mfa'

export default function MfaCard() {
  const { showToast } = useToast()
  const [factors, setFactors] = useState(null) // null = loading
  const [enrolling, setEnrolling] = useState(false)
  const [enrollment, setEnrollment] = useState(null)
  const [confirmCode, setConfirmCode] = useState('')
  const [confirming, setConfirming] = useState(false)
  const [confirmError, setConfirmError] = useState('')

  const verified = (factors ?? []).some((f) => f.status === 'verified')

  const refresh = async () => {
    try {
      const all = await listMfaFactors()
      setFactors(all)
    } catch (err) {
      showToast(err.message ?? 'Could not load 2FA status', 'error')
    }
  }

  useEffect(() => {
    refresh()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const handleEnable = async () => {
    setEnrolling(true)
    try {
      const res = await enrollMfa({ friendlyName: 'Authenticator app' })
      setEnrollment(res)
      setConfirmCode('')
      setConfirmError('')
    } catch (err) {
      showToast(err.message ?? 'Could not start 2FA setup', 'error')
    } finally {
      setEnrolling(false)
    }
  }

  const handleConfirm = async (e) => {
    e.preventDefault()
    if (confirming) return
    setConfirming(true)
    setConfirmError('')
    try {
      await verifyLogin({ factorId: enrollment.id, code: confirmCode })
      setEnrollment(null)
      showToast('Two-factor authentication enabled')
      await refresh()
    } catch (err) {
      setConfirmError("That code didn't match. Try the next one.")
    } finally {
      setConfirming(false)
    }
  }

  const abortEnrollment = async () => {
    if (enrollment) {
      try {
        await unenrollMfa(enrollment.id)
      } catch {
        // Ignore — factor expiry cleans up abandoned enrollments too.
      }
    }
    setEnrollment(null)
  }

  const handleDisable = async () => {
    const factor = (factors ?? []).find((f) => f.status === 'verified')
    if (!factor) return
    if (
      !window.confirm(
        'Turn off 2FA? Your account will be protected by your password only.',
      )
    ) {
      return
    }
    try {
      await unenrollMfa(factor.id)
      showToast('Two-factor authentication disabled')
      await refresh()
    } catch (err) {
      showToast(err.message ?? 'Could not disable 2FA', 'error')
    }
  }

  return (
    <div className="overflow-hidden rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
      <div className="flex items-center gap-2 border-b border-[#F5F0EB] px-6 py-4">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[#F5F0EB]">
          {verified ? (
            <Shield size={16} className="text-[#8B5A2B]" />
          ) : (
            <ShieldOff size={16} className="text-[#8B5A2B]" />
          )}
        </div>
        <h2 className="font-display text-lg font-semibold text-[#3B2314]">
          Two-Factor Authentication
        </h2>
      </div>

      <div className="p-6">
        {factors === null ? (
          <p className="text-sm text-[#6B5C4E]">Loading 2FA status…</p>
        ) : enrollment ? (
          /* ── Enrollment flow: QR + secret + confirm ── */
          <div className="space-y-4">
            <p className="text-sm text-[#6B5C4E]">
              Scan this QR code with your authenticator app (Google
              Authenticator, Authy, 1Password…), then enter the 6-digit code
              it shows to confirm.
            </p>
            <div className="flex justify-center">
              <img
                src={`data:image/svg+xml;utf8,${encodeURIComponent(
                  enrollment.totp?.qr_code ?? '',
                )}`}
                alt="Authenticator QR code"
                className="h-48 w-48 rounded-xl border border-[#F5F0EB] bg-white p-2"
              />
            </div>
            <div>
              <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Or enter this code manually
              </label>
              <input
                readOnly
                value={enrollment.totp?.secret ?? ''}
                onFocus={(e) => e.target.select()}
                className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 font-mono text-sm text-[#3B2314]"
              />
            </div>
            <form onSubmit={handleConfirm} className="space-y-3">
              <div>
                <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                  6-digit code
                </label>
                <input
                  type="text"
                  inputMode="numeric"
                  maxLength={6}
                  value={confirmCode}
                  onChange={(e) =>
                    setConfirmCode(e.target.value.replace(/\D/g, ''))
                  }
                  placeholder="123456"
                  className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 text-center text-xl font-bold tracking-[0.4em] text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
                />
              </div>
              {confirmError && (
                <p className="text-sm text-red-600">{confirmError}</p>
              )}
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={abortEnrollment}
                  className="inline-flex items-center gap-1.5 rounded-xl border border-[#D9D0C7] px-4 py-2.5 text-sm font-semibold text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB]"
                >
                  <X size={16} /> Cancel
                </button>
                <button
                  type="submit"
                  disabled={confirming || confirmCode.length !== 6}
                  className="flex-1 rounded-xl bg-[#8B5A2B] px-6 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-[#6B4520] disabled:opacity-50"
                >
                  {confirming ? 'Confirming…' : 'Confirm & Turn On'}
                </button>
              </div>
            </form>
          </div>
        ) : verified ? (
          /* ── Enabled state ── */
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="text-sm font-semibold text-[#3B2314]">
                2FA is on
              </p>
              <p className="text-sm text-[#6B5C4E]">
                Sign-ins require a code from your authenticator app.
              </p>
            </div>
            <button
              type="button"
              onClick={handleDisable}
              className="rounded-xl border border-red-300 px-4 py-2 text-sm font-semibold text-red-600 transition-colors hover:bg-red-50"
            >
              Disable
            </button>
          </div>
        ) : (
          /* ── Disabled state ── */
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="text-sm font-semibold text-[#3B2314]">
                2FA is off
              </p>
              <p className="text-sm text-[#6B5C4E]">
                Add an extra layer of protection for this admin account.
              </p>
            </div>
            <button
              type="button"
              onClick={handleEnable}
              disabled={enrolling}
              className="rounded-xl bg-[#8B5A2B] px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-[#6B4520] disabled:opacity-50"
            >
              {enrolling ? 'Setting up…' : 'Enable 2FA'}
            </button>
          </div>
        )}
      </div>
    </div>
  )
}