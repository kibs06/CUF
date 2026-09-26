import { ROLES } from './constants'
import { supabase } from './supabase'

/**
 * Auth, mirroring `lib/services/auth_service.dart`.
 *
 * The ordering contract below is the part that is easy to get wrong, and it is
 * not optional — it comes from the database, not from style:
 *
 *   `public.profiles` has NO `on auth.users` trigger. Its INSERT policy is
 *   `auth.uid() = id`, so **a session must already exist** before the row can
 *   be written.
 *
 * With "Confirm email" ON (which it is), `signUp` returns **no session**. There
 * is therefore nothing to write the profile with at sign-up time, so the fields
 * the row needs are stashed in the user's `raw_user_meta_data` — server-side,
 * so closing the tab mid-verification, or opening the mail on another device,
 * does not lose them. `writeProfileFromMetadata` finishes the job once the
 * confirmation link has established a session.
 */

/** Where the confirmation e-mail sends the customer back to. */
export function authConfirmRedirect() {
  // The deployed origin, NOT a deep-link scheme — a browser has nothing to
  // handle `solvision://`. This URL must be allow-listed in Supabase →
  // Authentication → URL Configuration → Redirect URLs, or GoTrue ignores it
  // and silently falls back to the site URL.
  return `${window.location.origin}/auth/confirm`
}

/**
 * The profile row for a user, retrying briefly while it is being written.
 *
 * The retry mirrors the app's `getProfile`: a freshly confirmed sign-up can
 * reach this before the row is visible, and giving up immediately would strand
 * a customer on an account page with no account.
 *
 * If it is still missing, the row is CREATED here — the same last-resort branch
 * the app has — with `seller_status: 'none'` written **explicitly**. The column
 * default is `'pending'`, so omitting it would make every new customer look
 * like an unapproved seller application.
 */
export async function fetchProfile(userId, { attempts = 5 } = {}) {
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .maybeSingle()

    if (error) throw error
    if (data) return data

    if (attempt < attempts) {
      await new Promise((resolve) => setTimeout(resolve, 300 * attempt))
    }
  }

  const { data: auth } = await supabase.auth.getUser()
  const user = auth?.user
  if (!user) return null

  const { error: upsertError } = await supabase.from('profiles').upsert({
    id: userId,
    full_name: user.user_metadata?.full_name ?? '',
    email: user.email ?? '',
    role: ROLES.CUSTOMER,
    seller_status: 'none',
  })
  if (upsertError) throw upsertError

  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .maybeSingle()

  if (error) throw error
  return data
}

/**
 * Writes the `profiles` row from the sign-up metadata, after the confirmation
 * link has established a session.
 *
 * The `role` guard is load-bearing and is copied from the app: the metadata's
 * explicit `role` is what says whether this signup may produce a plain customer
 * row at all. The seller flow's signup carries only a name, and must NOT be
 * turned into one — so anything that is not an explicit customer signup falls
 * through to a plain read (and, if there is genuinely no row, `fetchProfile`'s
 * own last-resort branch).
 */
export async function writeProfileFromMetadata(user) {
  if (!user) return null

  const metadata = user.user_metadata ?? {}
  if (metadata.role !== ROLES.CUSTOMER) return fetchProfile(user.id)

  const { error } = await supabase.from('profiles').upsert({
    id: user.id,
    full_name: metadata.full_name ?? '',
    email: user.email ?? '',
    role: ROLES.CUSTOMER,
    seller_status: metadata.seller_status ?? 'none',
    phone: metadata.phone ?? null,
    birthday: metadata.birthday ?? null,
    gender: metadata.gender ?? null,
  })
  if (error) throw error

  return fetchProfile(user.id)
}

/**
 * Whether an account is banned.
 *
 * This client-side check is not redundant with RLS — the migration that added
 * it says so outright: *"banning cannot be enforced at the login layer by RLS
 * (auth happens before any policy runs)"*. The suspended flag has to be read
 * and acted on by the client, and RLS is the second, server-side layer that
 * keeps an already-signed-in banned account out of the data plane.
 */
