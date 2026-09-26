import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Outlet, useLocation, useNavigate } from 'react-router-dom'

import ErrorBoundary from '../ErrorBoundary'
import PageTransition from '../motion/PageTransition'
import SellerHeader from './SellerHeader.jsx'
import SellerPanelContent from './SellerPanels.jsx'
import SellerSidePanel from './SellerSidePanel.jsx'
import { useAuth } from '../../hooks/useAuth.jsx'
import { useMyStore } from '../../hooks/useSeller.js'
import { SellerPanelProvider, useSellerPanel } from '../../hooks/useSellerPanel.jsx'
import { sellerPanelPage, sellerPanelTitle } from '../../lib/sellerPanelRules.js'
import { subscribeToSellerNotifications } from '../../lib/sellerNotifications.js'
import { subscribeToStoreInbox } from '../../lib/sellerMessages.js'
import { supabase } from '../../lib/supabase.js'

/**
 * The seller portal's shell.
 *
 * A top bar, not a sidebar. The sidebar was a bad fit for two reasons that
 * outlived its looks: this is the same site as the shop — the seller signed in
 * through the same door, and the customer who becomes a seller should recognise
 * the furniture rather than walk into a different-looking product — and a 240px
 * rail on the left of every page is 240px of a workbench given up to navigation
 * that fits in a row. `SellerHeader` carries the bar and the reasoning behind it.
 *
 * Five things the shell owns:
 *
 *  1. **The store query.** It is here so the bar, the guard, every page *and the
 *     side panel* read the same row. A component asking for the store itself
 *     would be a second request for the same answer, and the guard below could
 *     not exist at all.
 *  2. **The store guard.** An approved seller with no store row has nothing any
 *     page could show, and `undefined` while loading is not `null`: a pending
 *     query must not be read as "this seller has no store".
 *  3. **The panel's state**, through `SellerPanelProvider`, for the same reason
 *     the store is here: a pinned panel has to survive a route change, and the
 *     row that opens it lives in the bar while the panel is drawn here — so
 *     neither is the other's child, and neither is a child of the open route.
 *  4. **The realtime subscriptions.** See `SellerRealtime` below.
 *  5. **Sign out**, handed to the bar's account menu so it is reachable from every
 *     screen — one click inside the avatar, which is a bar control and so is on
 *     every page. It is also on `/seller/account`, and that is not duplication
 *     for its own sake: "I am done, get me off this machine" is a thing that
 *     happens at the machine, not after navigating to a settings page. The bar
 *     owns the click and the shell owns the navigation, which is why the menu
 *     takes the handler rather than calling `signOut` itself.
 *
 * There is no "Back to the shop" link, and its absence is deliberate. There used
 * to be one, and it is gone because the shop is closed to sellers — `AppLayout`
 * redirects an approved seller straight back here, so a link to it is a control
 * that bounces. The way out is Sign out.
 */
export default function SellerLayout() {
  const location = useLocation()
  const navigate = useNavigate()
  const { signOut } = useAuth()
  const { data: store, isLoading } = useMyStore()

  const storeName = store?.name?.trim() || 'Your workshop'
  const storeId = store?.id ?? null

  const onSignOut = async () => {
    await signOut()
    navigate('/', { replace: true })
  }

  return (
    <SellerPanelProvider>
      <div className="flex min-h-dvh flex-col bg-page">
        <SellerHeader storeName={storeName} storeId={storeId} onSignOut={onSignOut} />

        <SellerRealtime storeId={storeId} />

        {/*
          The docked panel is a flex sibling of `<main>`, not a layer over it, so
          a pinned panel narrows the page instead of covering it. That is the
          whole difference the pin buys: orders on the left, the inbox on the
          right, both readable.
        */}
        <div className="flex min-w-0 flex-1">
          <main className="min-w-0 flex-1">
            {/*
              Both keys are the pathname, deliberately: a page that threw keeps
              its error boundary until the seller actually goes somewhere else,
              and the transition replays per route rather than per render.
            */}
            <PageTransition key={location.pathname}>
              <ErrorBoundary key={location.pathname}>
                {!isLoading && store === null ? (
                  <NoStoreNotice />
                ) : (
                  <Outlet context={{ store }} />
                )}
              </ErrorBoundary>
            </PageTransition>
          </main>

          <SellerPanel storeId={storeId} />
        </div>
      </div>
    </SellerPanelProvider>
  )
}

