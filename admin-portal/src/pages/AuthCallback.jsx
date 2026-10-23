import { useEffect, useState } from 'react'
import { Link, Navigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth.jsx'
import { socialCallbackErrorMessage } from '../lib/socialAuth'

/**
 * Return leg of portal social sign-in (`/auth/callback`).
 *
 * Exchanges the provider `code` for a Supabase session, then the shared
 * `useAuth` gate decides: admins proceed (ProtectedRoute sends them on,
 * via /mfa-verify when enrolled), everyone else is signed straight back out
 * with "Access denied" — social login never self-provisions an admin.
 */
export default function AuthCallback() {
  const { session, loading, isAdmin, accessDenied } = useAuth()
  const [exchangeError, setExchangeError] = useState('')
  const [exchanging, setExchanging] = useState(true)

  useEffect(() => {
    let cancelled = false

    async function run() {
      try {
        const params = new URLSearchParams(window.location.search)
        if (params.get('error')) {
          if (!cancelled) setExchangeError(socialCallbackErrorMessage(params))
          return
        }
        const code = params.get('code')
        if (code) {
          const { error } = await supabase.auth.exchangeCodeForSession(code)
          if (error) {
            if (!cancelled) setExchangeError(error.message || 'That sign-in link did not work. Please try again.')
            return
          }
        }
        // No code = implicit-flow session: onAuthStateChange picks it up.
      } catch (err) {
        if (!cancelled) setExchangeError(err?.message ?? 'That sign-in link did not work. Please try again.')
      } finally {
        if (!cancelled) setExchanging(false)
      }
    }

    run()
    return () => {
      cancelled = true
    }
  }, [])

  if (!exchanging && !loading) {
    if (exchangeError) {
      return (
        <div className="flex min-h-screen items-center justify-center bg-surface p-4">
          <div className="w-full max-w-md rounded-2xl border border-border bg-surface p-8 text-center shadow-sm">
            <h1 className="mb-2 font-display text-2xl font-bold text-secondary">Sign-in didn&apos;t finish</h1>
            <p className="mb-6 text-sm text-secondary/60">{exchangeError}</p>
            <Link to="/login" className="font-medium text-primary hover:underline">
              Back to sign in
            </Link>
          </div>
        </div>
      )
    }
    if (session && isAdmin) {
      return <Navigate to="/" replace />
    }
    if (accessDenied || session) {
      // Non-admin social user: useAuth already signed them out and flagged
      // accessDenied — bounce to the login screen that explains it.
      return <Navigate to="/login" replace />
    }
    return <Navigate to="/login" replace />
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface">
      <div className="h-10 w-10 animate-spin rounded-full border-4 border-primary border-t-transparent" />
    </div>
  )
}
