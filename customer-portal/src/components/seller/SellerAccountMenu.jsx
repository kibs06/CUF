import { useEffect, useRef, useState } from 'react'
import { NavLink } from 'react-router-dom'
import { Bell, LogOut, MessageSquare, UserCircle } from 'lucide-react'

import CountBadge from '../ui/CountBadge.jsx'
import { useAuth } from '../../hooks/useAuth.jsx'
import { useSellerPanel } from '../../hooks/useSellerPanel.jsx'
import { useUnreadSellerNotificationCount } from '../../hooks/useSellerNotifications.js'
import { useUnreadStoreThreadCount } from '../../hooks/useSellerMessages.js'
import { getInitials } from '../../lib/constants.js'
import { waitingCount } from '../../lib/badgeRules.js'

/**
 * The seller bar's account control.
 *
 * It is the shop's `AccountMenu` in shape — a 40px circle that is the seller's
 * own photo when there is one and their initials when there is not, opening a
 * panel that says who they are and then what they can do — and it exists because
 * **"Account" does not belong in a navigation bar as a word.** The bar above
 * lists where the work is (Dashboard, Orders, Products, Storefront, Reports);
 * "Account" is not one of those, it is *who is signed in*, and the thing every
 * other site puts there is the face. The word was also the only pill in the row
 * that told a seller nothing they could not already guess from a picture.
 *
 * ## What is in the panel, and what is deliberately not
 *
 * **Alerts, then the account, then the way out.** Notifications and Messages sit
 * at the top with their unread counts, exactly as they do in the shop's menu,
 * because both are "someone is waiting on you" — the reason a person opens this
 * menu on a second visit. Then the account page, then Sign out under a hairline.
 *
 * Those two rows **open the side panel** and do not navigate, which is the whole
 * reason they are `button`s: nothing about them changes the URL, and a link that
 * does not navigate is a lie to anyone who middle-clicks it. The panel's own
 * header links to each one's real page for when a page is what someone wants.
 *
 * They are also the **only** way in. Two icon buttons in the bar came first, and
 * were taken out, and were tried a second time — so the icons are not an idea
 * nobody had, they are one that lost twice: beside five pills and a face on a
 * 64px row, a bell and an inbox are two more 40px circles whose meaning is a
 * tooltip, saying the same thing (someone is waiting on you) in two shapes. The
 * menu is one click away from every page, and these two rows are its first two.
 *
 * The **five destinations are not repeated** in the panel. They are places, the
 * bar already lists every one of them, and a menu that echoed them would be a
 * second, shorter copy of the navigation directly under it. Alerts are not
 * places: a seller does not *go* to a count, and the number has to be visible
 * from wherever they are — which is why these two live here rather than in the
 * bar itself, where two more icon buttons competed with the five pills and the
 * face for a 64px row.
 *
 * ## The count is now on the face
 *
 * There is a badge on the avatar whenever anything is unread, and it is the sum
 * of the two numbers below rather than either one of them: the question the bar
 * can answer is *is anything waiting on me*, and which kind is the question the
 * menu's own rows answer the moment it opens. It is not a third control and it
 * is not a bell — that argument was lost twice already — it is the same 40px face
 * with a number on its corner, so nothing was added to a row that was already
 * full.
 *
 * It also fixes a real gap rather than decorating one. **A menu whose counts are
 * only drawn inside it has to be opened to find out whether it is worth
 * opening** — so the seller's only way to know an order had arrived was to go
 * looking. The badge is drawn from the same two queries the rows read, so it
 * cannot disagree with them, and the realtime channels that invalidate those keys
 * are in the shell (`SellerLayout`'s `SellerRealtime`), which is what lets the
 * number move while the seller is reading an order.
 *
 * **Sign out moved in here**, which reverses an earlier decision. `SellerHeader`
 * used to keep it as a visible button, on the reasoning that leaving a shared
 * machine is the one thing a seller must be able to do from anywhere — but that
 * button was spending the bar's right-hand space on a control that is used once
 * per session, and the same click is still available from every page through
 * this menu. Nothing else about the reasoning changed: there is still no
 * confirmation step, and the row still tints crimson because it is the only
 * thing here that cannot be undone by navigating away.
 *
 * Escape and a click outside both close the panel, exactly as in the shop: a
 * menu that can only be dismissed by pressing its own button traps a keyboard
 * user inside it. The panel is mounted only while open and enters with CSS
 * (`drop-enter`) rather than a motion exit — see "Animations must fail open" in
 * the README; the closed state is the absent one.
 */
