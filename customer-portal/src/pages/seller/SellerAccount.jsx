import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  LayoutDashboard,
  LogOut,
  Package,
  Receipt,
  Store,
  TrendingUp,
} from 'lucide-react'

import PasswordForm from '../../components/account/PasswordForm.jsx'
import ThemeChoice from '../../components/settings/ThemeChoice.jsx'
import {
  SettingsRow,
  SettingsSection,
} from '../../components/settings/SettingsRow.jsx'
import {
  SellerPageBody,
  SellerPageHeader,
} from '../../components/seller/SellerPage.jsx'
import { useAuth } from '../../hooks/useAuth.jsx'
import { getInitials } from '../../lib/constants.js'

/** The portal's own version, substituted at build time by Vite. */
const VERSION = typeof __PORTAL_VERSION__ === 'string' ? __PORTAL_VERSION__ : 'dev'

/**
 * Where else the seller can go, as the options list on this page.
 *
 * Six destinations live in the bar above, so this is not the portal's only map
 * — it is the shop's own habit, kept: `/settings` sends a customer to the
 * screens that belong to their account, and this page does the same for a
 * seller. Each row's subtitle is *what the screen is for* rather than a count,
 * because a count here would be a second, staler copy of a number the page
 * itself already computes.
 */
const PORTAL_ROWS = [
  {
    to: '/seller',
    Icon: LayoutDashboard,
    title: 'Dashboard',
    subtitle: "Today's sales, and the jobs waiting on you",
  },
  {
    to: '/seller/orders',
    Icon: Receipt,
    title: 'Orders',
    subtitle: 'Every order placed against your storefront',
  },
  {
    to: '/seller/products',
    Icon: Package,
    title: 'Products',
    subtitle: 'What you sell, and the stock behind each size',
  },
  {
    to: '/seller/store',
    Icon: Store,
    title: 'Storefront',
    subtitle: 'What customers read on your card and your store page',
  },
  {
    to: '/seller/reports',
    Icon: TrendingUp,
    title: 'Reports',
    subtitle: 'Storefront revenue over the last 7, 30 or 90 days',
  },
]

/**
 * The seller's own account.
 *
 * ## Why this page exists at all
 *
 * It exists because the shop is closed to sellers (`AppLayout` redirects them to
 * `/seller`), and `/settings` — the only place in the portal with a sign-out
 * button — lives inside the shop. Closing one without adding the other would
 * have left a seller with no way to leave their session, which is not a missing
 * feature but a broken one: a shared computer and a seller who cannot sign out
 * is somebody else's orders on the screen.
 *
 * It is composed from the same pieces `/settings` uses rather than being a
 * second implementation of them — `PasswordForm`, `ThemeChoice` and the
 * `SettingsRow`/`SettingsSection` pair are all shared components, so a password
 * rule or a theme option added to one page is added to both. What is *not*
 * copied across is the customer half of `/settings`: there is no Size Your Foot,
 * no Addresses, no cart, and no account-deletion request, which belongs to a
 * customer support flow rather than a seller's.
 *
 * ## One column, not four cards
 *
 * The page was a two-column grid of four `SellerSection` cards, and that was the
 * wrong shape for what it holds: nothing here is a dashboard reading, and two
 * columns of unequal-height cards turn four unrelated settings into a layout the
 * eye has to scan in both directions. It is now the shape `/settings` uses — one
 * narrow column of **separated rows**, so each option is one line at one left
 * edge and the only thing separating two of them is a hairline. That also makes
 * this page narrower than the rest of the portal (`max-w-3xl` against
 * `SellerPageBody`'s `max-w-7xl`), which is deliberate rather than a slip: a
 * column of full-width rows sets a reading line of 1300px at a chevron nobody
 * can reach, and the shop's own settings page makes the identical exception.
 *
 * The sign-out keeps the shop's treatment — a crimson outline button at the end
 * of the column, not a row — because it is not a destination and should not look
 * like one.
 *
 * ## One deliberate omission
 *
 * **Changing the sign-in e-mail is not here.** It is a two-sided flow — GoTrue
 * mails a confirmation to the new address and a notice to the old one, and the
 * change is not in effect until the link is opened — and `/settings/security`
 * already owns those words. Rather than a second copy of that explanation
 * drifting from the first, the identity card says where it lives.
 */
export default function SellerAccount() {
  const { profile, signOut } = useAuth()
  const navigate = useNavigate()
  const [signingOut, setSigningOut] = useState(false)

  const onSignOut = async () => {
    setSigningOut(true)
    await signOut()
    // `replace` so the back button cannot return to a portal the session no
    // longer opens — the same reason sign-in uses it.
    navigate('/', { replace: true })
  }

  return (
    <SellerPageBody>
      <div className="mx-auto flex w-full max-w-3xl flex-col gap-8">
        <SellerPageHeader
          eyebrow="Your account"
          title="Account"
          description="Your sign-in details, and how the seller portal looks on this device."
        />

        {/* ── Who you are ─────────────────────────────────────────── */}
        <div>
          <div className="flex items-center gap-4 rounded-card border border-hairline bg-raised p-4 shadow-card">
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
                  {getInitials(profile?.full_name || profile?.email)}
                </span>
              )}
            </span>

            <span className="min-w-0 flex-1">
              <span className="block truncate font-display text-lg font-semibold text-ink">
                {profile?.full_name || 'Your account'}
              </span>
              <span className="mt-0.5 block truncate text-xs text-muted">
                {profile?.email || '—'}
              </span>
            </span>
          </div>

          <p className="mt-2 text-xs leading-relaxed text-muted">
            To change your name or your sign-in address, use the CUFMAI app.
            Changing the address needs a confirmation link sent to both the old
            and the new one, which is a two-sided flow the app already owns.
          </p>
        </div>

        {/* ── Your portal ─────────────────────────────────────────── */}
        <SettingsSection title="Your portal">
          {PORTAL_ROWS.map((row) => (
            <SettingsRow key={row.to} {...row} />
          ))}
        </SettingsSection>

        {/* ── Password ────────────────────────────────────────────── */}
        <section>
          <h2 className="overline">Password</h2>
          <p className="mt-2 text-xs leading-relaxed text-muted">
            The same password signs you in on the app.
          </p>
          <div className="mt-3 rounded-card border border-hairline bg-raised p-5 shadow-card">
            <PasswordForm idPrefix="seller-password" />
          </div>
        </section>

        {/* ── Appearance ──────────────────────────────────────────── */}
        <section>
          <h2 className="overline">Appearance</h2>
          <ThemeChoice />
        </section>

        {/* ── Sign out, and the version ───────────────────────────── */}
        <div className="mt-2">
          <button
            type="button"
            onClick={onSignOut}
            disabled={signingOut}
            className="btn w-full border border-crimson/40 text-crimson transition-colors duration-200 hover:bg-crimson/[0.06]"
          >
            <LogOut size={16} strokeWidth={2} />
            {signingOut ? 'Signing out…' : 'Sign out'}
          </button>

          <p className="mt-3 text-xs leading-relaxed text-muted">
            No confirmation step: signing out is undoable by signing back in, and
            a dialog on the way out of a shared computer is a keystroke standing
            between a seller and a closed session.
          </p>

          <p className="mt-6 text-center text-xs text-muted">
            CUFMAI seller portal v{VERSION}
          </p>
        </div>
      </div>
    </SellerPageBody>
  )
}
