import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'

import {
  accessDeniedReason,
  fetchProfile,
  isSuspended,
  signIn as signInRequest,
  signOut as signOutRequest,
  signUp as signUpRequest,
  updatePassword as updatePasswordRequest,
  updateEmail as updateEmailRequest,
  writeProfileFromMetadata,
} from '../lib/auth'
import { ROLES } from '../lib/constants'
import { footProfilePayload, footProfileSkippedPayload } from '../lib/footRules'
import {
  removeAvatar as removeAvatarRequest,
  updateProfile as updateProfileRequest,
  uploadAvatar as uploadAvatarRequest,
} from '../lib/profile'
import { supabase } from '../lib/supabase'

const AuthContext = createContext(null)

/**
 * Session and profile for the whole site.
 *
 * The shape mirrors the admin portal's `useAuth` on purpose — same field names,
 * same flow — because the two are the same kind of thing pointed at the same
 * project. The difference is the gate: this one admits anyone ACTIVE, and the
 * admin portal admits only admins.
 */
export function AuthProvider({ children }) {
  const [session, setSession] = useState(null)
  const [profile, setProfile] = useState(null)
  const [loading, setLoading] = useState(true)
  const [accessDenied, setAccessDenied] = useState(false)

  /**
   * Resolve a session into a profile, applying the suspension gate.
   *
   * Returns true when the account may proceed. A suspended account is signed
   * out here rather than merely hidden from the UI: the flag is the only thing
   * standing between a banned customer and the data plane, and leaving the
   * session alive would let a stale tab keep writing to the cart.
   */
  const applySession = useCallback(async (nextSession) => {
    if (!nextSession?.user) {
      setProfile(null)
      setAccessDenied(false)
      return false
    }

    try {
      const nextProfile = await fetchProfile(nextSession.user.id)
      if (isSuspended(nextProfile)) {
        await supabase.auth.signOut()
        setAccessDenied(true)
        setProfile(null)
        setSession(null)
        return false
      }
      setProfile(nextProfile)
      setAccessDenied(false)
      return true
    } catch {
      // A profile we cannot read is not a profile we may act on.
      await supabase.auth.signOut()
      setProfile(null)
      setSession(null)
      return false
    }
  }, [])

  useEffect(() => {
    let mounted = true

    async function init() {
      const { data } = await supabase.auth.getSession()
      if (!mounted) return

      setSession(data?.session ?? null)
      await applySession(data?.session ?? null)
      if (mounted) setLoading(false)
    }

    init()

    const { data: listener } = supabase.auth.onAuthStateChange(
      async (_event, nextSession) => {
        if (!mounted) return
        setSession(nextSession)
        await applySession(nextSession)
      },
    )

    return () => {
      mounted = false
      listener.subscription.unsubscribe()
    }
  }, [applySession])

  const signIn = useCallback(async (email, password) => {
    setAccessDenied(false)
    const nextProfile = await signInRequest({ email, password })
    setProfile(nextProfile)
    return nextProfile
  }, [])

  const signUp = useCallback(async (fields) => {
    const result = await signUpRequest(fields)
    if (result.profile) {
      setProfile(result.profile)
    }
    return result
  }, [])

  const signOut = useCallback(async () => {
    await signOutRequest()
    setProfile(null)
    setSession(null)
    setAccessDenied(false)
  }, [])

  const refreshProfile = useCallback(async () => {
    const userId = session?.user?.id
    if (!userId) return null
    const nextProfile = await fetchProfile(userId)
    setProfile(nextProfile)
    return nextProfile
  }, [session])

  const updatePassword = useCallback(
    (newPassword) => updatePasswordRequest(newPassword),
    [],
  )

  /**
   * Save edited profile fields and adopt the row the database returns.
   *
   * The response is used rather than the payload, because PostgREST's `select()`
   * is the row as stored — trimmed, with empty strings already turned into
   * NULLs. Setting it here is what makes the rest of the site agree (the
   * header's name, the account card): the profile lives in this context, not in
   * a query cache, so nothing else has to be invalidated.
   */
  const updateProfile = useCallback(
    async (payload) => {
      const userId = session?.user?.id
      if (!userId) {
        throw new Error('Sign in again to save your details.')
      }
      const nextProfile = await updateProfileRequest(userId, payload)
      setProfile(nextProfile)
      return nextProfile
    },
    [session],
  )

  /**
   * Upload a profile photo and adopt the new `avatar_url`.
   *
   * A partial update rather than the returned row: the upload writes the URL
   * itself, and re-reading the whole row would race a concurrent field edit.
   */
  const uploadAvatar = useCallback(
    async (file) => {
      const userId = session?.user?.id
      if (!userId) {
        throw new Error('Sign in again to change your photo.')
      }
      const url = await uploadAvatarRequest(userId, file)
      setProfile((current) =>
        current ? { ...current, avatar_url: url } : current,
      )
      return url
    },
    [session],
  )

  const removeAvatar = useCallback(async () => {
    const userId = session?.user?.id
    if (!userId) {
      throw new Error('Sign in again to change your photo.')
    }
    await removeAvatarRequest(userId)
    setProfile((current) =>
      current ? { ...current, avatar_url: null } : current,
    )
  }, [session])

  /**
   * Save the manual foot size and adopt the row.
   *
   * The same write as the app's `saveFootProfile` (it is a plain column update
   * on the customer's own row, so it needs no RPC), and it goes through the
   * same `updateProfileRequest` the profile form uses — one write path, one
   * place where the returned row is adopted.
   */
  const saveFootProfile = useCallback(
    async (draft) => {
      const userId = session?.user?.id
      if (!userId) {
        throw new Error('Sign in again to save your size.')
      }
      const nextProfile = await updateProfileRequest(
        userId,
        footProfilePayload(draft),
      )
      setProfile(nextProfile)
      return nextProfile
    },
    [session],
  )

  /**
   * Record that the customer declined the size question.
   *
   * `foot_profile_source = 'skipped'` is what stops the app's reminder banner
   * nagging; it deliberately does not touch a size already on file, so someone
   * who skips after scanning once keeps the recommendation.
   */
  const skipFootProfile = useCallback(async () => {
    const userId = session?.user?.id
    if (!userId) {
      throw new Error('Sign in again to change this.')
    }
    const nextProfile = await updateProfileRequest(
      userId,
      footProfileSkippedPayload(),
    )
    setProfile(nextProfile)
    return nextProfile
  }, [session])

  /** Begin an email change. The session's address is unchanged until the
   *  confirmation link is opened, so nothing is adopted here. */
  const updateEmail = useCallback(
    (next) => updateEmailRequest(next),
    [],
  )

  /**
   * Finish a link-confirmed signup.
   *
   * Called by the `/auth/confirm` landing page once GoTrue has put a session in
   * the URL. Until this runs, the account has an `auth.users` row and no
   * `profiles` row — signed in, but with no name and no role.
   */
  const completeSignupFromEmailLink = useCallback(async () => {
    const { data } = await supabase.auth.getUser()
    if (!data?.user) return null

    const nextProfile = await writeProfileFromMetadata(data.user)
    setProfile(nextProfile)
    return nextProfile
  }, [])

  const value = useMemo(
    () => ({
      session,
      user: session?.user ?? null,
      profile,
      loading,
      accessDenied,
      isSignedIn: Boolean(session?.user),
      isCustomer: profile?.role === ROLES.CUSTOMER,
      isSeller: profile?.role === ROLES.SELLER,
      isAdmin: profile?.role === ROLES.ADMIN,
      deniedReason: accessDeniedReason(profile),
      signIn,
      signUp,
      signOut,
      refreshProfile,
      updatePassword,
      updateEmail,
      updateProfile,
      uploadAvatar,
      removeAvatar,
      saveFootProfile,
      skipFootProfile,
      completeSignupFromEmailLink,
    }),
    [
      session,
      profile,
      loading,
      accessDenied,
      signIn,
      signUp,
      signOut,
      refreshProfile,
      updatePassword,
      updateEmail,
      updateProfile,
      uploadAvatar,
      removeAvatar,
      saveFootProfile,
      skipFootProfile,
      completeSignupFromEmailLink,
    ],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used within AuthProvider')
  return context
}