export default function SellerAccountMenu({ storeId, onSignOut }) {
  const { profile } = useAuth()
  const [open, setOpen] = useState(false)
  const containerRef = useRef(null)

  /*
    The counts are read HERE, at the button, and not only inside the panel — and
    that is the whole reason the badge can exist. Two consequences, both wanted:

     1. the numbers are fetched on every seller page rather than the moment the
        menu is opened, so the badge is already right when the seller looks at it
        (and so the first paint of the panel is right too, instead of flashing
        two empty rows);
     2. the queries have a live observer on every page, which is what the
        shell's realtime invalidation needs to actually redraw a badge — an
        invalidation with nothing mounted is just a cache mark, so a badge that
        existed only in the panel would move only when the panel was opened,
        which is the one moment it does not need to.

    Both are `HEAD` counts, and both are gated on `storeId`, so a seller who has
    not finished setting up a store asks for nothing.
  */
  const { data: unreadNotifications = 0 } = useUnreadSellerNotificationCount(storeId)
  const { data: unreadThreads } = useUnreadStoreThreadCount(storeId)
  /*
    The sum, not either half — `waitingCount` is what makes a half-loaded pair
    still produce a badge (one query landing before the other is the normal case,
    and `undefined + 3` on its own would blank a number that has a good answer in
    the other hand). See `badgeRules.js`.
  */
  const waiting = waitingCount(unreadNotifications, unreadThreads)

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

  const initials = getInitials(profile?.full_name || profile?.email)
  /*
    The photo when there is one, the initials when there is not — the same 40px
    circle either way, so the bar's row never changes height.

    `avatar_url` is used VERBATIM: its `?t=` stamp is written once, at upload
    time, and re-stamping it here would give the browser a new URL on every
    render and a re-fetch with it.
  */
  const avatarUrl = profile?.avatar_url || null

  return (
    <div ref={containerRef} className="relative">
      {/*
        The badge is a SIBLING of the button, not a child, and that is forced by
        the button's `overflow-hidden`: the avatar is a clipped circle, so a badge
        drawn inside it would be cut off at the corner it is meant to sit on. The
        badge carries no `label`, because the button's own `aria-label` already
        says the number — see `CountBadge` for why the digit is then hidden from a
        screen reader rather than announced twice.
      */}
      <CountBadge
        count={waiting}
        className="absolute -right-1 -top-1 z-10"
      />

      <button
        type="button"
        onClick={() => setOpen((current) => !current)}
        aria-expanded={open}
        aria-haspopup="menu"
        aria-label={
          waiting > 0 ? `Your account, ${waiting} unread` : 'Your account'
        }
        className={`num inline-flex h-10 w-10 items-center justify-center overflow-hidden rounded-full text-sm font-semibold transition-colors duration-200 ease-out-cubic ${
          avatarUrl
            ? 'bg-subtle ring-1 ring-hairline hover:ring-card-edge'
            : 'bg-clay/[0.12] text-clay-ink hover:bg-clay/20'
        }`}
      >
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
        <SellerAccountPanel
          profile={profile}
          avatarUrl={avatarUrl}
          initials={initials}
          unreadNotifications={unreadNotifications}
          unreadThreads={unreadThreads}
          onSignOut={onSignOut}
          onNavigate={() => setOpen(false)}
        />
      )}
    </div>
  )
}

