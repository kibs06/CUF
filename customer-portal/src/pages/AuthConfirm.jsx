import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'

import AuthShell from '../components/auth/AuthShell'
import { useAuth } from '../hooks/useAuth.jsx'
import { supabase } from '../lib/supabase'

const WAIT_STEPS = 24
const WAIT_INTERVAL_MS = 250

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

/**
 * Where the confirmation e-mail lands.
 *
 * Two things happen here that nothing else can do for us:
 *
 *  1. `supabase-js` parses the tokens out of the URL and establishes the
 *     session (its `detectSessionInUrl`). That is asynchronous, so this page
 *     waits for a session rather than assuming one — a cold browser opening the
 *     link from an e-mail client has nothing else to go on.
 *  2. The `profiles` row is written from the sign-up metadata. It could NOT be
 *     written at sign-up time: with e-mail confirmation on there is no session
 *     yet, and the INSERT policy is `auth.uid() = id`.
 */
export default function AuthConfirm() {
  const navigate = useNavigate()
  const { completeSignupFromEmailLink } = useAuth()
  const [failure, setFailure] = useState(null)

  useEffect(() => {
    let cancelled = false

    async function finish() {
      // A link the provider already refused carries why, in the fragment.
      const params = new URLSearchParams(
        (window.location.hash || window.location.search).replace(/^#/, ''),
      )
      const described =
        params.get('error_description') ?? params.get('error')
      if (described) {
        if (!cancelled) setFailure(described.replace(/\+/g, ' '))
        return
      }

      for (let attempt = 0; attempt < WAIT_STEPS; attempt += 1) {
        const { data } = await supabase.auth.getSession()
        if (data?.session) {
          try {
            await completeSignupFromEmailLink()
          } catch {
            // Signed in but the profile write failed. Not fatal: the account
            // exists, and `fetchProfile`'s own last-resort branch will create
            // the row on the next read.
          }
          if (cancelled) return
          navigate('/account', { replace: true })
          return
        }
        await sleep(WAIT_INTERVAL_MS)
      }

      if (!cancelled) {
        setFailure(
          'We could not confirm this link. It may have expired, or already been used — try signing in instead.',
        )
      }
    }

    finish()
    return () => {
      cancelled = true
    }
  }, [completeSignupFromEmailLink, navigate])

  return (
    <AuthShell
      title={failure ? 'That link did not work' : 'Confirming your account'}
      subtitle={
        failure
          ? 'Nothing is lost — you can pick up where you left off.'
          : 'This takes a moment.'
      }
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
      {failure ? (
        <div
          role="alert"
          className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm leading-relaxed text-ink"
        >
          {failure}
        </div>
      ) : (
        <div className="space-y-4">
          <div className="shimmer h-4 w-5/6 rounded" />
          <div className="shimmer h-4 w-2/3 rounded" />
          <div className="shimmer h-11 w-full rounded-field" />
        </div>
      )}
    </AuthShell>
  )
}
