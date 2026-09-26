/**
 * Account & Security rules — the pure half of the security screen.
 *
 * Both features here are conversations with GoTrue (Supabase Auth) rather than
 * with Postgres, and both have failure modes a customer can only act on if they
 * are told the right sentence: `email_exists` in a red box is not an
 * instruction, and "request already pending" is a *success* wearing an error's
 * clothes — the request exists, which is the thing they wanted.
 */

/**
 * The app's own check (`account_security_screen.dart`): non-empty, one `@`,
 * a dot in the domain. Deliberately loose — the confirmation email is the real
 * validation, and a cleverer pattern only rejects addresses that work.
 */
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

/** Why this address is unusable, or null. */
export function emailError(value) {
  const email = String(value ?? '').trim()
  if (!email) return 'Enter the new email address'
  if (!EMAIL_PATTERN.test(email)) return 'Please enter a valid email address'
  return null
}

/**
 * True when the new address is the one already on the account.
 *
 * Worth its own check rather than letting GoTrue answer, because GoTrue's reply
 * for this case is indistinguishable from a real conflict — and the useful
 * sentence is "that is the address you already use", which is not an error at
 * all as far as the customer is concerned.
 */
export function isSameEmail(current, next) {
  const a = String(current ?? '').trim().toLowerCase()
  const b = String(next ?? '').trim().toLowerCase()
  return Boolean(a) && a === b
}

/** Every problem with an email change, or an empty object. */
export function emailChangeErrors({ next, current } = {}) {
  const errors = {}
  const problem = emailError(next)
  if (problem) errors.email = problem
  else if (isSameEmail(current, next)) {
    errors.email = 'That is the address you are already signed in with'
  }
  return errors
}

/**
 * A GoTrue failure as a sentence.
 *
 * The status matters as much as the message for one case: 429 is a rate limit,
 * and "too many requests" reads as the customer's fault when in fact their
 * first click worked and this is their second. `email_exists` is the other one
 * worth naming, because the fix — sign in with the other address, or pick a
 * third — is not obvious from "already registered".
 */
export function emailChangeError(error) {
  const status = error?.status ?? error?.statusCode ?? null
  const raw = String(error?.message ?? error?.code ?? '').trim().toLowerCase()

  if (status === 429 || /rate limit|too many/.test(raw)) {
    return 'We have already sent a confirmation. Check both inboxes, then wait a few minutes before asking again.'
  }
  if (/already.*(registered|exists)|email_exists/.test(raw)) {
    return 'That email address already has a CUFMAI account. Sign in with it instead, or use a different address.'
  }
  if (/invalid.*email|email.*invalid/.test(raw)) {
    return 'That email address was not accepted. Please check it and try again.'
  }
  if (/not authenticated|session|jwt/.test(raw)) {
    return 'Your session has expired. Please sign in again, then change your email.'
  }
  return 'We could not start the email change. Please try again in a moment.'
}

/**
 * What the customer is told after the request goes through.
 *
 * Two emails, and the wording says so rather than implying one: with secure
 * email change on, the new address gets the confirmation link and the old
 * address gets a notice — which is the feature, not noise. It is also why this
 * cannot promise the change has happened: it has not, yet.
 */
export function emailChangeSentMessage(next) {
  return `Confirmation sent to ${String(next ?? '').trim()}. Open the link in that email to finish the change — until then, keep signing in with your current address.`
}

/**
 * The deletion consequence, in the app's words.
 *
 * The list is the point: "delete my account" is abstract, and a customer
 * weighing it deserves to know it takes their orders and their saved sizes with
 * it. Passed to `ConfirmDialog` as one string because the dialog renders it with
 * `whitespace-pre-line`.
 */
export const DELETION_CONSEQUENCE = [
  'This asks CUFMAI to delete your account. Our team reviews the request within 48 hours.',
  '',
  'Everything on the account goes with it:',
  '• Profile information and your photo',
  '• Orders and purchase history',
  '• Saved delivery addresses',
  '• Your foot size and scan data',
  '',
  'This cannot be undone once it is approved.',
].join('\n')

/**
 * The deletion function's answer as something to show.
 *
 * `success: false` is NOT a failure here — the one case the RPC returns it for
 * is "you already have a pending deletion request", which means the customer
 * already did this and the row exists. Reporting that as an error would push
 * them to try again, which is the one thing that cannot help.
 */
export function deletionResult(data, fallback = 'We could not send that request. Please try again.') {
  const success = data?.success === true
  const message = String(data?.message ?? '').trim()

  if (success) return { ok: true, message: message || 'Your request has been sent.' }

  if (/already have a pending/i.test(message)) {
    return { ok: true, message }
  }

  return { ok: false, message: message || fallback }
}
