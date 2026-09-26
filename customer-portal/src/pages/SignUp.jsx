import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'

import AuthShell from '../components/auth/AuthShell'
import Field from '../components/ui/Field'
import { useAuth } from '../hooks/useAuth.jsx'
import {
  GENDER_OPTIONS,
  formatBirthdayForDb,
  resolveGenderValue,
  validateBirthday,
  validateGenderSelfDescribe,
} from '../lib/signupRules.js'

const MINIMUM_PASSWORD_LENGTH = 8

export default function SignUp() {
  const navigate = useNavigate()
  const { signUp } = useAuth()

  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [phone, setPhone] = useState('')
  const [birthday, setBirthday] = useState('')
  const [gender, setGender] = useState('')
  const [genderText, setGenderText] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')

  const [errors, setErrors] = useState({})
  const [formError, setFormError] = useState(null)
  const [submitting, setSubmitting] = useState(false)
  const [awaitingEmail, setAwaitingEmail] = useState(false)

  const validate = () => {
    const next = {}

    if (!fullName.trim()) next.fullName = 'Enter your full name'
    if (!email.trim()) next.email = 'Enter your email address'

    // The app's own policy: mandatory, not in the future, 13+ by calendar year.
    const birthdayError = validateBirthday(birthday)
    if (birthdayError) next.birthday = birthdayError

    const genderError = validateGenderSelfDescribe(gender, genderText)
    if (genderError) next.gender = genderError

    if (!password) {
      next.password = 'Choose a password'
    } else if (password.length < MINIMUM_PASSWORD_LENGTH) {
      next.password = `Use at least ${MINIMUM_PASSWORD_LENGTH} characters`
    }

    if (confirm !== password) next.confirm = 'The two passwords do not match'

    setErrors(next)
    return Object.keys(next).length === 0
  }

  const onSubmit = async (event) => {
    event.preventDefault()
    if (!validate()) return

    setSubmitting(true)
    setFormError(null)
    try {
      const result = await signUp({
        fullName,
        email,
        password,
        phone: phone.trim() || null,
        birthday: formatBirthdayForDb(birthday),
        gender: resolveGenderValue(gender, genderText),
      })

      // With e-mail confirmation on, `signUp` returns no session — and with no
      // session there is no profile row to write (RLS requires `auth.uid() =
      // id`). The confirmation link finishes it; see lib/auth.js.
      // A fallback guest checkout is not built, so the only success path with
      // a session goes straight to the account page.
      if (result.emailVerificationRequired) setAwaitingEmail(true)
      else navigate('/account', { replace: true })
    } catch (error) {
      setFormError(
        error?.message ?? 'We could not create your account. Please try again.',
      )
    } finally {
      setSubmitting(false)
    }
  }

  if (awaitingEmail) {
    return (
      <AuthShell
        title="Check your email"
        subtitle="One more step and your account is ready."
        footer={
          <>
            Wrong address?{' '}
            <button
              type="button"
              onClick={() => setAwaitingEmail(false)}
              className="font-semibold text-clay-ink underline-offset-4 hover:underline"
            >
              Go back and change it
            </button>
          </>
        }
      >
        <p className="text-sm leading-relaxed text-muted">
          We sent a confirmation link to{' '}
          <span className="font-semibold text-ink">{email.trim()}</span>. Open it
          in this browser to confirm your account and finish setting up your
          profile.
        </p>
        <p className="mt-4 text-xs text-muted">
          The link expires after a while. If it stops working, sign in and we
          will send a fresh one.
        </p>
      </AuthShell>
    )
  }

  return (
    <AuthShell
      title="Create your account"
      subtitle="Your cart follows you between this site and the CUFMAI app."
      footer={
        <>
          Already have an account?{' '}
          <Link
            to="/signin"
            className="font-semibold text-clay-ink underline-offset-4 hover:underline"
          >
            Sign in
          </Link>
        </>
      }
    >
      <form onSubmit={onSubmit} className="space-y-5" noValidate>
        <Field
          id="fullName"
          label="Full name"
          value={fullName}
          onChange={setFullName}
          error={errors.fullName}
          autoComplete="name"
          required
          placeholder="Juan dela Cruz"
        />

        <Field
          id="email"
          label="Email"
          type="email"
          value={email}
          onChange={setEmail}
          error={errors.email}
          autoComplete="email"
          required
          placeholder="you@example.com"
        />

        <Field
          id="phone"
          label="Mobile number"
          type="tel"
          value={phone}
          onChange={setPhone}
          autoComplete="tel"
          placeholder="09XX XXX XXXX"
          hint="Sellers use this to arrange delivery."
        />

        <Field
          id="birthday"
          label="Birthday"
          type="date"
          value={birthday}
          onChange={setBirthday}
          error={errors.birthday}
          autoComplete="bday"
          required
        />

        <Field id="gender" label="Gender" error={errors.gender}>
          <select
            id="gender"
            value={gender}
            onChange={(event) => setGender(event.target.value)}
            className="mt-2 h-11 w-full rounded-field border border-hairline bg-raised px-4 text-sm text-ink transition-colors duration-200 ease-out-cubic hover:border-card-edge focus:border-clay"
          >
            <option value="">Prefer not to say</option>
            {GENDER_OPTIONS.filter((option) => option !== 'Prefer not to say').map(
              (option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ),
            )}
          </select>
        </Field>

        {gender === 'Self-describe' && (
          <Field
            id="genderText"
            label="How you describe yourself"
            value={genderText}
            onChange={setGenderText}
            required
            placeholder="Your words"
          />
        )}

        <Field
          id="password"
          label="Password"
          type="password"
          value={password}
          onChange={setPassword}
          error={errors.password}
          autoComplete="new-password"
          required
          hint={`At least ${MINIMUM_PASSWORD_LENGTH} characters.`}
        />

        <Field
          id="confirm"
          label="Confirm password"
          type="password"
          value={confirm}
          onChange={setConfirm}
          error={errors.confirm}
          autoComplete="new-password"
          required
        />

        {formError && (
          <div
            role="alert"
            className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm text-ink"
          >
            {formError}
          </div>
        )}

        <button type="submit" disabled={submitting} className="btn btn-primary w-full">
          {submitting ? 'Creating your account…' : 'Create account'}
        </button>

        <p className="text-center text-xs leading-relaxed text-muted">
          Seller accounts are created in the CUFMAI app — this storefront is for
          shopping.
        </p>
      </form>
    </AuthShell>
  )
}