export function isSuspended(profile) {
  return profile?.suspended === true
}

export function accessDeniedReason(profile) {
  if (isSuspended(profile)) {
    return (
      profile?.suspended_reason?.trim() ||
      'This account has been suspended. Please contact CUFMAI support.'
    )
  }
  return null
}

/**
 * Sign in.
 *
 * Any existing session is dropped first, exactly as the app does: a lingering
 * session from another account can otherwise block the new sign-in silently,
 * which reads to the customer as "my password is wrong".
 */
export async function signIn({ email, password }) {
  const { data: existing } = await supabase.auth.getSession()
  if (existing?.session) await supabase.auth.signOut()

  const { data, error } = await supabase.auth.signInWithPassword({
    email: email.trim(),
    password,
  })
  if (error) throw error

  const user = data.user
  if (!user) throw new Error('Sign-in failed. Please try again.')

  const profile = await fetchProfile(user.id)
  if (isSuspended(profile)) {
    await supabase.auth.signOut()
    throw new Error(accessDeniedReason(profile))
  }

  return profile
}

/**
 * Create a CUSTOMER account.
 *
 * Returns `{ user, profile, emailVerificationRequired }`. `profile` is null
 * when confirmation is still pending — see the module docs for why.
 */
export async function signUp({
  fullName,
  email,
  password,
  phone,
  birthday,
  gender,
}) {
  const { data, error } = await supabase.auth.signUp({
    email: email.trim(),
    password,
    options: {
      emailRedirectTo: authConfirmRedirect(),
      data: {
        full_name: fullName.trim(),
        // Mirrors the profiles columns, so the row can be written later from
        // metadata alone.
        role: ROLES.CUSTOMER,
        seller_status: 'none',
        phone: phone ?? null,
        // Already a local `YYYY-MM-DD` string: the column is a DATE, and
        // sending an ISO timestamp would let a timezone shift the day.
        birthday: birthday ?? null,
        gender: gender ?? null,
      },
    },
  })
  if (error) throw error

  const user = data.user
  if (!user) throw new Error('Sign up failed. Please try again.')

  if (!data.session) {
    return { user, profile: null, emailVerificationRequired: true }
  }

  const profile = await writeProfileFromMetadata(user)
  return { user, profile, emailVerificationRequired: false }
}

export async function signOut() {
  const { error } = await supabase.auth.signOut()
  if (error) throw error
}

/**
 * Send the password-reset e-mail.
 *
 * `redirectTo` is the account page rather than a dedicated screen: the recovery
 * link signs the customer in with a short-lived session, and the only thing
 * left to do is set a new password — which the account page already offers. A
 * separate page would be a second place to land on the same form.
 */
export async function requestPasswordReset(email) {
  const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
    redirectTo: `${window.location.origin}/account`,
  })
  if (error) throw error
}

export async function updatePassword(newPassword) {
  const { error } = await supabase.auth.updateUser({ password: newPassword })
  if (error) throw error
}

/**
 * Start changing the sign-in email.
 *
 * The same single call the app makes (`auth_service.dart` → `updateUser`), and
 * deliberately nothing else: GoTrue owns the confirmation flow, and with secure
 * email change on it emails the new address a confirmation link and the old
 * address a notice. The change is NOT in effect when this resolves — the new
 * address becomes the sign-in address when that link is opened, which is why
 * the screen says so rather than reporting success.
 *
 * `profiles.email` is not written here. It is a denormalised copy of the auth
 * address, and writing the new value before it is confirmed would leave the
 * profile advertising an address the customer cannot sign in with — the app
 * leaves the same gap, and the profile row catches up when the auth row does.
 */
export async function updateEmail(newEmail) {
  const { error } = await supabase.auth.updateUser({
    email: String(newEmail ?? '').trim(),
  })
  if (error) throw error
}
