import { useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { Loader2 } from 'lucide-react'

import AuthShell from '../components/auth/AuthShell'
import Field from '../components/ui/Field'
import PasswordField from '../components/ui/PasswordField'
import { useAuth } from '../hooks/useAuth.jsx'
import { requestPasswordReset } from '../lib/auth'
import { ROLES } from '../lib/constants'

export default function SignIn() {
  const navigate = useNavigate()
  const location = useLocation()
  const { signIn } = useAuth()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [errors, setErrors] = useState({})
  const [formError, setFormError] = useState(null)
  const [submitting, setSubmitting] = useState(false)
  const [resetting, setResetting] = useState(false)
  const [resetSent, setResetSent] = useState(false)

  // Where the customer was headed before the gate. `replace` on the way out
  // keeps the sign-in page out of the history behind them.
  const destination = location.state?.from ?? null

  const validate = () => {
    const next = {}
    if (!email.trim()) next.email = 'Enter your email address'
    if (!password) next.password = 'Enter your password'
    setErrors(next)
    return Object.keys(next).length === 0
  }

  const onSubmit = async (event) => {
    event.preventDefault()
    if (!validate()) return

    setSubmitting(true)
    setFormError(null)
    try {
      const profile = await signIn(email, password)
      /*
        Where a sign-in lands when nobody was on the way anywhere.

        A seller goes to their workshop and a customer to their account, and the
        role is the only thing that can decide it — which is why `useAuth`'s
        `signIn` resolves to the profile rather than to a boolean. Asking before
        the sign-in would mean asking whoever is at the keyboard.

        `destination` is still preferred when it exists: a seller who clicked
        "Orders" on the storefront asked for that page, and the portal's job is to
        take them there rather than to assert where they belong.
      */
      const fallback = profile?.role === ROLES.SELLER ? '/seller' : '/account'
      navigate(destination ?? fallback, { replace: true })
    } catch (error) {
      setFormError(
        error?.message ?? 'We could not sign you in. Please try again.',
      )
    } finally {
      setSubmitting(false)
    }
  }

  const onReset = async (event) => {
    event.preventDefault()
    if (!email.trim()) {
      setErrors({ email: 'Enter your email address first' })
      return
    }

    setSubmitting(true)
    setFormError(null)
    try {
      await requestPasswordReset(email)
      setResetSent(true)
      setResetting(false)
    } catch (error) {
      setFormError(error?.message ?? 'We could not send that e-mail.')
    } finally {
      setSubmitting(false)
    }
  }

  /*
    The card says what the form under it does. It used to say "Welcome back"
    over a "Send reset link" button, which is how a customer who has forgotten
    their password ends up unsure whether they are signing in or resetting.
  */
  const heading = resetting
    ? { title: 'Reset your password', subtitle: 'We will e-mail you a link to choose a new one.' }
    : { title: 'Welcome back', subtitle: 'Sign in to see your cart and orders.' }

  return (
    <AuthShell
      title={heading.title}
      subtitle={heading.subtitle}
      footer={
        <>
          New to CUFMAI?{' '}
          <Link
            to="/signup"
            className="font-semibold text-clay-ink underline-offset-4 hover:underline"
          >
            Create an account
          </Link>
        </>
      }
    >
      {resetSent && (
        <div className="mb-5 rounded-field border border-olive/30 bg-olive/[0.07] px-4 py-3 text-sm leading-relaxed text-ink">
          If <span className="font-semibold">{email.trim()}</span> has an
          account, a reset link is on its way. Open it in this browser to choose
          a new password.
        </div>
      )}

      {resetting ? (
        <form onSubmit={onReset} className="space-y-5" noValidate>
          <Field
            id="reset-email"
            label="Email"
            type="email"
            value={email}
            onChange={setEmail}
            error={errors.email}
            autoComplete="email"
            autoFocus
            required
            placeholder="you@example.com"
            hint="Use the address on the account."
          />
          <button type="submit" disabled={submitting} className="btn btn-primary w-full">
            {submitting && <Loader2 size={15} className="animate-spin" />}
            {submitting ? 'Sending…' : 'Send reset link'}
          </button>
          <button
            type="button"
            onClick={() => {
              setResetting(false)
              setErrors({})
            }}
            className="w-full text-xs font-semibold text-muted underline-offset-4 transition-colors duration-200 ease-out-cubic hover:text-clay-ink hover:underline"
          >
            Back to sign in
          </button>
        </form>
      ) : (
        <form onSubmit={onSubmit} className="space-y-5" noValidate>
          <Field
            id="email"
            label="Email"
            type="email"
            value={email}
            onChange={setEmail}
            error={errors.email}
            autoComplete="email"
            autoFocus
            required
            placeholder="you@example.com"
          />

          {/*
            "Forgot?" rides on the label rather than sitting under the form as
            a second full-width button. Two stacked buttons of the same shape
            make the customer read the form twice to find the primary action;
            a link on the label line is where they look for it anyway.
          */}
          <PasswordField
            id="password"
            label="Password"
            value={password}
            onChange={setPassword}
            error={errors.password}
            autoComplete="current-password"
            required
            labelAction={
              <button
                type="button"
                onClick={() => {
                  setResetting(true)
                  setFormError(null)
                  setErrors({})
                }}
                className="text-xs font-semibold text-clay-ink underline-offset-4 hover:underline"
              >
                Forgot?
              </button>
            }
          />

          {formError && (
            <div
              role="alert"
              className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm leading-relaxed text-ink"
            >
              {formError}
            </div>
          )}

          <button type="submit" disabled={submitting} className="btn btn-primary w-full">
            {submitting && <Loader2 size={15} className="animate-spin" />}
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      )}
    </AuthShell>
  )
}
