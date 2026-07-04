import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { ROLES } from '../lib/constants'

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
          if (userProfile?.role !== ROLES.ADMIN) {
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
        if (userProfile?.role !== ROLES.ADMIN) {
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
    if (userProfile?.role !== ROLES.ADMIN) {
      await supabase.auth.signOut()
      setAccessDenied(true)
      throw new Error('Access denied. This portal is for admins only.')
    }

    setProfile(userProfile)
    setSession(data.session)
    return userProfile
  }

  const signOut = async () => {
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
