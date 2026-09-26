import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { LogOut, Package, Receipt, Settings as SettingsIcon, ShoppingBag } from 'lucide-react'

import PasswordForm from '../components/account/PasswordForm'
import ProfileForm from '../components/account/ProfileForm'
import Reveal from '../components/ui/Reveal'
import { useAuth } from '../hooks/useAuth.jsx'
import { useCart } from '../hooks/useCart.jsx'
import { formatCurrency, getInitials } from '../lib/constants'

export default function Account() {
  const { profile, user, signOut } = useAuth()
  const { count, subtotal, items } = useCart()

  // Arriving from a password-reset link is a "you are here to change your
  // password" moment, so the banner points at the form below rather than it
  // sitting unannounced below the fold.
  const [fromRecovery, setFromRecovery] = useState(false)
  useEffect(() => {
    if (window.location.hash.includes('type=recovery')) setFromRecovery(true)
  }, [])

  return (
    <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6 lg:px-8">
      <header className="flex items-center gap-5">
        <span className="relative h-16 w-16 shrink-0 overflow-hidden rounded-full border border-hairline bg-subtle sm:h-20 sm:w-20">
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
              className="num flex h-full items-center justify-center text-lg font-semibold text-clay-ink sm:text-xl"
            >
              {getInitials(profile?.full_name || profile?.email || user?.email)}
            </span>
          )}
        </span>

        <div className="min-w-0">
          <p className="overline">Your account</p>
          <h1 className="mt-2 truncate font-display text-3xl font-semibold text-ink sm:text-4xl">
            {profile?.full_name || 'Your details'}
          </h1>
          <p className="mt-2 truncate text-sm text-muted">{user?.email}</p>
        </div>
      </header>

      {fromRecovery && (
        <div className="mt-6 rounded-field border border-clay/30 bg-clay/[0.07] px-4 py-3 text-sm text-ink">
          You followed a password reset link. Choose a new password below.
        </div>
      )}

      {/*
        The order history gets its own row above the details, not a card in the
        side column. A customer who opens their account is usually looking for
        one of three things — what did I order, what did I spend, where is my
        password — and the first of those now has somewhere to go.
      */}
      <Reveal className="mt-8 flex flex-wrap items-center justify-between gap-4 rounded-card border border-hairline bg-raised p-5 shadow-card">
        <div className="flex items-center gap-4">
          <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-premium bg-clay/10">
            <Receipt size={20} className="text-clay-ink" strokeWidth={1.75} />
          </span>
          <div>
            <h2 className="font-display text-lg font-semibold text-ink">
              Your orders
            </h2>
            <p className="mt-0.5 text-xs text-muted">
              Track a pair, check a payment, or cancel something you changed
              your mind about.
            </p>
          </div>
        </div>
        <Link to="/orders" className="btn btn-outline">
          Open orders
        </Link>
      </Reveal>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_20rem]">
        {/* ── Details ────────────────────────────────────────────── */}
        <Reveal>
          <ProfileForm />
        </Reveal>

        {/* ── Side column ────────────────────────────────────────── */}
        <div className="space-y-6">
          <Reveal
            delay={0.05}
            className="rounded-card border border-hairline bg-raised p-6 shadow-card"
          >
            <h2 className="font-display text-lg font-semibold text-ink">
              Your cart
            </h2>
            {count > 0 ? (
              <>
                <p className="mt-2 text-sm text-muted">
                  {count} {count === 1 ? 'pair' : 'pairs'} across{' '}
                  {items.length === 1 ? '1 line' : `${items.length} lines`}
                </p>
                <p className="num mt-3 text-2xl font-semibold text-ink">
                  {formatCurrency(subtotal)}
                </p>
                <Link to="/cart" className="btn btn-outline mt-5 w-full">
                  <ShoppingBag size={16} strokeWidth={2} />
                  View cart
                </Link>
              </>
            ) : (
              <>
                <p className="mt-2 text-sm text-muted">
                  Nothing in your cart yet.
                </p>
                <Link to="/shop" className="btn btn-outline mt-5 w-full">
                  <Package size={16} strokeWidth={2} />
                  Browse the catalog
                </Link>
              </>
            )}
          </Reveal>

          <Reveal
            delay={0.1}
            className="rounded-card border border-hairline bg-raised p-6 shadow-card"
          >
            <h2 className="font-display text-lg font-semibold text-ink">
              Change password
            </h2>
            <div className="mt-4">
              <PasswordForm
                idPrefix="account-password"
                autoFocus={fromRecovery}
                onDone={() => setFromRecovery(false)}
              />
            </div>
          </Reveal>

          <Reveal delay={0.15} className="space-y-3">
            <Link to="/settings" className="btn btn-outline w-full">
              <SettingsIcon size={16} strokeWidth={2} />
              Settings
            </Link>
            <button
              type="button"
              onClick={signOut}
              className="btn btn-outline w-full"
            >
              <LogOut size={16} strokeWidth={2} />
              Sign out
            </button>
          </Reveal>
        </div>
      </div>
    </div>
  )
}

