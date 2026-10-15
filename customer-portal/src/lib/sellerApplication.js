import {
  formatBirthdayForDb,
  resolveGenderValue,
} from './signupRules.js'
import {
  SELLER_DOC_KEYS,
  STORE_ASSET_BUCKET,
  VERIFICATION_BUCKET,
} from './sellerApplicationRules.js'
import { supabase } from './supabase.js'

export * from './sellerApplicationRules.js'

/**
 * Seller application writes — the Supabase half of the portal's seller signup.
 *
 * The rules live next door in `sellerApplicationRules.js` (pure, tested without
 * a network); this file owns the account creation, the document uploads and
 * the profile writes, mirroring `AuthService.ensureUser` +
 * `completeSellerApplication` in the Flutter app.
 *
 * ## The ordering contract (copied from the app, still load-bearing)
 *
 * The Supabase Auth user is created ONLY at final submit — abandoning the form
 * mid-way never leaves an orphaned auth user. Documents are uploaded AFTER a
 * session exists (the private bucket's RLS keys off `auth.uid()`), and the
 * profile is then upserted with `seller_status = 'pending'` while `role` stays
 * `customer` — the flip to `seller` happens ONLY on admin approval.
 *
 * With "Confirm email" ON, `signUp` returns no session, so the submit pauses at
 * an awaiting-email state: the text fields are stashed in `localStorage` (files
 * cannot be — the applicant re-attaches them after confirming, and the copy on
 * the form says so) and `AuthConfirm` routes the fresh session back here to
 * resume instead of to `/account`.
 */

export const SELLER_SIGNUP_ROUTE = '/signup/seller'

function extensionOf(name) {
  const parts = String(name ?? '').split('.')
  return parts.length > 1 ? parts.pop().toLowerCase() : ''
}

/**
 * Whether this email already has a profile row — the app's `emailExists`
 * duplicate check at Step 1, before any document work.
 */
export async function sellerEmailExists(email) {
  const { data, error } = await supabase
    .from('profiles')
    .select('id')
    .eq('email', String(email ?? '').trim().toLowerCase())
    .maybeSingle()
  if (error) throw error
  return data != null
}

/**
 * Creates the auth user for a seller application — ONLY called at final submit.
 *
 * Carries NO role in its metadata (exactly like the app's `ensureUser`): the
 * application write below is what produces the pending row, so a customer row
 * must never be minted from this signup's metadata first. Reuses the current
 * session when it already belongs to this email; drops a different session
 * first, mirroring the app's sign-in.
 *
 * Returns `{ user, emailVerificationRequired }`.
 */
export async function signUpSellerAccount({ email, password, fullName }) {
  const trimmedEmail = String(email ?? '').trim()
  const { data: existing } = await supabase.auth.getSession()
  const current = existing?.session?.user ?? null
  if (current) {
    if ((current.email ?? '').toLowerCase() === trimmedEmail.toLowerCase()) {
      return { user: current, emailVerificationRequired: false }
    }
    await supabase.auth.signOut()
  }

  const { data, error } = await supabase.auth.signUp({
    email: trimmedEmail,
    password,
    options: {
      // Same destination as `authConfirmRedirect()` in auth.js — inlined
      // because auth.js uses an extensionless import Vite resolves but
      // `node --test` does not. The URL must stay allow-listed in Supabase.
      emailRedirectTo: `${window.location.origin}/auth/confirm`,
      data: { full_name: String(fullName ?? '').trim() },
    },
  })
  if (error) throw error
  const user = data.user
  if (!user) throw new Error('Sign up failed. Please try again.')
  if (!data.session) return { user, emailVerificationRequired: true }
  return { user, emailVerificationRequired: false }
}

/**
 * Uploads one verification document into the PRIVATE bucket at
 * `{userId}/{docKey}.{ext}` (upsert — resubmitting overwrites, so the RLS
 * policies keying off the first path segment keep working). Returns the
 * storage path written to the profile row.
 */
export async function uploadVerificationDoc(userId, docKey, file) {
  const ext = extensionOf(file.name) || 'jpg'
  const path = `${userId}/${docKey}.${ext}`
  const { error } = await supabase.storage
    .from(VERIFICATION_BUCKET)
    .upload(path, file, { upsert: true, contentType: file.type })
  if (error) throw error
  return path
}

/** All private-bucket uploads for one application, in doc-key order. */
export async function uploadSellerDocuments(userId, files) {
  const paths = {}
  const order = [
    [SELLER_DOC_KEYS.ID_DOCUMENT, files.idFile],
    [SELLER_DOC_KEYS.SELFIE, files.selfieFile],
    [SELLER_DOC_KEYS.DTI_CERT, files.dtiFile],
    [SELLER_DOC_KEYS.BIR_COR, files.birFile],
    [SELLER_DOC_KEYS.PERMIT, files.permitFile],
  ]
  for (const [docKey, file] of order) {
    if (file) paths[docKey] = await uploadVerificationDoc(userId, docKey, file)
  }
  if (!files.isMember && files.barangayFile) {
    paths[SELLER_DOC_KEYS.BARANGAY_PROOF] = await uploadVerificationDoc(
      userId,
      SELLER_DOC_KEYS.BARANGAY_PROOF,
      files.barangayFile,
    )
  }
  const productPhotos = []
  for (let index = 0; index < (files.productFiles ?? []).length; index += 1) {
    productPhotos.push(
      await uploadVerificationDoc(
        userId,
        `product_photo_${index + 1}`,
        files.productFiles[index],
      ),
    )
  }
  paths.productPhotos = productPhotos
  return paths
}

