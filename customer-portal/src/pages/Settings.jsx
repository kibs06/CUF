import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Info, LogOut, MapPin, Ruler, ShieldCheck, Trash2 } from 'lucide-react'

import ThemeChoice from '../components/settings/ThemeChoice'
import { SettingsRow, SettingsSection } from '../components/settings/SettingsRow'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import Reveal from '../components/ui/Reveal'
import { useAuth } from '../hooks/useAuth.jsx'
import { footProfileSummary } from '../lib/footRules'
import { DELETION_CONSEQUENCE } from '../lib/securityRules'
import { requestAccountDeletion } from '../lib/support'

/** The portal's own version, substituted at build time by Vite. */
const VERSION =
  typeof __PORTAL_VERSION__ === 'string' ? __PORTAL_VERSION__ : 'dev'

/**
 * Settings.
 *
 * The app's four sections, in the app's order — Account, Appearance, Legal,
 * Support — with the rows that are honest on the web.
 *
 * Four of the app's rows are deliberately absent rather than ported as dead
 * ends, and each for a different reason:
 *
 *   • **Switch Account** is a multi-account phone affordance (a session per
 *     device, a switcher between them). A browser signs in one account at a
 *     time and signing out and back in is the same gesture, so a row here would
 *     promise something the platform does not have.
 *   • **What's New** exists because an installed app can be out of date: it
 *     shows the installed build against the latest release and offers the APK.
 *     A website cannot be out of date — the customer is running whatever was
 *     deployed a second ago — so a row here would have nothing to say. The
 *     portal's version is at the foot of this page instead, which is all that
 *     row ever shows.
 *   • **Help & Support** and **Terms & Privacy** are not built yet, on purpose.
 *     Both are prose: the help menu leads to a FAQ document and a support chat,
 *     and the customer Terms & Privacy document is ~950 lines of policy text
 *     living inside `terms_privacy_screen.dart`. Copying that into this
 *     codebase would create a second copy of a legal document that can drift
 *     from the one customers agreed to, which is the failure mode worth 
 *     avoiding — so it needs a decision about where the canonical text lives
 *     before it needs a page.
 *   • Account deletion IS here, because it is a function call rather than copy.
 *
 * The destructive two both confirm first, and both say what the consequence is:
 * signing out is recoverable and takes one sentence, deletion is not and lists
 * what goes with the account.
 */
