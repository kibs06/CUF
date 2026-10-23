import { useEffect, useState } from 'react'
import { Link, Navigate, useNavigate } from 'react-router-dom'

import AuthShell from '../components/auth/AuthShell'
import { useAuth } from '../hooks/useAuth.jsx'
import { supabase } from '../lib/supabase'
import {
  socialCallbackErrorMessage,
  takePostLoginDestination,
} from '../lib/socialAuth'
import { ROLES } from '../lib/constants'

/**
 * Return leg of storefront social sign-in (`/auth/callback`).
 *
 * Exchanges the provider `code` for a Supabase session, then lets the shared
 * `useAuth` gate decide: suspended accounts are signed straight back out
 * there, everyone else lands by role (sellers in their workshop, customers
 * where they were headed). Social login never grants anything beyond the
 * profile row — sellers still apply via `/signup/seller`.
 */
export default function AuthCallback() {
  const navigate = useNavigate()
  const { session, profile, loading, accessDenied } = useAuth()
  const [exchangeError, setExchangeError] = useState(null)
  const [exchanging, setExchanging] = useState(true)

  useEffect(() => {
    let cancelled = false

    async function run() {
      try {
        const params = new URLSearchParams(
          (window.location.hash || window.location.search).replace(/^#/, ''),
        )
        const described =
          params.get('error_description') ?? params.get('error')
        if (described) {
          if (!cancelled) {
            setExchangeError(
              socialCallbackErrorMessage(params) ||
                'That sign-in link did not work. Please try again.',
            )
          }
          return
        }
        const code = params.get('code')
        if (code) {
          const { error } = await supabase.auth.exchangeCodeForSession(code)
          if (error) {
            if (!cancelled) {
              setExchangeError(
                error.message || 'That sign-in link did not work. Please try again.',
              )
            }
            return
          }
        }
        // No code = implicit-flow session: onAuthStateChange picks it up.
      } catch (error) {
        if (!cancelled) {
          setExchangeError(
            error?.message || 'That sign-in link did not work. Please try again.',
          )
        }
      } finally {
        if (!cancelled) setExchanging(false)
      }
    }

    run()
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    if (exchanging || loading || exchangeError) return
    if (!session?.user) return
    // Suspended social users are already signed out by the gate with
    // accessDenied set — send them to sign-in, which explains why.
    if (accessDenied) {
      navigate('/signin', { replace: true })
      return
    }
    // No email from the provider (common on Facebook): the account works,
    // but order updates need an address — collect it where email is edited.
    if (!session.user.email) {
      navigate('/settings/security', {
        replace: true,
        state: { socialEmailMissing: true },
      })
      return
    }
    const fallback =
      profile?.role === ROLES.SELLER ? '/seller' : '/account'
    navigate(takePostLoginDestination() ?? fallback, { replace: true })
  }, [exchanging, loading, exchangeError, session, profile, accessDenied, navigate])

  if (exchangeError) {
    return (
      <AuthShell
        title="That sign-in did not finish"
        subtitle="Nothing is lost — you can pick up where you left off."
        footer={
          <>
            Trouble signing in?{' '}
            <Link
              to="/signin"
              className="font-semibold text-clay-ink underline-offset-4 hover:underline"
            >
              Try again
            </Link>
          </>
        }
      >
        <div
          role="alert"
          className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm leading-relaxed text-ink"
        >
          {exchangeError}
        </div>
      </AuthShell>
    )
  }

  if (!exchanging && !loading && !session?.user) {
    return <Navigate to="/signin" replace />
  }

  return (
    <AuthShell
      title="Signing you in"
      subtitle="This takes a moment."
    >
      <div className="space-y-4">
        <div className="shimmer h-4 w-5/6 rounded" />
        <div className="shimmer h-4 w-2/3 rounded" />
        <div className="shimmer h-11 w-full rounded-field" />
      </div>
    </AuthShell>
  )
}
