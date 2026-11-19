import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import MfaCard from '../components/MfaCard.jsx'
import Tooltip from '../components/ui/Tooltip.jsx'
import { User, Lock, AlertTriangle } from 'lucide-react'

export default function Settings() {
  const { profile, refreshProfile, signOut } = useAuth()
  const { showToast } = useToast()

  const [fullName, setFullName] = useState(profile?.full_name ?? '')
  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [savingProfile, setSavingProfile] = useState(false)
  const [savingPassword, setSavingPassword] = useState(false)

  const handleProfileSave = async (e) => {
    e.preventDefault()
    if (!profile?.id) return
    setSavingProfile(true)
    try {
      const { error } = await supabase
        .from('profiles')
        .update({ full_name: fullName.trim() })
        .eq('id', profile.id)
      if (error) throw error
      await refreshProfile()
      showToast('Profile updated')
    } catch (err) {
      showToast(err.message ?? 'Update failed', 'error')
    } finally {
      setSavingProfile(false)
    }
  }

  const handlePasswordChange = async (e) => {
    e.preventDefault()
    if (newPassword.length < 6) {
      showToast('Password must be at least 6 characters', 'error')
      return
    }
    if (newPassword !== confirmPassword) {
      showToast('Passwords do not match', 'error')
      return
    }
    setSavingPassword(true)
    try {
      const { error } = await supabase.auth.updateUser({ password: newPassword })
      if (error) throw error
      setNewPassword('')
      setConfirmPassword('')
      showToast('Password updated')
    } catch (err) {
      showToast(err.message ?? 'Password update failed', 'error')
    } finally {
      setSavingPassword(false)
    }
  }

  const handleSignOutAll = async () => {
    try {
      await supabase.auth.signOut({ scope: 'global' })
      await signOut()
      showToast('Signed out of all sessions')
    } catch (err) {
      showToast(err.message ?? 'Sign out failed', 'error')
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      {/* Admin Profile section */}
      <div className="overflow-hidden rounded-xl border border-border bg-card">
        <div className="flex items-center gap-2 border-b border-border px-6 py-4">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-canvas">
            <User size={16} className="text-primary" />
          </div>
          <h2 className="text-[15px] font-bold text-ink">Admin Profile</h2>
        </div>
        <form onSubmit={handleProfileSave} className="p-6 space-y-4">
          <div>
            <label className="mb-1.5 block text-[12px] font-medium text-muted">
              Full Name
            </label>
            <input
              type="text"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              className="w-full rounded-xl border border-border bg-canvas px-4 py-2.5 text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/20"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-[12px] font-medium text-muted">
              Email
            </label>
            <input
              type="email"
              value={profile?.email ?? ''}
              readOnly
              className="w-full rounded-xl border border-border bg-canvas px-4 py-2.5 text-muted"
            />
          </div>
          <Tooltip label="Saves the name shown to sellers and customers.">
            <button
              type="submit"
              disabled={savingProfile}
              className="rounded-xl bg-secondary px-6 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-primaryDeep disabled:opacity-50"
            >
              Save Profile
            </button>
          </Tooltip>
        </form>
      </div>

      {/* Two-Factor Authentication section */}
      <MfaCard />

      {/* Change Password section */}
      <div className="overflow-hidden rounded-xl border border-border bg-card">
        <div className="flex items-center gap-2 border-b border-border px-6 py-4">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-canvas">
            <Lock size={16} className="text-primary" />
          </div>
          <h2 className="text-[15px] font-bold text-ink">Change Password</h2>
        </div>
        <form onSubmit={handlePasswordChange} className="p-6 space-y-4">
          <div>
            <label className="mb-1.5 block text-[12px] font-medium text-muted">
              New Password
            </label>
            <input
              type="password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              className="w-full rounded-xl border border-border bg-canvas px-4 py-2.5 text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/20"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-[12px] font-medium text-muted">
              Confirm Password
            </label>
            <input
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="w-full rounded-xl border border-border bg-canvas px-4 py-2.5 text-ink outline-none transition-colors focus:border-primary focus:ring-2 focus:ring-primary/20"
            />
          </div>
          <Tooltip label="Changes the password you sign in with.">
            <button
              type="submit"
              disabled={savingPassword}
              className="rounded-xl bg-secondary px-6 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-primaryDeep disabled:opacity-50"
            >
              Update Password
            </button>
          </Tooltip>
        </form>
      </div>

      {/* Danger Zone */}
      <div className="rounded-xl border border-red-200 bg-red-50 p-6">
        <div className="flex items-center gap-2 mb-2">
          <AlertTriangle size={16} className="text-red-600" />
          <h2 className="text-[15px] font-bold text-red-700">Danger Zone</h2>
        </div>
        <p className="mb-4 text-sm text-red-600">
          Sign out of all devices and sessions linked to this admin account.
        </p>
        <Tooltip label="Ends every admin session, including this one.">
          <button
            type="button"
            onClick={handleSignOutAll}
            className="rounded-xl border border-red-400 px-4 py-2.5 text-sm font-semibold text-red-600 transition-colors hover:bg-red-100"
          >
            Sign out of all sessions
          </button>
        </Tooltip>
      </div>
    </div>
  )
}
