import { phoneError } from './checkoutRules.js'
import { GENDER_OPTIONS, MINIMUM_SIGNUP_AGE, resolveGenderValue } from './signupRules.js'

/**
 * Profile-editing rules — the pure half of "edit your details".
 *
 * Only the parts that are NOT already in `signupRules.js` live here. `signupRules`
 * already owns the birthday policy, the gender options, the self-describe guard
 * and `formatBirthdayForDb`, and those are database rules that must not exist
 * twice: the account page and the sign-up page enforce the same 13-year
 * minimum, and a second copy would eventually disagree with the first.
 *
 * What is genuinely new here:
 *
 *   profileDraftFromRow   a `profiles` row → an editable draft, including the
 *                         gender round-trip that sign-up makes lossy (see below)
 *   profileUpdatePayload  a draft → the column names the table actually has
 *   avatarFileError       the client-side guard the Storage bucket cannot give
 *   withAvatarCacheBust   the app's `?t=` trick, because the storage path never
 *                         changes between uploads
 */

/**
 * Gender as the app stores it, back into a form selection.
 *
 * This round-trip is lossy on purpose and worth spelling out: picking
 * 'Self-describe' at sign-up persists the **free text itself** into
 * `profiles.gender` (`resolveGenderValue`), not the literal string
 * 'Self-describe'. So a stored value that is not one of the four options IS a
 * self-described one, and the reverse mapping has to infer that — otherwise
 * editing an unrelated field would silently rewrite somebody's gender to
 * 'Prefer not to say' or blank it.
 */
export function genderDraftFrom(value) {
  const stored = typeof value === 'string' ? value.trim() : ''
  if (!stored) return { option: '', selfDescribe: '' }
  if (GENDER_OPTIONS.includes(stored)) return { option: stored, selfDescribe: '' }
  return { option: 'Self-describe', selfDescribe: stored }
}

/** A `DATE` column arrives as `YYYY-MM-DD`; an `<input type="date">` wants exactly that. */
function dateInputValue(value) {
  const raw = String(value ?? '').trim()
  if (!raw) return ''
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(raw)
  return match ? `${match[1]}-${match[2]}-${match[3]}` : ''
}

/**
 * A profile row → the draft the form edits.
 *
 * Every field is a string, including the date, because that is what an input
 * holds; `profileUpdatePayload` is what turns them back into column values.
 */
export function profileDraftFromRow(profile) {
  const gender = genderDraftFrom(profile?.gender)

  return {
    fullName: profile?.full_name ?? '',
    phone: profile?.phone ?? '',
    birthday: dateInputValue(profile?.birthday),
    genderOption: gender.option,
    genderSelfDescribe: gender.selfDescribe,
    bio: profile?.bio ?? '',
  }
}

export function emptyProfileDraft() {
  return {
    fullName: '',
    phone: '',
    birthday: '',
    genderOption: '',
    genderSelfDescribe: '',
    bio: '',
  }
}

/** `YYYY-MM-DD` → a local Date at midnight, or null. */
export function parseDateInput(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value ?? '').trim())
  if (!match) return null

  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const date = new Date(year, month - 1, day)
  // Rejects 2026-02-31, which `new Date` would silently roll to 3 March.
  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    return null
  }
  return date
}

function todayAtMidnight() {
  const now = new Date()
  return new Date(now.getFullYear(), now.getMonth(), now.getDate())
}

/**
 * The birthday rule for an account that ALREADY exists.
 *
 * The accept/reject decision is deliberately identical to `signupRules
 * .validateBirthday` — same future check, same year-only age comparison, same
 * `MINIMUM_SIGNUP_AGE` — and a test pins the two against each other on the
 * boundary. Only the wording differs, because "You must be at least 13 years
 * old to sign up" is the wrong sentence to show somebody who signed up years
 * ago and is correcting a typo in their year of birth.
 */
export function birthdayError(value) {
  if (!value) return 'Please select your birthday'

  const date = parseDateInput(value)
  if (!date) return 'Please enter a valid birthday'

  const today = todayAtMidnight()
  if (date.getTime() > today.getTime()) return "Birthday can't be in the future"

  if (today.getFullYear() - date.getFullYear() < MINIMUM_SIGNUP_AGE) {
    return `A CUFMAI account needs a birthday at least ${MINIMUM_SIGNUP_AGE} years ago.`
  }

  return null
}

