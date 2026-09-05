import { useState } from 'react'
import { Navigate } from 'react-router-dom'
import { SHOE_SOLE_SVG } from '../lib/constants'
import { useAuth } from '../hooks/useAuth.jsx'
import { needsMfa } from '../lib/mfa'

export default function Login() {
  const { signIn, session, isAdmin, loading, accessDenied } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  if (!loading && session && isAdmin) {
    // Admins with 2FA land on the code step instead of the dashboard.
    if (needsMfa(session)) {
      return <Navigate to="/mfa-verify" replace />
    }
    return <Navigate to="/" replace />
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    setSubmitting(true)
    try {
      await signIn(email, password)
    } catch (err) {
      setError(err.message ?? 'Login failed')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface p-4">
      <div className="w-full max-w-md rounded-2xl border border-border bg-surface p-8 shadow-sm">
        <div className="mx-auto mb-4 h-16 w-16 text-primary" dangerouslySetInnerHTML={{ __html: SHOE_SOLE_SVG }} />
        <h1 className="text-center font-display text-3xl font-bold text-secondary">Admin Portal</h1>
        <p className="mb-8 text-center text-sm text-secondary/60">SoleVision · Crafted Ground</p>

        {(error || accessDenied) && (
          <div className="mb-4 rounded-xl border border-error/30 bg-error/10 px-4 py-3 text-sm text-error">
            {error || 'Access denied. This portal is for admins only.'}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-secondary">Email</label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-xl border border-border bg-white px-4 py-2.5 text-secondary outline-none focus:border-primary"
              placeholder="admin@solevision.ph"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-secondary">Password</label>
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-xl border border-border bg-white px-4 py-2.5 text-secondary outline-none focus:border-primary"
              placeholder="••••••••"
            />
          </div>
          <button
            type="submit"
            disabled={submitting}
            className="w-full rounded-xl bg-primary px-4 py-2.5 font-medium text-white hover:bg-[#6B4520] disabled:opacity-60"
          >
            {submitting ? 'Signing in…' : 'Sign In'}
          </button>
        </form>
      </div>
    </div>
  )
}
