import { useState } from 'react'

import Field from '../ui/Field'
import { useAuth } from '../../hooks/useAuth.jsx'

export const MINIMUM_PASSWORD_LENGTH = 8

/**
 * Change the password.
 *
 * Extracted from the account page so Settings → Account & Security can offer it
 * too, rather than the security screen linking to "somewhere else on the site"
 * for the most security-shaped thing on the site. One implementation, two
 * doors: a second copy of this form is a second place for the minimum length
 * and the confirmation check to drift.
 *
 * The two rules are the app's: at least eight characters, and typed twice.
 * Nothing cleverer — length is what actually protects the account, and the
 * symbol-and-capital rules mostly produce passwords people write on a note.
 */
export default function PasswordForm({
  idPrefix = 'password',
  onDone = null,
  autoFocus = false,
}) {
  const { updatePassword } = useAuth()

  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [error, setError] = useState(null)
  const [done, setDone] = useState(false)
  const [saving, setSaving] = useState(false)

  const onSubmit = async (event) => {
    event.preventDefault()
    setDone(false)

    if (password.length < MINIMUM_PASSWORD_LENGTH) {
      setError(`Use at least ${MINIMUM_PASSWORD_LENGTH} characters`)
      return
    }
    if (password !== confirm) {
      setError('The two passwords do not match')
      return
    }

    setError(null)
    setSaving(true)
    try {
      await updatePassword(password)
      setPassword('')
      setConfirm('')
      setDone(true)
      onDone?.()
    } catch (failure) {
      setError(failure?.message ?? 'We could not update your password.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4" noValidate>
      <Field
        id={`${idPrefix}-new`}
        label="New password"
        type="password"
        value={password}
        onChange={setPassword}
        autoComplete="new-password"
        error={error}
        autoFocus={autoFocus}
        required
      />
      <Field
        id={`${idPrefix}-confirm`}
        label="Confirm"
        type="password"
        value={confirm}
        onChange={setConfirm}
        autoComplete="new-password"
        required
      />

      {done && (
        <p className="rounded-field border border-olive/30 bg-olive/[0.07] px-3 py-2 text-xs text-ink">
          Password updated.
        </p>
      )}

      <button type="submit" disabled={saving} className="btn btn-primary w-full">
        {saving ? 'Saving…' : 'Update password'}
      </button>

      <p className="text-xs leading-relaxed text-muted">
        At least {MINIMUM_PASSWORD_LENGTH} characters. Signing in on the app
        uses the same password, so this changes it in both places.
      </p>
    </form>
  )
}