/**
 * The phone rule, which the app does not have one of.
 *
 * Optional here (the column is nullable and sign-up does not ask for it
 * either), but validated when present, reusing the checkout's own digit rule so
 * a number that saves on the account page is one an address form accepts.
 * Being stricter than the app is deliberate: this number ends up on a delivery
 * record and in a rider's phone.
 */
export function profilePhoneError(value) {
  const raw = String(value ?? '').trim()
  if (!raw) return null
  return phoneError(raw)
}

/** Every problem with a draft, keyed by field. */
export function profileErrors(draft) {
  const errors = {}

  if (!String(draft?.fullName ?? '').trim()) {
    errors.fullName = 'Please enter a name'
  }

  const phone = profilePhoneError(draft?.phone)
  if (phone) errors.phone = phone

  const birthday = birthdayError(draft?.birthday)
  if (birthday) errors.birthday = birthday

  if (draft?.genderOption === 'Self-describe') {
    const text = String(draft?.genderSelfDescribe ?? '').trim()
    if (!text) errors.gender = 'Please tell us how you describe yourself'
  }

  return errors
}

export function isProfileComplete(draft) {
  return Object.keys(profileErrors(draft)).length === 0
}

function blankToNull(value) {
  const trimmed = String(value ?? '').trim()
  return trimmed ? trimmed : null
}

/**
 * A draft → the `profiles` columns it may write.
 *
 * Exactly five columns, and none of them is `role`, `seller_status`,
 * `suspended*` or the seller application fields: a trigger
 * (`guard_profiles_sensitive_columns`) raises on those anyway, but the right
 * place not to send them is here.
 *
 * Empty means NULL, including for the optional columns — `phone: null` clears
 * the number, `birthday: null` clears the date. That is a divergence from the
 * app, which only writes `birthday`/`gender` when it has a value and therefore
 * cannot clear one; it is the correct behaviour for a form that shows the
 * current value in every field and submits all of them together, and it is how
 * `phone` already behaved in the app.
 */
export function profileUpdatePayload(draft) {
  return {
    full_name: String(draft?.fullName ?? '').trim(),
    phone: blankToNull(draft?.phone),
    birthday: blankToNull(draft?.birthday),
    gender: resolveGenderValue(draft?.genderOption, draft?.genderSelfDescribe),
    bio: blankToNull(draft?.bio),
  }
}

/**
 * Whether two payloads are the same write.
 *
 * Used to answer "is the row on screen the row we just saved?" without
 * depending on object identity across the auth context — the payload is the
 * thing that actually went to the server, so comparing it cannot lie about
 * whether a save landed.
 */
export function sameProfilePayload(left, right) {
  const keys = new Set([
    ...Object.keys(left ?? {}),
    ...Object.keys(right ?? {}),
  ])

  for (const key of keys) {
    if ((left?.[key] ?? null) !== (right?.[key] ?? null)) return false
  }
  return true
}

/** Whether a draft would change anything — for a "no changes to save" state. */
export function profileIsDirty(draft, profile) {
  const current = profileUpdatePayload(profileDraftFromRow(profile))
  const next = profileUpdatePayload(draft)

  return Object.keys(next).some((key) => {
    if (key === 'gender') {
      // A self-described gender and an unset one both arrive as `null` from
      // `resolveGenderValue` when the text is blank, which is the same state.
      return (next[key] ?? null) !== (current[key] ?? null)
    }
    return (next[key] ?? null) !== (current[key] ?? null)
  })
}

/**
 * The avatar bucket and the one path a customer's photo may live at.
 *
 * `{userId}/avatar.jpg` is not a preference — it is a contract with two other
 * things: the Storage INSERT/UPDATE/DELETE policies check
 * `(storage.foldername(name))[1] = auth.uid()`, and the app uploads to this
 * exact path with `upsert: true`. A per-upload unique filename would satisfy the
 * policy and orphan every previous avatar.
 */
export const AVATAR_BUCKET = 'avatars'

export function avatarStoragePath(userId) {
  return `${String(userId ?? '')}/avatar.jpg`
}

