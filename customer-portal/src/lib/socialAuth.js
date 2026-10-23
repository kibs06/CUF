/**
 * Social (OAuth) sign-in helpers for the customer storefront.
 *
 * Same shape as the admin portal's `socialAuth.js` on purpose — one pattern
 * for both web clients, pointed at the same Supabase project.
 *
 * Social sign-in proves WHO the customer is; it never decides WHAT they may
 * do. New social users become plain `customer` rows through the existing
 * `fetchProfile` last-resort branch (`seller_status: 'none'` explicit), and
 * suspended accounts are still signed straight out by the `useAuth` gate.
 * Sellers still apply via `/signup/seller`.
 *
 * Pure functions only (no JSX, no Supabase import) so they stay testable with
 * the repo's `node --test` runner like the other `lib/*.test.js` files.
 */

export const SOCIAL_PROVIDERS = ['google', 'facebook']

export function isSocialProvider(provider) {
  return SOCIAL_PROVIDERS.includes(provider)
}

/**
 * Where Supabase must return the customer after the provider approves the
 * login. Same-origin by construction — and it must be allow-listed in
 * Supabase → Auth → URL Configuration → Redirect URLs for THIS portal's
 * origin (the storefront and the admin portal are different deployments, so
 * each needs its own entry; same rule as `/auth/confirm`).
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
 * Friendly copy for the /auth/callback return leg (customer denied consent,
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

const DESTINATION_KEY = 'cufmai:post-login-destination'

function storage() {
  try {
    if (typeof window !== 'undefined' && window.sessionStorage) {
      return window.sessionStorage
    }
  } catch {
    // Private-mode / blocked storage: the destination is a nicety, not auth.
  }
  return null
}

/**
 * Remember where the customer was headed (e.g. /checkout) before the OAuth
 * redirect. `location.state.from` does not survive leaving for Google and
 * coming back, but sessionStorage does — same tab, same flow.
 */
export function rememberPostLoginDestination(destination) {
  const store = storage()
  if (!store) return
  if (typeof destination === 'string' && destination.startsWith('/')) {
    store.setItem(DESTINATION_KEY, destination)
  } else {
    store.removeItem(DESTINATION_KEY)
  }
}

/** Take (and clear) the remembered destination, or null when there is none. */
export function takePostLoginDestination() {
  const store = storage()
  if (!store) return null
  const destination = store.getItem(DESTINATION_KEY)
  store.removeItem(DESTINATION_KEY)
  return typeof destination === 'string' && destination.startsWith('/')
    ? destination
    : null
}
