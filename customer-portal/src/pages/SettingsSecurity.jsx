import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowLeft, AtSign, KeyRound, Smartphone } from 'lucide-react'

import PasswordForm from '../components/account/PasswordForm'
import Field from '../components/ui/Field'
import Reveal from '../components/ui/Reveal'
import { useAuth } from '../hooks/useAuth.jsx'
import {
  emailChangeErrors,
  emailChangeError,
  emailChangeSentMessage,
} from '../lib/securityRules'

/**
 * Account & Security.
 *
 * The app's security screen offers thirteen rows; this is the four that are
 * real in a browser, and the rest are named at the foot rather than shown as
 * buttons that go nowhere:
 *
 *   • email change      — the same GoTrue `updateUser` call the app makes
 *   • password          — the shared `PasswordForm`
 *   • phone             — a `profiles` column, edited on the account page
 *   • (no) 2FA, passkeys, device list, biometrics, account activity — all of
 *     these are either device-local (biometrics), or need a session/device
 *     inventory the anon client cannot read, or are a GoTrue MFA enrolment
 *     flow the portal has not built
 *
 * The email change is the subtle one, and the copy does the work: nothing has
 * changed when the request succeeds. GoTrue emails the new address a
 * confirmation link and the old address a notice, and the sign-in address
 * follows the link — not this button.
 */
export default function SettingsSecurity() {
  const { user, profile, updateEmail } = useAuth()

  const [changing, setChanging] = useState(false)
  const [next, setNext] = useState('')
  const [error, setError] = useState(null)
  const [sent, setSent] = useState(null)
  const [saving, setSaving] = useState(false)

  const currentEmail = profile?.email || user?.email || ''

  const onSubmitEmail = async (event) => {
    event.preventDefault()

    const errors = emailChangeErrors({ next, current: currentEmail })
    if (errors.email) {
      setError(errors.email)
      return
    }

    setError(null)
    setSaving(true)
    try {
      await updateEmail(next)
      setSent(emailChangeSentMessage(next))
      setChanging(false)
      setNext('')
    } catch (failure) {
      setError(emailChangeError(failure))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-10 sm:px-6 lg:px-8">
      <Link
        to="/settings"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-muted transition-colors duration-200 hover:text-ink"
      >
        <ArrowLeft size={14} strokeWidth={2} />
        Settings
      </Link>

      <header className="mt-4">
        <p className="overline">Account</p>
        <h1 className="mt-2 font-display text-3xl font-semibold text-ink">
          Account &amp; Security
        </h1>
      </header>

      {sent && (
        <p
          role="status"
          className="mt-6 rounded-card border border-olive/40 bg-olive/[0.08] px-4 py-3 text-sm leading-relaxed text-ink"
        >
          {sent}
        </p>
      )}

      {/* ── Sign-in email ─────────────────────────────────────────── */}
      <Reveal className="mt-8 rounded-card border border-hairline bg-raised p-6 shadow-card">
        <div className="flex items-center gap-3">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-premium bg-clay/10">
            <AtSign size={18} className="text-clay-ink" strokeWidth={1.75} />
          </span>
          <div className="min-w-0 flex-1">
            <h2 className="font-display text-lg font-semibold text-ink">
              Sign-in email
            </h2>
            <p className="mt-0.5 truncate text-xs text-muted">{currentEmail}</p>
          </div>

          {!changing && (
            <button
              type="button"
              onClick={() => {
                setSent(null)
                setError(null)
                setChanging(true)
              }}
              className="btn btn-outline shrink-0"
            >
              Change
            </button>
          )}
        </div>

        {changing ? (
          <form onSubmit={onSubmitEmail} className="mt-5 space-y-4" noValidate>
            <Field
              id="new-email"
              label="New email address"
              type="email"
              value={next}
              onChange={(value) => {
                setNext(value)
                setError(null)
              }}
              autoComplete="email"
              error={error}
              autoFocus
              required
            />

            <div className="flex flex-wrap gap-2">
              <button type="submit" disabled={saving} className="btn btn-primary">
                {saving ? 'Sending…' : 'Send verification'}
              </button>
              <button
                type="button"
                onClick={() => {
                  setChanging(false)
                  setNext('')
                  setError(null)
                }}
                className="btn btn-outline"
              >
                Cancel
              </button>
            </div>

            <p className="text-xs leading-relaxed text-muted">
              We send a confirmation link to the new address, and a warning to
              your current one. The change happens only when the link is
              opened — so if someone else asks for this on your account, the
              notice is how you find out.
            </p>
          </form>
        ) : (
          !sent && (
            <p className="mt-4 text-sm leading-relaxed text-muted">
              This is how you sign in, and where order confirmations go. It is
              kept read-only on your details page for that reason: changing it
              has to be confirmed from the new mailbox, not typed into a form.
            </p>
          )
        )}
      </Reveal>

      {/* ── Password ──────────────────────────────────────────────── */}
      <Reveal
        delay={0.05}
        className="mt-6 rounded-card border border-hairline bg-raised p-6 shadow-card"
      >
        <div className="flex items-center gap-3">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-premium bg-clay/10">
            <KeyRound size={18} className="text-clay-ink" strokeWidth={1.75} />
          </span>
          <div>
            <h2 className="font-display text-lg font-semibold text-ink">
              Password
            </h2>
            <p className="mt-0.5 text-xs text-muted">
              Change the password you sign in with.
            </p>
          </div>
        </div>

        <div className="mt-5">
          <PasswordForm idPrefix="security-password" />
        </div>
      </Reveal>

      {/* ── Phone ─────────────────────────────────────────────────── */}
      <Reveal
        delay={0.1}
        className="mt-6 rounded-card border border-hairline bg-raised p-6 shadow-card"
      >
        <div className="flex items-center gap-3">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-premium bg-clay/10">
            <Smartphone size={18} className="text-clay-ink" strokeWidth={1.75} />
          </span>
          <div className="min-w-0 flex-1">
            <h2 className="font-display text-lg font-semibold text-ink">
              Mobile number
            </h2>
            <p className="mt-0.5 truncate text-xs text-muted">
              {profile?.phone || 'Not set yet'}
            </p>
          </div>
          <Link to="/account" className="btn btn-outline shrink-0">
            {profile?.phone ? 'Change' : 'Add'}
          </Link>
        </div>
      </Reveal>

      <p className="mt-6 text-xs leading-relaxed text-muted">
        Two-factor authentication, passkeys, the device list and account
        activity are part of the CUFMAI app, where a phone can hold the keys
        they depend on. Your email and password are the same account in both
        places.
      </p>
    </div>
  )
}
