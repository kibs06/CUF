import { supabase } from './supabase'

// ── JWT / AAL helpers ─────────────────────────────────────────────

/** Decodes a Supabase access-token (JWT) payload without verifying —
 *  used only to read the `aal` claim for UI gating. Returns null on any
 *  malformed input; callers treat null as AAL1. */
export function decodeJwt(token) {
  try {
    const payload = token.split('.')[1]
    const normalized = payload.replace(/-/g, '+').replace(/_/g, '/')
    const padded = normalized.padEnd(
      normalized.length + ((4 - (normalized.length % 4)) % 4),
      '=',
    )
    return JSON.parse(atob(padded))
  } catch {
    return null
  }
}

/** Returns 'aal2' when MFA was completed on this session, else 'aal1'. */
export function getAal(session) {
  if (!session?.access_token) return 'aal1'
  return decodeJwt(session.access_token)?.aal === 'aal2' ? 'aal2' : 'aal1'
}

/** True when the session still needs an MFA code before the portal shows. */
export function needsMfa(session) {
  if (getAal(session) === 'aal2') return false
  const factors = session?.user?.factors ?? []
  return factors.some(
    (f) => f.factor_type === 'totp' && f.status === 'verified',
  )
}

/** The verified TOTP factor to challenge at login, or null. */
export function getVerifiedFactor(session) {
  const factors = session?.user?.factors ?? []
  return (
    factors.find(
      (f) => f.factor_type === 'totp' && f.status === 'verified',
    ) ?? null
  )
}

// ── MFA API wrappers (all throw on error) ─────────────────────────

export async function listMfaFactors() {
  const { data, error } = await supabase.auth.mfa.listFactors()
  if (error) throw error
  return data.all
}

export async function enrollMfa({ friendlyName }) {
  const { data, error } = await supabase.auth.mfa.enroll({
    factorType: 'totp',
    issuer: 'SoleVision',
    friendlyName: friendlyName ?? 'Authenticator app',
  })
  if (error) throw error
  return data
}

/** Verifies a code against a factor: used both to confirm enrollment
 *  and to step up the login session (works the same server-side). */
export async function verifyLogin({ factorId, code }) {
  const { data, error } = await supabase.auth.mfa.challengeAndVerify({
    factorId,
    code,
  })
  if (error) throw error
  return data
}

export async function unenrollMfa(factorId) {
  const { data, error } = await supabase.auth.mfa.unenroll({ factorId })
  if (error) throw error
  return data
}