import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'

import AuthErrorSummary from '../components/auth/AuthErrorSummary'
import AuthShell from '../components/auth/AuthShell'
import StepIndicator from '../components/auth/StepIndicator'
import Field from '../components/ui/Field'
import PasswordField from '../components/ui/PasswordField'
import { useAuth } from '../hooks/useAuth.jsx'
import {
  GENDER_OPTIONS,
  formatBirthdayForDb,
  resolveGenderValue,
  validateBirthday,
  validateGenderSelfDescribe,
} from '../lib/signupRules.js'

const MINIMUM_PASSWORD_LENGTH = 8

const STEP_LINKS = [
  { email: 'email', password: 'password', confirm: 'confirm' },
  {
    fullName: 'fullName',
    birthday: 'birthday',
    gender: 'gender',
  },
]

function isEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value ?? '').trim())
}

/**
 * Customer signup, in two short screens rather than one long form.
 *
 * Only the account itself (email + password) is needed to create access, so
 * that is step one — three fields, one decision. The profile (name, birthday,
 * phone, gender) follows, with each surprising question explained where it is
 * asked: the birthday is the 13+ age check, the phone is for deliveries, and
 * gender stays optional. Nothing about the account created is different from
 * the old single form — the same fields, the same validation, the same
 * confirmation flow — only the order and the grouping changed.
 */
export default function SignUp() {
  const navigate = useNavigate()
  const { signUp } = useAuth()

  const [step, setStep] = useState(0)

  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [phone, setPhone] = useState('')
  const [birthday, setBirthday] = useState('')
  const [gender, setGender] = useState('')
  const [genderText, setGenderText] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')

  const [errors, setErrors] = useState({})
  const [attempt, setAttempt] = useState(0)
  const [formError, setFormError] = useState(null)
  const [submitting, setSubmitting] = useState(false)
  const [awaitingEmail, setAwaitingEmail] = useState(false)

  const fail = (next) => {
    const ok = Object.keys(next).length === 0
    setErrors(next)
    if (!ok) setAttempt((count) => count + 1)
    return ok
  }

  const validateAccount = () => {
    const next = {}
    if (!email.trim()) next.email = 'Enter your email address'
    else if (!isEmail(email)) next.email = 'Enter a valid email address'
    if (!password) {
      next.password = 'Choose a password'
    } else if (password.length < MINIMUM_PASSWORD_LENGTH) {
      next.password = `Use at least ${MINIMUM_PASSWORD_LENGTH} characters`
    }
    if (confirm !== password) next.confirm = 'The two passwords do not match'
    return fail(next)
  }

  const validateProfile = () => {
    const next = {}

    if (!fullName.trim()) next.fullName = 'Enter your full name'

    // The app's own policy: mandatory, not in the future, 13+ by calendar year.
    const birthdayError = validateBirthday(birthday)
    if (birthdayError) next.birthday = birthdayError

    const genderError = validateGenderSelfDescribe(gender, genderText)
    if (genderError) next.gender = genderError

    return fail(next)
  }

  const goNext = () => {
    if (!validateAccount()) return
    setErrors({})
    setStep(1)
  }

  const onSubmit = async (event) => {
    event.preventDefault()
    if (!validateProfile()) return

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
      subtitle={
        step === 0
          ? 'Takes about 30 seconds — your details come next.'
          : 'Last step — tell us who the account belongs to.'
      }
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
      <StepIndicator steps={['Account', 'Profile']} current={step} onSelect={setStep} />

      {Object.keys(errors).length > 0 && (
        <div className="mb-5">
          <AuthErrorSummary
            key={`${step}-${attempt}`}
            errors={errors}
            links={STEP_LINKS[step]}
          />
        </div>
      )}

      {step === 0 && (
        <form
          onSubmit={(event) => {
            event.preventDefault()
            goNext()
          }}
          className="space-y-5"
          noValidate
        >
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
            hint="Your sign-in and order updates live here."
          />

          <PasswordField
            id="password"
            label="Password"
            value={password}
            onChange={setPassword}
            error={errors.password}
            autoComplete="new-password"
            required
            hint={`At least ${MINIMUM_PASSWORD_LENGTH} characters.`}
          />

          <PasswordField
            id="confirm"
            label="Confirm password"
            value={confirm}
            onChange={setConfirm}
            error={errors.confirm}
            autoComplete="new-password"
            required
          />

          <button type="submit" className="btn btn-primary w-full">
            Continue
          </button>

          <p className="text-center text-xs leading-relaxed text-muted">
            A shoemaker or artisan?{' '}
            <Link
              to="/signup/seller"
              className="font-semibold text-clay-ink underline-offset-4 hover:underline"
            >
              Apply to sell
            </Link>{' '}
            — the same application as the CUFMAI app.
          </p>
        </form>
      )}

      {step === 1 && (
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
            hint="What sellers and receipts call you."
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
            hint="To confirm you are 13 or older — nothing else."
          />

          <Field
            id="phone"
            label="Mobile number"
            type="tel"
            value={phone}
            onChange={setPhone}
            autoComplete="tel"
            placeholder="09XX XXX XXXX"
            hint="Only used to arrange deliveries."
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
          <button
            type="button"
            onClick={() => {
              setErrors({})
              setStep(0)
            }}
            disabled={submitting}
            className="w-full cursor-pointer text-xs font-semibold text-muted underline-offset-4 transition-colors duration-200 ease-out-cubic hover:text-clay-ink hover:underline disabled:cursor-default disabled:opacity-60"
          >
            Back to account
          </button>
        </form>
      )}
    </AuthShell>
  )
}
