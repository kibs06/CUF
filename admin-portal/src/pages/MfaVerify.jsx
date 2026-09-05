import { useState } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { ShieldCheck } from 'lucide-react'
import { useAuth } from '../hooks/useAuth.jsx'
import { getVerifiedFactor, verifyLogin } from '../lib/mfa'

export default function MfaVerify() {
  const { session, loading } = useAuth()
  const navigate = useNavigate()
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  if (!loading && !session) return <Navigate to="/login" replace />

  const factor = getVerifiedFactor(session)
  // Reached manually without needing a code (e.g. already AAL2).
  if (!loading && session && !factor) return <Navigate to="/" replace />

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (submitting || !factor) return
    setSubmitting(true)
    setError('')
    try {
      await verifyLogin({ factorId: factor.id, code })
      navigate('/', { replace: true })
    } catch (err) {
      setError("That code didn't match or has expired. Try the next one.")
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface p-4">
      <div className="w-full max-w-md rounded-2xl border border-border bg-surface p-8 shadow-sm">
        <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-primary/10">
          <ShieldCheck className="h-8 w-8 text-primary" />
        </div>
        <h1 className="text-center font-display text-2xl font-bold text-secondary">
          Two-Step Verification
        </h1>
        <p className="mb-8 text-center text-sm text-secondary/60">
          Enter the 6-digit code from your authenticator app.
        </p>

        {error && (
          <div className="mb-4 rounded-xl border border-error/30 bg-error/10 px-4 py-3 text-sm text-error">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <input
            type="text"
            inputMode="numeric"
            autoComplete="one-time-code"
            required
            maxLength={6}
            autoFocus
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
            className="w-full rounded-xl border border-border bg-white px-4 py-3 text-center text-2xl font-bold tracking-[0.5em] text-secondary outline-none focus:border-primary"
            placeholder="······"
          />
          <button
            type="submit"
            disabled={submitting || code.length !== 6}
            className="w-full rounded-xl bg-primary px-4 py-2.5 font-medium text-white hover:bg-[#6B4520] disabled:opacity-60"
          >
            {submitting ? 'Verifying…' : 'Verify'}
          </button>
        </form>
      </div>
    </div>
  )
}