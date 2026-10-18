import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { ROLES } from '../lib/constants'
import { needsMfa } from '../lib/mfa'

const AuthContext = createContext(null)

async function fetchProfile(userId) {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .maybeSingle()

  if (error) throw error
  return data
}

// Hard-enforcement gate for the portal: only an ACTIVE admin may use it.
// Suspended accounts (even admins) are signed out immediately.
function isBlocked(profile) {
  return profile?.role !== ROLES.ADMIN || !!profile?.suspended
}

function blockReason(profile) {
  if (profile?.suspended) return 'Your admin account has been suspended.'
  return 'Access denied. This portal is for admins only.'
}

/**
 * Best-effort session logging for the "Seller sessions" audit trail.
 *
 * Sign-ins touch no public table, so the trail only exists if the clients
 * write it. Swallowed on failure — history is analytics, never auth — and
 * sign-outs are logged BEFORE the session is dropped (afterwards the INSERT
 * policy, auth.uid() = user_id, rejects the anonymous client).
 */
async function logSessionEvent(userId, event, role) {
  if (!userId) return
  try {
    await supabase.from('account_session_log').insert({
      user_id: userId,
      event,
      role: role ?? null,
      source: 'admin-portal',
      user_agent: typeof navigator !== 'undefined' ? navigator.userAgent : null,
    })
  } catch {
    // Never block auth on analytics.
  }
}

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null)
  const [profile, setProfile] = useState(null)
  const [loading, setLoading] = useState(true)
  const [accessDenied, setAccessDenied] = useState(false)

  useEffect(() => {
    let mounted = true

    async function init() {
      const { data } = await supabase.auth.getSession()
      if (!mounted) return

      const currentSession = data.session
      setSession(currentSession)

      if (currentSession?.user) {
        try {
          const userProfile = await fetchProfile(currentSession.user.id)
          if (isBlocked(userProfile)) {
            await supabase.auth.signOut()
            setAccessDenied(true)
            setProfile(null)
            setSession(null)
          } else {
            setProfile(userProfile)
            setAccessDenied(false)
          }
        } catch {
          await supabase.auth.signOut()
          setProfile(null)
          setSession(null)
        }
      }

      setLoading(false)
    }

    init()

    const { data: listener } = supabase.auth.onAuthStateChange(async (_event, newSession) => {
      setSession(newSession)
      if (!newSession?.user) {
        setProfile(null)
        return
      }

      try {
        const userProfile = await fetchProfile(newSession.user.id)
        if (isBlocked(userProfile)) {
          await supabase.auth.signOut()
          setAccessDenied(true)
          setProfile(null)
          setSession(null)
        } else {
          setProfile(userProfile)
          setAccessDenied(false)
        }
      } catch {
        await supabase.auth.signOut()
        setProfile(null)
        setSession(null)
      }
    })

    return () => {
      mounted = false
      listener.subscription.unsubscribe()
    }
  }, [])

  const signIn = async (email, password) => {
    setAccessDenied(false)
    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    })
    if (error) throw error

    const userProfile = await fetchProfile(data.user.id)
    if (isBlocked(userProfile)) {
      await supabase.auth.signOut()
      setAccessDenied(true)
      throw new Error(blockReason(userProfile))
    }

    setProfile(userProfile)
    setSession(data.session)
    await logSessionEvent(data.user.id, 'sign_in', userProfile?.role)
    return userProfile
  }

  const signOut = async () => {
    const uid = session?.user?.id
    if (uid) await logSessionEvent(uid, 'sign_out', profile?.role)
    await supabase.auth.signOut()
    setProfile(null)
    setSession(null)
    setAccessDenied(false)
  }

  const refreshProfile = async () => {
    if (!session?.user) return
    const userProfile = await fetchProfile(session.user.id)
    setProfile(userProfile)
  }

  const value = useMemo(
    () => ({
      session,
      profile,
      loading,
      accessDenied,
      isAdmin: profile?.role === ROLES.ADMIN,
      mfaRequired: needsMfa(session),
      signIn,
      signOut,
      refreshProfile,
    }),
    [session, profile, loading, accessDenied],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
