import { AVATAR_BUCKET, avatarStoragePath, withAvatarCacheBust } from './profileRules.js'
import { supabase } from './supabase.js'

// The rules live next door — including the error mapping, which turns a
// Storage failure into a sentence (see `profileError` in `profileRules.js`).
// Re-exported so screens have one import site for "profile".
export * from './profileRules.js'

/**
 * Profile writes.
 *
 * ## What a customer is allowed to write, and why that is not enforced here
 *
 * `profiles` has an owner UPDATE policy (`auth.uid() = id`), and a BEFORE
 * UPDATE trigger — `guard_profiles_sensitive_columns` — raises if the row owner
 * changes `role`, `seller_status`, `suspended`, `suspended_reason`,
 * `suspended_at`, or any seller-application column once an application is
 * pending or approved. So the database is the authority and this module simply
 * does not send those columns: `profileUpdatePayload` builds the payload from
 * five fields, and `avatar_url` is written separately by the upload below.
 *
 * ## The avatar path is a contract, not a preference
 *
 * `{userId}/avatar.jpg`, overwritten on every upload. The Storage policies
 * check `(storage.foldername(name))[1] = auth.uid()`, and the app uploads to
 * this exact path with `upsert: true` — a unique filename per upload would
 * satisfy the policy and orphan every previous photo, including the one the
 * app still points at.
 */

/** Update the customer's own row and return it. */
export async function updateProfile(userId, payload) {
  const { data, error } = await supabase
    .from('profiles')
    .update(payload)
    .eq('id', userId)
    .select()
    .single()

  if (error) throw error
  return data
}

/**
 * Upload a new profile photo and point `avatar_url` at it.
 *
 * Order matters: the file is uploaded FIRST and the column written only after
 * Storage has accepted it. The reverse would leave the account displaying a
 * photo that never arrived, and the URL would look perfectly valid.
 *
 * The returned URL carries a `?t=` stamp because the path is stable across
 * uploads — see `withAvatarCacheBust`.
 */
export async function uploadAvatar(userId, file) {
  const path = avatarStoragePath(userId)

  const { error } = await supabase.storage
    .from(AVATAR_BUCKET)
    .upload(path, file, { upsert: true, cacheControl: '3600' })
  if (error) throw error

  const { data } = supabase.storage.from(AVATAR_BUCKET).getPublicUrl(path)
  const url = withAvatarCacheBust(data?.publicUrl)

  await updateProfile(userId, { avatar_url: url })
  return url
}

/**
 * Remove the customer's photo, from Storage and from the row.
 *
 * Both halves, in this order: a row cleared first would leave the file behind
 * forever, and the next upload would still be a `upsert` onto a path nobody is
 * pointing at. The row is cleared even if the file was already gone, because
 * the state the customer asked for is "no photo" and a missing file already
 * satisfies it.
 */
export async function removeAvatar(userId) {
  const { error } = await supabase.storage
    .from(AVATAR_BUCKET)
    .remove([avatarStoragePath(userId)])

  // A Storage error here is reported, but only after the row is cleared — see
  // the note above.
  await updateProfile(userId, { avatar_url: null })

  if (error) throw error
}