/**
 * The panel, in whichever of its two forms the state calls for.
 *
 * Nothing is rendered when no panel is open — not a hidden one. A closed panel
 * that is still mounted is a list of notifications still subscribed, still
 * querying and still taking clicks from behind the page, which is the same
 * mistake the account menu documents for its own panel.
 */
function SellerPanel({ storeId }) {
  const {
    panel,
    pinned,
    docked,
    expanded,
    panelWidth,
    maxRem,
    close,
    togglePin,
    toggleExpand,
    setWidth,
  } = useSellerPanel()
  if (!panel) return null

  return (
    <SellerSidePanel
      panelId={panel}
      title={sellerPanelTitle(panel)}
      page={sellerPanelPage(panel)}
      docked={docked}
      pinned={pinned}
      expanded={expanded}
      /* The drawn width, not the stored one: the provider has already applied
         the window's ceiling to it — see `appliedPanelWidth`. */
      width={panelWidth}
      maxRem={maxRem}
      onResize={setWidth}
      onClose={close}
      onTogglePin={togglePin}
      onToggleExpand={toggleExpand}
    >
      <SellerPanelContent panel={panel} storeId={storeId} />
    </SellerSidePanel>
  )
}

/**
 * The portal's realtime channels, in the one component that is always mounted.
 *
 * Both tables are in the `supabase_realtime` publication, so these fire — unlike
 * the customer's `notifications`, which was never published and which is why
 * that feed refetches on focus instead of subscribing. A subscription to an
 * unpublished table silently never fires, and a feed that only *looks* live is
 * worse than one that admits it polls.
 *
 * ## Why here, and not in the badge hooks
 *
 * Because three surfaces draw the same two numbers: the account menu's rows, the
 * panel's own lists, and the badges inside both. A subscription inside a hook
 * that all three use would be three channels invalidating the same two keys —
 * and with the panel open on a pinned screen, all three really are mounted at
 * once.
 *
 * The shell is the single component guaranteed to be on every seller page, so
 * this is where the sockets belong. Each channel is removed on unmount, which is
 * also what keeps `StrictMode`'s double mount (effect → cleanup → effect) from
 * leaving a duplicate behind.
 */
function SellerRealtime({ storeId }) {
  const queryClient = useQueryClient()

  useEffect(() => {
    if (!storeId) return undefined

    /* Each event means one thing here: "these keys are stale now". Both halves
       of a pair are always refreshed together, so a badge cannot end up
       disagreeing with the list it badges. */
    const refresh = (keys) => () => {
      for (const key of keys) queryClient.invalidateQueries({ queryKey: [key, storeId] })
    }

    const channels = [
      subscribeToSellerNotifications(
        storeId,
        refresh(['seller-notifications', 'seller-notifications-unread']),
      ),
      subscribeToStoreInbox(
        storeId,
        refresh(['seller-conversations', 'seller-conversations-unread']),
      ),
    ]

    return () => {
      for (const channel of channels) {
        if (channel) supabase.removeChannel(channel)
      }
    }
  }, [storeId, queryClient])

  return null
}

/**
 * An approved seller with no store row.
 *
 * The app creates a store in `CreateStoreScreen`, which the portal does not
 * have, so this points at the app rather than pretending. Building a second
 * store-creation flow in the browser would need the location picker, the tier-1
 * application data and the store-front upload that the phone already holds —
 * and a half-built one that produces a store with no location is worse than
 * none.
 *
 * The padding is `SellerPageBody`'s, not this component's own: the notice is a
 * page, and a page that inset itself differently from every other seller page
 * would show the bar's left edge and the card's left edge disagreeing.
 */
function NoStoreNotice() {
  return (
    <div className="px-4 py-16 sm:px-6 lg:px-8 lg:py-24">
      <div className="mx-auto max-w-7xl">
        <div className="max-w-2xl rounded-premium border border-hairline bg-raised p-8 shadow-premium">
          <h1 className="font-display text-2xl font-semibold text-ink">
            Set up your storefront first
          </h1>
          <p className="mt-3 text-sm leading-relaxed text-muted">
            Your seller account is approved, but it does not have a store yet.
            Creating one needs your workshop&rsquo;s location and storefront
            photo, so it is done in the CUFMAI app.
          </p>
          <p className="mt-3 text-sm leading-relaxed text-muted">
            Open the app, finish the store set-up, and every page here will fill
            in from the same row.
          </p>
        </div>
      </div>
    </div>
  )
}