/** The client-side half of "is this a usable profile photo". */
export const AVATAR_MAX_BYTES = 5 * 1024 * 1024
export const AVATAR_TYPES = ['image/jpeg', 'image/png', 'image/webp']

/**
 * Why a chosen file is not usable, or null.
 *
 * A client-side guard, and it is not redundant with anything: the bucket has a
 * size limit but no MIME restriction, so without this a customer can upload a
 * 40 MB PDF as their avatar and only find out when it renders as a broken
 * image. The extension fallback exists because Windows drag-and-drop fairly
 * often arrives with `file.type` empty, and rejecting a perfectly good JPEG
 * with "use a JPG, PNG or WebP" is a bug the customer cannot diagnose.
 */
export function avatarFileError(file) {
  if (!file) return 'Choose a photo first'

  const type = String(file.type ?? '').toLowerCase()
  const extension = /\.([a-z0-9]+)$/i.exec(String(file.name ?? ''))?.[1]?.toLowerCase()
  const extensionOk = ['jpg', 'jpeg', 'png', 'webp'].includes(extension ?? '')
  const typeOk = AVATAR_TYPES.includes(type)

  if (!typeOk && !(type === '' && extensionOk)) {
    return 'Use a JPG, PNG or WebP photo'
  }

  if (Number(file.size) > AVATAR_MAX_BYTES) {
    return `Keep the photo under ${Math.round(AVATAR_MAX_BYTES / (1024 * 1024))} MB`
  }

  return null
}

/**
 * A public avatar URL with a cache-busting stamp.
 *
 * The storage path never changes — every upload overwrites `{userId}/avatar.jpg`
 * — so the public URL is byte-for-byte identical before and after a new photo
 * lands. Without this, the browser (and any CDN in front of it) keeps serving
 * the old face, and the customer concludes the upload failed. The app does the
 * same thing with `?t=${millisecondsSinceEpoch}`.
 *
 * Called ONCE, at upload time, and the stamped URL is what gets stored in
 * `profiles.avatar_url`. It must not be called while rendering: `Date.now()`
 * changes every pass, so the `<img src>` would change on every render and the
 * browser would re-fetch the photo each time.
 */
/**
 * A failed profile save or avatar upload as something a screen can act on.
 *
 * The cases worth naming all come from outside the row we write:
 *
 *   Storage rejects a file   → the bucket has its own size/mime limits, and
 *                              its message ("Payload too large", "mime type … is
 *                              not supported") is accurate but written for a
 *                              developer. `avatarFileError` catches most of
 *                              these earlier; this is the net underneath it.
 *   the guard trigger fires  → `P0001` with a hand-written sentence. It should
 *                              be unreachable from this form (we never send
 *                              `role`/`seller_status`), and if it ever fires
 *                              the server's own wording is the useful part.
 *   no session               → a customer whose session expired mid-edit gets
 *                              "Not authenticated" from PostgREST, which reads
 *                              as a system fault rather than "sign in again".
 */
export function profileError(
  error,
  fallback = 'We could not save your details. Please try again.',
) {
  const code = error?.code ?? null
  const raw = String(error?.message ?? error?.error ?? '').trim()

  if (/payload too large/i.test(raw) || code === '413') {
    return {
      message: `That photo is too big. Keep it under ${Math.round(
        AVATAR_MAX_BYTES / (1024 * 1024),
      )} MB.`,
      code: code ?? '413',
    }
  }

  if (/mime type|invalid file type|content type/i.test(raw)) {
    return { message: 'Use a JPG, PNG or WebP photo.', code: code ?? 'mime' }
  }

  if (code === '42501' && (!raw || /not authenticated|permission denied/i.test(raw))) {
    return {
      message: 'Your session has expired. Sign in again and your changes will save.',
      code,
    }
  }

  if (raw) return { message: raw, code }
  return { message: fallback, code }
}

export function withAvatarCacheBust(url, now = Date.now()) {
  const raw = String(url ?? '').trim()
  if (!raw) return ''

  const [base, query = ''] = raw.split('?')
  const kept = query
    .split('&')
    .filter((part) => part && !part.startsWith('t='))
    .join('&')

  return `${base}?${kept ? `${kept}&` : ''}t=${now}`
}