/**
 * The panel itself, split out of the button so it can be rendered on its own.
 *
 * Not tidiness: the panel exists only inside the `open` branch above, and a
 * component that is reachable only through a click is a component no harness can
 * render without simulating one. Everything that decides what the panel *says*
 * lives here, and the button above is left holding the state, the outside-click
 * and the Escape key.
 *
 * It takes its two counts as **props** rather than reading them itself, for the
 * same reason it is split out at all: they already exist one level up — the face
 * draws them — and a component that fetched its own copy could disagree with the
 * badge on the avatar it hangs from. One number, one reader, two places it is
 * drawn.
 */
export function SellerAccountPanel({
  profile,
  avatarUrl,
  initials,
  unreadNotifications = 0,
  unreadThreads = 0,
  onSignOut,
  onNavigate,
}) {
  return (
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

      {/* Alerts first, and in the order the shop's menu uses: notifications
          above messages, because both are news and the newer kind is the one a
          seller is more likely to be looking for. */}
      <div className="py-1">
        <PanelRow
          panel="notifications"
          icon={Bell}
          badge={unreadNotifications}
          badgeLabel="unread notifications"
          onNavigate={onNavigate}
        >
          Notifications
        </PanelRow>
        <PanelRow
          panel="messages"
          icon={MessageSquare}
          badge={unreadThreads}
          badgeLabel="conversations needing a reply"
          onNavigate={onNavigate}
        >
          Messages
        </PanelRow>
      </div>

      <div className="border-t border-hairline py-1">
        <MenuRow to="/seller/account" icon={UserCircle} onNavigate={onNavigate}>
          Account settings
        </MenuRow>
      </div>

      <div className="border-t border-hairline py-1">
        <button
          type="button"
          role="menuitem"
          onClick={() => {
            onNavigate?.()
            onSignOut?.()
          }}
          className="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-muted-strong transition-colors duration-200 ease-out-cubic hover:bg-crimson/10 hover:text-ink"
        >
          <LogOut size={16} strokeWidth={2} />
          Sign out
        </button>
      </div>
    </div>
  )
}

/**
 * A row in the panel.
 *
 * One recipe — icon, label, the active treatment when the route underneath the
 * menu is already this one — so the rows cannot drift apart, and so the badge
 * appears on exactly the same place on every one of them.
 */
function PanelRow({ panel, icon, badge = 0, badgeLabel, onNavigate, children }) {
  const { panel: openPanel, toggle } = useSellerPanel()

  return (
    <MenuButton
      icon={icon}
      badge={badge}
      badgeLabel={badgeLabel}
      active={openPanel === panel}
      /*
        The panel is outside this menu, so the row names the region it opens:
        the id is derived from the panel's own id rather than passed, which is
        what lets the two agree without either component knowing the other. It is
        the same promise the bar's icons used to make.
      */
      controls={`seller-panel-${panel}`}
      onClick={() => {
        // The menu closes behind it: the panel opens beside the page, and a
        // dropdown left hanging over it would be a second layer for no reason.
        onNavigate?.()
        toggle(panel)
      }}
    >
      {children}
    </MenuButton>
  )
}

/**
 * The button half of a panel row.
 *
 * The pill is `CountBadge`, which owns the three decisions that have to be the
 * same in all four places a badge is drawn (zero, the `99+` cap, and the
 * screen-reader treatment). What a row supplies is the `label` — "unread
 * notifications" rather than just "3" — because the meaning of the number is the
 * one thing that differs between a row and the avatar above it.
 */
function MenuButton({
  icon: Icon,
  badge = 0,
  badgeLabel,
  active = false,
  controls,
  onClick,
  children,
}) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onClick}
      aria-expanded={active || undefined}
      aria-controls={controls}
      className={[
        'flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm transition-colors duration-200 ease-out-cubic',
        active
          ? 'bg-clay/10 font-medium text-clay-ink'
          : 'text-muted-strong hover:bg-subtle hover:text-ink',
      ].join(' ')}
    >
      <Icon size={16} strokeWidth={2} />
      <span className="min-w-0 flex-1 truncate">{children}</span>
      <CountBadge count={badge} label={badgeLabel} />
    </button>
  )
}

function MenuRow({ to, icon: Icon, badge = 0, badgeLabel, onNavigate, children }) {
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
      <CountBadge count={badge} label={badgeLabel} />
    </NavLink>
  )
}
