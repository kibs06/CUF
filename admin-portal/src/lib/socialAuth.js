/**
 * Social (OAuth) sign-in helpers for the admin portal.
 *
 * Social sign-in proves WHO the user is — it never decides WHAT they may do.
 * The portal's `isBlocked` gate in `useAuth.jsx` (admin role + not suspended)
 * stays the real gatekeeper: a Google/Facebook user with no admin profile row
 * is signed straight back out with "Access denied".
 *
 * Pure functions only (no JSX, no Supabase import) so they stay testable with
 * the repo's `node --test` runner like the other `lib/*.test.js` files.
 */

export const SOCIAL_PROVIDERS = ['google', 'facebook']

export function isSocialProvider(provider) {
  return SOCIAL_PROVIDERS.includes(provider)
}

/**
 * Where Supabase must return the user after the provider approves the login.
 * Must be allow-listed in Supabase → Auth → URL Configuration → Redirect URLs
 * (production origin + localhost during development).
 */
export function socialCallbackUrl(origin) {
  return `${String(origin).replace(/\/$/, '')}/auth/callback`
}

/**
 * Friendly copy for OAuth start failures. Supabase throws when the provider
 * is not enabled on the project (the console step in
 * docs/SOCIAL_SIGNIN_SETUP.md was skipped) — that is a setup problem, not a
 * user problem, so the copy says so instead of blaming the click.
 */
export function socialStartErrorMessage(error) {
  const message = String(error?.message ?? error ?? '')
  if (/provider.*not enabled|not enabled.*provider|unsupported provider/i.test(message)) {
    return 'Social sign-in is not switched on yet. Use your email and password for now.'
  }
  return message || 'Social sign-in failed. Please try again.'
}

/**
 * Friendly copy for the /auth/callback return leg (user denied consent,
 * expired code, PKCE mismatch, …).
 */
export function socialCallbackErrorMessage(searchParams) {
  const description =
    searchParams.get('error_description') ?? searchParams.get('error') ?? ''
  if (/access_denied|user_denied|denied/i.test(description)) {
    return 'You cancelled the sign-in. Try again when ready.'
  }
  return description
    ? decodeURIComponent(String(description).replace(/\+/g, ' '))
    : 'That sign-in link did not work. Please try again.'
}
