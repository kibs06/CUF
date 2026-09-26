import { useEffect, useRef, useState } from 'react'
import { Link, NavLink } from 'react-router-dom'
import { Bell, LogOut, MessageSquare, Receipt, Settings, User, UserCircle } from 'lucide-react'

import { useAuth } from '../../hooks/useAuth.jsx'
import { useUnreadThreadCount } from '../../hooks/useMessages.js'
import { useUnreadNotificationCount } from '../../hooks/useNotifications.js'

/**
 * The header's account control.
 *
 * Signed out it is a plain link; signed in it is a menu showing the customer's
 * initials — the same pair of initials the store avatars use, so the account
 * reads as theirs rather than as a generic avatar.
 *
 * Closes on Escape and on a click outside. Both matter: a menu that can only be
 * dismissed by pressing its own button traps a keyboard user inside it.
 *
 * The panel is mounted only while `open`, and animates in with CSS
 * (`drop-enter`). It used to be an `AnimatePresence` pair, which kept a closed
 * menu in the DOM until motion reported its exit finished — and a closed menu
 * that is still mounted is a 240px panel of links and buttons sitting over the
 * header, still focusable, still taking the clicks that land on it. See
 * "Animations must fail open" in the README.
 *
 * ## The shape of the panel
 *
 * Three parts, in the order a customer wants them: who they are, where they are
 * going, and the way out. The rows use the header's own active treatment
 * (`bg-clay/10 text-clay-ink`) rather than a hover-only highlight, because a
 * menu opened from `/orders` should say that you are already there — otherwise
 * the first click is a wasted one. Sign out sits alone under a hairline and
 * tints crimson on hover: it is the only row here that does something you
 * cannot undo by navigating away.
 */