export default function Settings() {
  const { profile, signOut } = useAuth()
  const navigate = useNavigate()

  const [confirm, setConfirm] = useState(null) // 'signout' | 'delete' | null
  const [working, setWorking] = useState(false)
  const [notice, setNotice] = useState(null) // { ok, message }
  const [error, setError] = useState(null)

  const initials = initialsOf(profile?.full_name, profile?.email)

  const onSignOut = async () => {
    setWorking(true)
    await signOut()
    setWorking(false)
    setConfirm(null)
    navigate('/')
  }

  const onRequestDeletion = async () => {
    setWorking(true)
    setError(null)
    try {
      const result = await requestAccountDeletion()
      setNotice(result)
      setConfirm(null)
    } catch (failure) {
      // The failure's own message is the useful one (`functionError` reads the
      // function's `{ error }` body), so it is shown rather than a generic.
      setError(failure?.message ?? 'We could not send that request.')
    } finally {
      setWorking(false)
    }
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-10 sm:px-6 lg:px-8">
      <header>
        <p className="overline">Your account</p>
        <h1 className="mt-2 font-display text-3xl font-semibold text-ink">
          Settings
        </h1>
      </header>

      {/* ── Who you are ───────────────────────────────────────────── */}
      <Reveal className="mt-6">
        <Link
          to="/account"
          className="flex items-center gap-4 rounded-card border border-hairline bg-raised p-4 shadow-card transition-[border-color,box-shadow] duration-300 ease-out-cubic hover:border-card-edge hover:shadow-card-lift"
        >
          <span className="h-12 w-12 shrink-0 overflow-hidden rounded-full bg-subtle">
            {profile?.avatar_url ? (
              <img
                src={profile.avatar_url}
                alt=""
                decoding="async"
                className="h-full w-full object-cover"
              />
            ) : (
              <span
                aria-hidden="true"
                className="num flex h-full items-center justify-center text-sm font-semibold text-clay-ink"
              >
                {initials}
              </span>
            )}
          </span>

          <span className="min-w-0 flex-1">
            <span className="block truncate font-display text-lg font-semibold text-ink">
              {profile?.full_name || 'Your account'}
            </span>
            <span className="mt-0.5 block truncate text-xs text-muted">
              {profile?.email}
            </span>
          </span>

          <span className="shrink-0 text-xs font-semibold text-clay-ink">
            Edit details
          </span>
        </Link>
      </Reveal>

      {notice && (
        <p
          role="status"
          className="mt-6 rounded-card border border-olive/40 bg-olive/[0.08] px-4 py-3 text-sm leading-relaxed text-ink"
        >
          {notice.message}
        </p>
      )}

      <div className="mt-8 space-y-8">
        {/* ── Account ─────────────────────────────────────────────── */}
        <SettingsSection title="Account">
          <SettingsRow
            to="/settings/security"
            Icon={ShieldCheck}
            title="Account & Security"
            subtitle={`Password, sign-in email${
              profile?.phone ? ` · ${profile.phone}` : ''
            }`}
          />
          <SettingsRow
            to="/settings/foot-size"
            Icon={Ruler}
            title="Size Your Foot"
            subtitle={footProfileSummary(profile)}
          />
          <SettingsRow
            to="/settings/addresses"
            Icon={MapPin}
            title="My Addresses"
            subtitle="Where your orders are delivered"
          />
        </SettingsSection>

        {/* ── Appearance ──────────────────────────────────────────── */}
        <section>
          <h2 className="overline">Appearance</h2>
          <ThemeChoice />
        </section>

        {/* ── Legal ───────────────────────────────────────────────── */}
        <SettingsSection title="Legal">
          <SettingsRow to="/settings/about" Icon={Info} title="About CUFMAI" />
        </SettingsSection>

        {/* ── Support ─────────────────────────────────────────────── */}
        <SettingsSection title="Support">
          <SettingsRow
            Icon={Trash2}
            title="Request Account Deletion"
            onClick={() => {
              setNotice(null)
              setConfirm('delete')
            }}
            danger
          />
        </SettingsSection>
      </div>

      {/* ── Sign out, and the version ─────────────────────────────── */}
      <div className="mt-10">
        <button
          type="button"
          onClick={() => {
            setNotice(null)
            setConfirm('signout')
          }}
          className="btn w-full border border-crimson/40 text-crimson transition-colors duration-200 hover:bg-crimson/[0.06]"
        >
          <LogOut size={16} strokeWidth={2} />
          Sign out
        </button>

        <p className="mt-6 text-center text-xs text-muted">
          CUFMAI storefront v{VERSION}
        </p>
      </div>

      <ConfirmDialog
        open={confirm === 'signout'}
        title="Sign out?"
        description="You will need your email and password to sign back in. Your cart and orders stay on your account."
        confirmLabel="Sign out"
        tone="primary"
        pending={working}
        onClose={() => setConfirm(null)}
        onConfirm={onSignOut}
      />

      <ConfirmDialog
        open={confirm === 'delete'}
        title="Request account deletion?"
        description={DELETION_CONSEQUENCE}
        confirmLabel="Request deletion"
        cancelLabel="Keep my account"
        pending={working}
        error={error}
        onClose={() => {
          setError(null)
          setConfirm(null)
        }}
        onConfirm={onRequestDeletion}
      />
    </div>
  )
}

function initialsOf(name, email) {
  const source = (name || email || '?').trim()
  const parts = source.split(/\s+/)
  if (parts.length >= 2) {
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
  }
  return source.slice(0, 2).toUpperCase()
}
