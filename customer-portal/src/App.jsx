import { lazy, Suspense } from 'react'
import { Route, Routes } from 'react-router-dom'

import RequireAuth from './components/auth/RequireAuth.jsx'
import RequireSeller from './components/seller/RequireSeller.jsx'
import SellerLayout from './components/seller/SellerLayout.jsx'
import AppLayout from './components/layout/AppLayout.jsx'
import RouteFallback from './components/ui/RouteFallback.jsx'
import Account from './pages/Account.jsx'
import AuthConfirm from './pages/AuthConfirm.jsx'
import Cart from './pages/Cart.jsx'
import Checkout from './pages/Checkout.jsx'
import GcashPay from './pages/GcashPay.jsx'
import Home from './pages/Home.jsx'
import MessageThread from './pages/MessageThread.jsx'
import Messages from './pages/Messages.jsx'
import NotFound from './pages/NotFound.jsx'
import Notifications from './pages/Notifications.jsx'
import OrderDetail from './pages/OrderDetail.jsx'
import Orders from './pages/Orders.jsx'
import ProductDetail from './pages/ProductDetail.jsx'
import Settings from './pages/Settings.jsx'
import SettingsAbout from './pages/SettingsAbout.jsx'
import SettingsAddresses from './pages/SettingsAddresses.jsx'
import SettingsFootSize from './pages/SettingsFootSize.jsx'
import SettingsSecurity from './pages/SettingsSecurity.jsx'
import Shop from './pages/Shop.jsx'
import SignIn from './pages/SignIn.jsx'
import SignUp from './pages/SignUp.jsx'
import StoreDetail from './pages/StoreDetail.jsx'
import Stores from './pages/Stores.jsx'

/**
 * The seller portal is the one part of this app that most visitors never load,
 * so it is the one part that is split out of the bundle.
 *
 * `lazy` rather than a second entry point: the seller shell is inside the same
 * router, uses the same auth context and the same Supabase client, and a second
 * HTML entry would make every one of those things a second copy. Splitting at
 * the component boundary keeps the shared code shared and still means a
 * shopper's first page load carries no seller code at all.
 *
 * Measured on the built output: the storefront's own chunk is unchanged and each
 * seller page arrives as its own 2–13 kB file, so `SellerProductForm` is not
 * downloaded by anyone who is not a seller.
 */
const SellerDashboard = lazy(() => import('./pages/seller/SellerDashboard.jsx'))
const SellerOrders = lazy(() => import('./pages/seller/SellerOrders.jsx'))
const SellerOrderDetail = lazy(
  () => import('./pages/seller/SellerOrderDetail.jsx'),
)
const SellerAccount = lazy(() => import('./pages/seller/SellerAccount.jsx'))
const SellerNotifications = lazy(
  () => import('./pages/seller/SellerNotifications.jsx'),
)
const SellerMessages = lazy(() => import('./pages/seller/SellerMessages.jsx'))
const SellerMessageThread = lazy(
  () => import('./pages/seller/SellerMessageThread.jsx'),
)
const SellerProducts = lazy(() => import('./pages/seller/SellerProducts.jsx'))
const SellerProductForm = lazy(
  () => import('./pages/seller/SellerProductForm.jsx'),
)
const SellerStore = lazy(() => import('./pages/seller/SellerStore.jsx'))
const SellerReports = lazy(() => import('./pages/seller/SellerReports.jsx'))

/**
 * Routes.
 *
 * Every customer-facing page sits inside `AppLayout`, which is what gives the
 * whole shop one header, one footer and one page transition. The paths are the
 * ones a customer would guess — `/makers/:id`, `/product/:id` — because these
 * URLs get pasted into messages and indexed by search engines; that is the
 * entire reason this portal is a React app rather than a canvas.
 *
 * `/cart` is behind `RequireAuth` because the cart genuinely lives on the
 * account: it is the app's `cart_items` table, scoped by `user_id`. There is no
 * guest cart to show, so asking for one would only produce an empty page.
 *
 * `/checkout/pay/:orderId` has its own URL rather than being a step inside
 * checkout because it is a state a customer comes back to on purpose — days
 * later, from a bookmark, to see whether the maker confirmed the payment. A URL
 * is what makes that possible.
 *
 * `/orders` and `/orders/:orderId` are behind `RequireAuth` for the same reason
 * the cart is, and they are the second half of that bookmark: paying creates an
 * order, and the customer needs somewhere to come back TO. The list and the
 * detail are separate routes rather than a modal over the list because an order
 * is the thing people link to — "here is my order" is a URL, not a click path.
 *
 * `/seller/*` is the seller portal. It is a SIBLING of the layout route, not a
 * child of it — see the block below for why that nesting is the whole point.
 */