export default function AccountMenu() {
  const { isSignedIn, profile, signOut } = useAuth()
  const [open, setOpen] = useState(false)
  const containerRef = useRef(null)

  /*
    The unread count is a HEAD count, not the feed: this component renders in
    the header of every page, and downloading a customer's notifications to
    draw one number would be the most expensive thing on the site. It is still
    behind sign-in (`enabled` in the hook) and RLS, so a signed-out visitor
    asks for nothing.
  */
  const { data: unreadCount = 0 } = useUnreadNotificationCount()

  /*
    Messages get a badge too, and it counts THREADS with something unread —
    the app's own rule (`if (count > 0) total++`) — so it can never outgrow the
    inbox it is badging. Both numbers are behind sign-in and RLS.
  */
  const { data: unreadThreads = 0 } = useUnreadThreadCount()

  useEffect(() => {
    if (!open) return undefined

    const onPointerDown = (event) => {
      if (!containerRef.current?.contains(event.target)) setOpen(false)
    }
    const onKeyDown = (event) => {
      if (event.key === 'Escape') setOpen(false)
    }

    document.addEventListener('pointerdown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [open])

  if (!isSignedIn) {
    return (
      <Link
        to="/signin"
        className="inline-flex h-10 items-center gap-2 rounded-full border border-hairline px-4 text-sm font-semibold text-muted-strong transition-colors duration-200 ease-out-cubic hover:border-card-edge hover:bg-subtle hover:text-ink"
      >
        <User size={16} strokeWidth={2} />
        <span className="hidden sm:inline">Sign in</span>
      </Link>
    )
  }

  const initials = initialsOf(profile?.full_name, profile?.email)
  /*
    The photo when there is one, the initials when there is not. Both are the
    same 40px circle so the control never changes size, and the initials are
    exactly the avatar's fallback everywhere else on the site.

    `avatar_url` is used VERBATIM. Its `?t=` stamp is written once, at upload
    time; re-stamping it here would produce a different string on every render,
    which makes the browser re-fetch the image on every pass of the tree.
  */
  const avatarUrl = profile?.avatar_url || null

  return (
    <div ref={containerRef} className="relative">
      <button
        type="button"
        onClick={() => setOpen((current) => !current)}
        aria-expanded={open}
        aria-haspopup="menu"
        className={`num inline-flex h-10 w-10 items-center justify-center overflow-hidden rounded-full text-sm font-semibold transition-colors duration-200 ease-out-cubic ${
          avatarUrl ? 'bg-subtle ring-1 ring-hairline' : 'bg-clay/12 text-clay-ink hover:bg-clay/20'
        }`}
      >
        <span className="sr-only">Your account</span>
        {avatarUrl ? (
          <img
            src={avatarUrl}
            alt=""
            decoding="async"
            className="h-full w-full object-cover"
          />
        ) : (
          <span aria-hidden="true">{initials}</span>
        )}
      </button>

      {open && (
        <div
          role="menu"
          className="drop-enter absolute right-0 z-50 mt-2 w-60 origin-top-right overflow-hidden rounded-card border border-hairline bg-raised shadow-card-lift"
        >
          <div className="flex items-center gap-3 border-b border-hairline bg-subtle/60 px-4 py-3">
            <span className="h-10 w-10 shrink-0 overflow-hidden rounded-full bg-raised ring-1 ring-hairline">
              {avatarUrl ? (
                <img
                  src={avatarUrl}
                  alt=""
                  decoding="async"
                  className="h-full w-full object-cover"
                />
              ) : (
                <span
                  aria-hidden="true"
                  className="num flex h-full items-center justify-center text-xs font-semibold text-clay-ink"
                >
                  {initials}
                </span>
              )}
            </span>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-ink">
                {profile?.full_name || 'Your account'}
              </p>
              <p className="truncate text-xs text-muted" title={profile?.email}>
                {profile?.email}
              </p>
            </div>
          </div>

          {/*
            Orders sits ABOVE the account details: it is the reason a
            signed-in customer opens this menu at all, and burying it under
            "Account details" would make them hunt for it through the profile
            page.
          */}
          <div className="py-1">
            <MenuLink to="/orders" icon={Receipt} onNavigate={() => setOpen(false)}>
              Your orders
            </MenuLink>
            {/*
              Notifications sits directly under orders: both are news about
              something the customer already did, and the badge is the reason
              the menu is opened on a second visit. The count is capped at 99+
              so the row's layout cannot be pushed around by a four-digit
              number.
            */}
            <MenuLink
              to="/notifications"
              icon={Bell}
              badge={unreadCount > 99 ? '99+' : unreadCount || null}
              onNavigate={() => setOpen(false)}
            >
              Notifications
            </MenuLink>
            {/*
              Messages sit under notifications: both are "someone is waiting on
              you", and a reply from a maker is the one thing on this list the
              customer might need to act on today.
            */}
            <MenuLink
              to="/messages"
              icon={MessageSquare}
              badge={unreadThreads > 99 ? '99+' : unreadThreads || null}
              badgeLabel="conversations unread"
              onNavigate={() => setOpen(false)}
            >
              Messages
            </MenuLink>
            <MenuLink to="/account" icon={UserCircle} onNavigate={() => setOpen(false)}>
              Account details
            </MenuLink>
            {/*
              Settings comes last, after the two things the menu is actually
              for. It is the fourth item in a menu that closes on a click, so
              anything above it is competing with "where is my order" — which
              is why account deletion, theme and the address book all live one
              level in rather than here.
            */}
            <MenuLink to="/settings" icon={Settings} onNavigate={() => setOpen(false)}>
              Settings
            </MenuLink>
          </div>

          <div className="border-t border-hairline py-1">
            <button
              type="button"
              role="menuitem"
              onClick={() => {
                setOpen(false)
                signOut()
              }}
              className="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-muted-strong transition-colors duration-200 ease-out-cubic hover:bg-crimson/10 hover:text-ink"
            >
              <LogOut size={16} strokeWidth={2} />
              Sign out
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

/**
 * A row in the panel. All three are the same recipe — icon, label, the active
 * treatment when the route underneath the menu is already this one — so the
 * `Settings` row cannot drift away from the other two the way it did when the
 * markup was repeated three times.
 */
function MenuLink({
  to,
  icon: Icon,
  badge = null,
  badgeLabel = 'unread',
  onNavigate,
  children,
}) {
  return (
    <NavLink
      to={to}
      role="menuitem"
      onClick={onNavigate}
      className={({ isActive }) =>
        [
          'flex items-center gap-2.5 px-4 py-2.5 text-sm transition-colors duration-200 ease-out-cubic',
          isActive
            ? 'bg-clay/10 font-medium text-clay-ink'
            : 'text-muted-strong hover:bg-subtle hover:text-ink',
        ].join(' ')
      }
    >
      <Icon size={16} strokeWidth={2} />
      <span className="min-w-0 flex-1 truncate">{children}</span>
      {badge && (
        <span className="num pop-enter inline-flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-clay px-1 text-[11px] font-semibold text-ink-inverse">
          {badge}
          {/* The number is decoration on a row whose label already says where
              it goes; the screen-reader form of "3 unread" is in the text. */}
          <span className="sr-only"> {badgeLabel}</span>
        </span>
      )}
    </NavLink>
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