/**
 * The store-front photo goes to the PUBLIC store-assets bucket so it can double
 * as the store banner post-approval (`StoreService.createStore` falls back to
 * `profiles.store_front_url`). Returns the storage path.
 */
export async function uploadStorefrontPhoto(userId, file) {
  const ext = extensionOf(file.name) || 'jpg'
  const path = `${userId}/storefront.${ext}`
  const { error } = await supabase.storage
    .from(STORE_ASSET_BUCKET)
    .upload(path, file, { upsert: true, contentType: file.type })
  if (error) throw error
  return path
}

/**
 * Writes the full Tier 1 application onto the profile and marks it `pending`
 * for admin review. `role` stays `customer` — the flip to `seller` happens ONLY
 * on admin approval (`approveSeller`), unchanged from the app.
 */
export async function completeSellerApplication({
  userId,
  email,
  account,
  identity,
  community,
  business,
  storefront,
  paths,
}) {
  void business
  const profileData = {
    id: userId,
    full_name: String(account.fullName ?? '').trim(),
    email: String(email ?? '').trim(),
    role: 'customer',
    seller_status: 'pending',
    phone: String(account.phone ?? '').trim() || null,
    id_type: identity.idType,
    id_document_url: paths[SELLER_DOC_KEYS.ID_DOCUMENT],
    selfie_url: paths[SELLER_DOC_KEYS.SELFIE],
    cufmai_member_id:
      community.isMember && String(community.memberId ?? '').trim()
        ? String(community.memberId).trim()
        : null,
    barangay_proof_url: community.isMember
      ? null
      : (paths[SELLER_DOC_KEYS.BARANGAY_PROOF] ?? null),
    store_front_url: paths[SELLER_DOC_KEYS.STOREFRONT],
    product_photo_urls:
      paths.productPhotos?.length > 0 ? paths.productPhotos : null,
    store_name: String(storefront.storeName ?? '').trim(),
    store_description: String(storefront.storeDescription ?? '').trim(),
    birthday: formatBirthdayForDb(account.birthday),
    gender: resolveGenderValue(account.gender, account.genderText),
    store_location: String(community.storeLocation ?? '').trim() || null,
    store_lat: community.storeLat ?? null,
    store_lng: community.storeLng ?? null,
    store_tags:
      storefront.storeTags?.length > 0 ? storefront.storeTags : null,
    rejection_reason: null,
  }

  const { error: profileError } = await supabase
    .from('profiles')
    .upsert(profileData)
  if (profileError) throw profileError

  if (
    paths[SELLER_DOC_KEYS.DTI_CERT] ||
    paths[SELLER_DOC_KEYS.BIR_COR] ||
    paths[SELLER_DOC_KEYS.PERMIT]
  ) {
    const { error: docsError } = await supabase
      .from('seller_business_docs')
      .upsert(
        {
          profile_id: userId,
          dti_cert_url: paths[SELLER_DOC_KEYS.DTI_CERT] ?? null,
          bir_cor_url: paths[SELLER_DOC_KEYS.BIR_COR] ?? null,
          permit_url: paths[SELLER_DOC_KEYS.PERMIT] ?? null,
          verification_status: 'pending',
          submitted_at: new Date().toISOString(),
          verified_at: null,
        },
        { onConflict: 'profile_id' },
      )
    if (docsError) throw docsError
  }

  const { data: profile, error: readError } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .maybeSingle()
  if (readError) throw readError
  return profile ?? profileData
}

/** localStorage key for the text-only pending application (no files). */
export const PENDING_SELLER_KEY = 'cufmai_pending_seller_application'

/**
 * Stashes the text half of an application whose email is still unconfirmed.
 * Files are deliberately NOT stored — the resume copy tells the applicant to
 * re-attach them.
 */
export function savePendingSellerApplication(draft) {
  try {
    window.localStorage.setItem(PENDING_SELLER_KEY, JSON.stringify(draft))
  } catch {
    // Private mode / quota: the email state below still tells the applicant
    // what to do; the draft is a convenience, not the flow.
  }
}

export function loadPendingSellerApplication() {
  try {
    const raw = window.localStorage.getItem(PENDING_SELLER_KEY)
    if (!raw) return null
    return JSON.parse(raw)
  } catch {
    return null
  }
}

export function clearPendingSellerApplication() {
  try {
    window.localStorage.removeItem(PENDING_SELLER_KEY)
  } catch {
    // Best-effort.
  }
}
