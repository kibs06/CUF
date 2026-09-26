import { useEffect, useMemo, useState } from 'react'
import { Check } from 'lucide-react'

import AvatarUpload from './AvatarUpload'
import Field from '../ui/Field'
import { useAuth } from '../../hooks/useAuth.jsx'
import {
  emptyProfileDraft,
  profileDraftFromRow,
  profileError,
  profileErrors,
  profileIsDirty,
  profileUpdatePayload,
  sameProfilePayload,
} from '../../lib/profile'
import { GENDER_OPTIONS } from '../../lib/signupRules'

/**
 * Your details, editable.
 *
 * One form rather than the app's four per-field dialogs: on a phone a dialog
 * per field is a reasonable trade for screen space, and on a page that is
 * already tall it is four round trips to change a name and a birthday.
 *
 * ## Two things it is careful about
 *
 * 1. **It re-seeds from the profile row, not from the payload it sent.** A save
 *    normalises — trimming, turning empty strings into NULLs — so re-reading
 *    what the database stored is what makes "no unsaved changes" true instead
 *    of approximately true.
 * 2. **It validates on submit, then live afterwards.** A customer who has just
 *    been told their phone number is incomplete should see the message clear as
 *    they fix it, not on the next attempt.
 *
 * Email is deliberately absent: changing a sign-in address is a GoTrue
 * verification flow (the app calls `auth.updateEmail`, which mails a link), not
 * a column write, and doing it half-way here would leave
 * `auth.users.email` and `profiles.email` disagreeing. It is shown read-only
 * rather than hidden, so nobody goes looking for it.
 */
