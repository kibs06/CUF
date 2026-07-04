import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth.jsx'
import { useToast } from '../components/ui/Toast.jsx'
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
    <div className="mx-auto max-w-2xl space-y-6">
      {/* Admin Profile section */}
      <div className="overflow-hidden rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
        <div className="flex items-center gap-2 border-b border-[#F5F0EB] px-6 py-4">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[#F5F0EB]">
            <User size={16} className="text-[#8B5A2B]" />
          </div>
          <h2 className="font-display text-lg font-semibold text-[#3B2314]">Admin Profile</h2>
        </div>
        <form onSubmit={handleProfileSave} className="p-6 space-y-4">
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              Full Name
            </label>
            <input
              type="text"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              Email
            </label>
            <input
              type="email"
              value={profile?.email ?? ''}
              readOnly
              className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 text-[#6B5C4E]"
            />
          </div>
          <button
            type="submit"
            disabled={savingProfile}
            className="rounded-xl bg-[#8B5A2B] px-6 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-[#6B4520] disabled:opacity-50"
          >
            Save Profile
          </button>
        </form>
      </div>

      {/* Change Password section */}
      <div className="overflow-hidden rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
        <div className="flex items-center gap-2 border-b border-[#F5F0EB] px-6 py-4">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[#F5F0EB]">
            <Lock size={16} className="text-[#8B5A2B]" />
          </div>
          <h2 className="font-display text-lg font-semibold text-[#3B2314]">Change Password</h2>
        </div>
        <form onSubmit={handlePasswordChange} className="p-6 space-y-4">
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              New Password
            </label>
            <input
              type="password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              Confirm Password
            </label>
            <input
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
            />
          </div>
          <button
            type="submit"
            disabled={savingPassword}
            className="rounded-xl bg-[#8B5A2B] px-6 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-[#6B4520] disabled:opacity-50"
          >
            Update Password
          </button>
        </form>
      </div>

      {/* Danger Zone */}
      <div className="rounded-2xl border border-red-200 bg-red-50 p-6">
        <div className="flex items-center gap-2 mb-2">
          <AlertTriangle size={16} className="text-red-600" />
          <h2 className="font-display text-lg font-semibold text-red-700">Danger Zone</h2>
        </div>
        <p className="mb-4 text-sm text-red-600">
          Sign out of all devices and sessions linked to this admin account.
        </p>
        <button
          type="button"
          onClick={handleSignOutAll}
          className="rounded-xl border border-red-400 px-4 py-2.5 text-sm font-semibold text-red-600 transition-colors hover:bg-red-100"
        >
          Sign out of all sessions
        </button>
      </div>
    </div>
  )
}