export default function App() {
  return (
    <Routes>
      <Route element={<AppLayout />}>
        <Route index element={<Home />} />
        <Route path="shop" element={<Shop />} />
        <Route path="makers" element={<Stores />} />
        <Route path="makers/:storeId" element={<StoreDetail />} />
        <Route path="product/:productId" element={<ProductDetail />} />

        <Route path="signin" element={<SignIn />} />
        <Route path="signup" element={<SignUp />} />
        <Route path="auth/confirm" element={<AuthConfirm />} />

        <Route element={<RequireAuth />}>
          <Route path="account" element={<Account />} />
          {/*
            Settings and its sub-pages sit inside the same auth gate as the
            account page: every one of them reads or writes the customer's own
            row, and `RequireAuth` is what turns an anonymous visit into a
            sign-in prompt with a `from` to come back to.
          */}
          <Route path="settings" element={<Settings />} />
          <Route path="settings/security" element={<SettingsSecurity />} />
          <Route path="settings/foot-size" element={<SettingsFootSize />} />
          <Route path="settings/addresses" element={<SettingsAddresses />} />
          <Route path="settings/about" element={<SettingsAbout />} />
          <Route path="orders" element={<Orders />} />
          <Route path="orders/:orderId" element={<OrderDetail />} />
          {/*
            Notifications is behind the gate for the same reason orders is:
            every row is addressed to `auth.uid()` by the table's own RLS, so an
            anonymous visit has literally nothing to show — the sign-in prompt
            is the honest answer, not an empty feed.
          */}
          <Route path="notifications" element={<Notifications />} />
          {/*
            Messaging, and why there are two routes rather than a panel inside
            the inbox: a thread is a *place* — it is what a notification about a
            reply links to (`notificationDestination`), and what "here is my
            conversation with the maker" resolves to as a URL. The inbox at
            `/messages` is the list.

            Both are gated for the same reason notifications are: every row
            belongs to `auth.uid()` by the tables' own RLS, so an anonymous
            visitor has nothing to see and the sign-in prompt is the honest
            answer.
          */}
          <Route path="messages" element={<Messages />} />
          <Route path="messages/:conversationId" element={<MessageThread />} />
          <Route path="cart" element={<Cart />} />
          <Route path="checkout" element={<Checkout />} />
          <Route path="checkout/pay/:orderId" element={<GcashPay />} />
        </Route>

        <Route path="*" element={<NotFound />} />
      </Route>

      {/*
        The seller portal.

        Two gates and a shell of its own, and each is doing a different job:
        `RequireSeller` answers "may this account sell" (role AND an approved
        application — see the component), and `SellerLayout` answers "which
        storefront it is selling for".

        **It is a sibling of the layout route above, not a child of it, and that
        is the whole point.** `AppLayout` renders the storefront's sticky header,
        its page transition and its footer, so a seller route nested inside it
        would wear the shop's chrome above a workshop's tools — a search pill, a
        cart and a "Makers" link on a page about the seller's own orders.

        The paths are `/seller/...` rather than a second host so that one
        `npm run dev` serves both roles, which is the requirement this was built
        to: signing in as a seller lands on `/seller`, signing in as a customer
        lands on `/`, and both are the same app, the same session and the same
        deployment. `RequireSeller` is what makes that safe — the seller area is
        not a hidden set of pages, it is a gated one.

        `Suspense` wraps each page rather than the whole group, so the fallback
        replaces only the content area: a page-level boundary would blank the
        portal's navigation for the moment the chunk takes to arrive, which is
        the one part of the screen that never needs to load.
      */}
      <Route element={<RequireSeller />}>
        <Route path="seller" element={<SellerLayout />}>
          <Route
            index
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerDashboard />
              </Suspense>
            }
          />
          <Route
            path="orders"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerOrders />
              </Suspense>
            }
          />
          <Route
            path="orders/:orderId"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerOrderDetail />
              </Suspense>
            }
          />
          <Route
            path="products"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerProducts />
              </Suspense>
            }
          />
          {/* `new` before `:productId` so it is not read as a product id. */}
          <Route
            path="products/new"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerProductForm />
              </Suspense>
            }
          />
          <Route
            path="products/:productId"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerProductForm />
              </Suspense>
            }
          />
          {/*
            The seller's own notifications and messages.

            Two routes each have their own pages rather than reusing the
            customer's `/notifications` and `/messages`: those read
            `notifications.user_id` and `conversations.customer_id`, so a seller
            would be handed an empty feed over a table that was never going to
            answer — and `AppLayout` bounces a seller out of the shop anyway. The
            data behind these two is `seller_notifications.store_id` and
            `conversations.store_id`, which is the store, not the person.

            A thread is a *place*, exactly as it is on the customer's side: it
            is what a `new_message` notification links to, and what "here is my
            conversation with Ana" resolves to as a URL.
          */}
          <Route
            path="notifications"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerNotifications />
              </Suspense>
            }
          />
          <Route
            path="messages"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerMessages />
              </Suspense>
            }
          />
          <Route
            path="messages/:conversationId"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerMessageThread />
              </Suspense>
            }
          />
          <Route
            path="store"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerStore />
              </Suspense>
            }
          />
          <Route
            path="reports"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerReports />
              </Suspense>
            }
          />
          {/*
            The seller's own account. It lives under `/seller` rather than
            reusing `/settings` because `AppLayout` sends an approved seller out
            of the shop — including out of `/settings`, which is where the
            portal's only sign-out button used to be. This is that button's new
            home, along with the password form and the theme picker.
          */}
          <Route
            path="account"
            element={
              <Suspense fallback={<RouteFallback />}>
                <SellerAccount />
              </Suspense>
            }
          />

          {/*
            A seller URL that matches nothing keeps the seller shell, so a
            mistyped `/seller/orders2` lands inside the portal with its own bar
            rather than dropping the seller into the shop's 404. Two catch-alls
            is not a conflict here: React Router only ever considers the one
            inside the branch it already matched, and a single top-level `*`
            alongside `AppLayout`'s would be two routes with the same score,
            which is the ambiguous shape worth avoiding.
          */}
          <Route path="*" element={<NotFound />} />
        </Route>
      </Route>
    </Routes>
  )
}