export default function ProfileForm() {
  const { profile, user, updateProfile, isSeller, isAdmin } = useAuth()

  const [draft, setDraft] = useState(() =>
    profile ? profileDraftFromRow(profile) : emptyProfileDraft(),
  )
  const [errors, setErrors] = useState({})
  const [problem, setProblem] = useState(null)
  const [pending, setPending] = useState(false)

  /*
    The payload of the last successful save, held so the confirmation can be
    DERIVED rather than remembered. A boolean flag could not survive this
    component's own re-seed: the save replaces the profile row, which re-runs
    the effect below, and a `setSaved(false)` in there erased the confirmation
    before it was ever painted — caught by driving the real form, where the
    row updated and the "saved" message never appeared. Comparing what is on
    screen with what we sent is true after the save, and false the moment
    anything is edited again.
  */
  const [savedPayload, setSavedPayload] = useState(null)

  // Re-seed whenever the row itself changes — after a save, after a refresh,
  // or when a different account signs in.
  useEffect(() => {
    const row = profile ? profileDraftFromRow(profile) : emptyProfileDraft()
    setDraft(row)
    setErrors({})
    setProblem(null)
    setSavedPayload((current) =>
      current && sameProfilePayload(current, profileUpdatePayload(row))
        ? current
        : null,
    )
  }, [profile])

  const dirty = useMemo(
    () => profileIsDirty(draft, profile ?? {}),
    [draft, profile],
  )

  const set = (field) => (value) => {
    setDraft((current) => ({ ...current, [field]: value }))
    // Clear the field's error as soon as the customer edits it, so the message
    // never contradicts what is on screen.
    setErrors((current) => {
      if (!current[field]) return current
      const next = { ...current }
      delete next[field]
      return next
    })
  }

  const onSubmit = async (event) => {
    event.preventDefault()
    setSavedPayload(null)
    setProblem(null)

    const found = profileErrors(draft)
    setErrors(found)
    if (Object.keys(found).length > 0) {
      setProblem('Some details need fixing before we can save.')
      return
    }

    setPending(true)
    const payload = profileUpdatePayload(draft)
    try {
      await updateProfile(payload)
      setSavedPayload(payload)
    } catch (error) {
      setProblem(profileError(error).message)
    } finally {
      setPending(false)
    }
  }

  const saved = Boolean(
    savedPayload &&
      !dirty &&
      sameProfilePayload(savedPayload, profileUpdatePayload(draft)),
  )

  return (
    <div className="rounded-card border border-hairline bg-raised p-6 shadow-card">
      <h2 className="font-display text-xl font-semibold text-ink">
        Your details
      </h2>
      <p className="mt-1 text-xs leading-relaxed text-muted">
        The same account as the CUFMAI app — change it here and your phone has
        it too.
      </p>

      <div className="mt-6 border-b border-hairline-soft pb-6">
        <AvatarUpload onChanged={() => setSavedPayload(null)} />
      </div>

      <form onSubmit={onSubmit} className="mt-6 space-y-5" noValidate>
        <Field
          id="profile-name"
          label="Full name"
          value={draft.fullName}
          onChange={set('fullName')}
          error={errors.fullName}
          autoComplete="name"
          placeholder="Ana Reyes"
          required
        />

        <Field
          id="profile-email"
          label="Email"
          value={profile?.email ?? user?.email ?? ''}
          hint="Your sign-in email. Changing it is not available here yet."
          disabled
        />

        <Field
          id="profile-phone"
          label="Mobile number"
          type="tel"
          value={draft.phone}
          onChange={set('phone')}
          error={errors.phone}
          autoComplete="tel"
          placeholder="0917 123 4567"
          hint="Only used by the maker delivering your order."
        />

        <div className="grid gap-5 sm:grid-cols-2">
          <Field
            id="profile-birthday"
            label="Birthday"
            type="date"
            value={draft.birthday}
            onChange={set('birthday')}
            error={errors.birthday}
            max={todayInputValue()}
          />

          <Field
            id="profile-gender"
            label="Gender"
            error={errors.gender}
          >
            <select
              id="profile-gender"
              value={draft.genderOption}
              onChange={(event) => set('genderOption')(event.target.value)}
              className="mt-2 h-11 w-full rounded-field border border-hairline bg-raised px-3 text-sm text-ink transition-colors duration-200 ease-out-cubic hover:border-card-edge focus:border-clay"
            >
              <option value="">Not set</option>
              {GENDER_OPTIONS.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </select>
          </Field>
        </div>

        {draft.genderOption === 'Self-describe' && (
          <Field
            id="profile-gender-self"
            label="How do you describe yourself?"
            value={draft.genderSelfDescribe}
            onChange={set('genderSelfDescribe')}
            maxLength={80}
            required
          />
        )}

        <Field
          id="profile-bio"
          label="About you"
          hint="Optional. Shown to a maker when you message them."
        >
          <textarea
            id="profile-bio"
            rows={3}
            value={draft.bio}
            onChange={(event) => set('bio')(event.target.value)}
            maxLength={300}
            className="mt-2 w-full resize-none rounded-field border border-hairline bg-raised px-4 py-3 text-sm text-ink transition-colors duration-200 ease-out-cubic placeholder:text-muted/60 hover:border-card-edge focus:border-clay"
          />
        </Field>

        <div className="rounded-field border border-hairline-soft bg-subtle/50 px-4 py-3">
          <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-muted">
            Account type
          </p>
          <p className="mt-1 text-sm text-ink">
            {accountTypeLabel({ isSeller, isAdmin })}
          </p>
          <p className="mt-1 text-xs leading-relaxed text-muted">
            Set by CUFMAI. Seller tools live in the app.
          </p>
        </div>

        {problem && (
          <p
            role="alert"
            className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm leading-relaxed text-ink"
          >
            {problem}
          </p>
        )}

        {saved && (
          <p
            role="status"
            className="flex items-center gap-2 rounded-field border border-olive/30 bg-olive/[0.07] px-4 py-3 text-sm text-ink"
          >
            <Check size={15} strokeWidth={2.5} className="shrink-0 text-olive" />
            Your details are saved.
          </p>
        )}

        <div className="flex flex-wrap items-center gap-3">
          <button
            type="submit"
            disabled={pending || !dirty}
            className="btn btn-primary disabled:cursor-not-allowed disabled:opacity-60"
          >
            {pending ? 'Saving…' : 'Save changes'}
          </button>

          {dirty && !pending && (
            <button
              type="button"
              onClick={() => {
                setDraft(profileDraftFromRow(profile ?? {}))
                setErrors({})
                setProblem(null)
                setSavedPayload(null)
              }}
              className="btn btn-outline"
            >
              Discard
            </button>
          )}

          <span className="text-xs text-muted">
            {dirty ? 'Unsaved changes' : 'Everything is up to date'}
          </span>
        </div>
      </form>
    </div>
  )
}

/** `YYYY-MM-DD` for today, so the date picker cannot offer the future. */
function todayInputValue() {
  const now = new Date()
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const day = String(now.getDate()).padStart(2, '0')
  return `${now.getFullYear()}-${month}-${day}`
}

function accountTypeLabel({ isSeller, isAdmin }) {
  if (isAdmin) return 'Administrator'
  if (isSeller) return 'CUFMAI member artisan'
  return 'Customer'
}
