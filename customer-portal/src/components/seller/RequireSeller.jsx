import { Link, Navigate, Outlet, useLocation } from 'react-router-dom'
import { Clock, Hammer, ShieldAlert } from 'lucide-react'

import { SELLER_ACCESS, sellerAccess } from '../../lib/sellerRules.js'
import { useAuth } from '../../hooks/useAuth.jsx'

/**
 * Gates every `/seller` route.
 *
 * Two gates, not one, and the second is the one that is easy to forget:
 *
 *   1. **Signed in.** Anything less lands on sign-in with a `from` to come back
 *      to, exactly as `RequireAuth` does.
 *   2. **An approved seller.** `auth_gate.dart` decides the app's shells in this
 *      order — admin, then seller-with-`seller_status = 'approved'`, then a
 *      pending applicant, then a customer — and the order is load-bearing:
 *      `role = 'seller'` alone is not permission to sell. A seller row with
 *      `seller_status = 'pending'` has applied and has not been approved, and
 *      showing them a dashboard full of zeroes would read as a broken account
 *      rather than an unfinished application.
 *
 * A pending or rejected applicant gets a page rather than a redirect, because
 * they are in the right place and are waiting on someone else. A customer — or
 * an admin, who has their own portal — is sent to the storefront: there is no
 * seller page that could tell them anything true.
 *
 * While the session is still being restored it renders a placeholder rather than
 * deciding, for the reason `RequireAuth` gives: redirecting on "not yet known"
 * throws a signed-in seller out of their own portal on every reload.
 */
export default function RequireSeller() {
  const { isSignedIn, loading, profile } = useAuth()
  const location = useLocation()

  if (loading) {
    return (
      <div className="mx-auto max-w-5xl px-4 py-24 sm:px-6 lg:px-8">
        <div className="shimmer h-64 rounded-premium" />
      </div>
    )
  }

  if (!isSignedIn) {
    return <Navigate to="/signin" state={{ from: location.pathname }} replace />
  }

  const access = sellerAccess(profile)

  if (access === SELLER_ACCESS.PENDING) {
    return (
      <ApplicationNotice
        icon={Clock}
        tone="amber"
        title="Your seller application is being reviewed"
        body="An admin is looking at your application. You will be able to list products and take orders here as soon as it is approved — the CUFMAI app will let you know when that happens."
      />
    )
  }

  if (access === SELLER_ACCESS.REJECTED) {
    return (
      <ApplicationNotice
        icon={ShieldAlert}
        tone="crimson"
        title="Your seller application was not approved"
        body="This account cannot sell on CUFMAI. If you think that is a mistake, contact the association — they can look at the application with you."
      />
    )
  }

  if (access !== SELLER_ACCESS.APPROVED) {
    return <Navigate to="/" replace />
  }

  return <Outlet />
}

/**
 * The waiting and refused screens.
 *
 * Not the seller shell — there is no navigation a seller cannot use yet, and a
 * bar of disabled links would be a worse answer than one honest paragraph. The
 * way out is the storefront, which this account genuinely can use.
 */
function ApplicationNotice({ icon: Icon, tone, title, body }) {
  const tones = {
    amber: 'bg-amber/10 text-amber',
    crimson: 'bg-crimson/10 text-crimson',
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-20 sm:px-6 lg:px-8">
      <div className="rounded-premium border border-hairline bg-raised p-8 shadow-premium">
        <span
          aria-hidden="true"
          className={`flex h-11 w-11 items-center justify-center rounded-full ${tones[tone]}`}
        >
          <Icon className="h-5 w-5" />
        </span>
        <h1 className="mt-5 font-display text-2xl font-semibold text-ink">
          {title}
        </h1>
        <p className="mt-3 text-sm leading-relaxed text-muted">{body}</p>

        <div className="mt-7 flex flex-wrap gap-3">
          <Link to="/" className="btn btn-primary">
            <Hammer className="h-4 w-4" aria-hidden="true" />
            Back to the storefront
          </Link>
          <Link to="/settings" className="btn btn-outline">
            Account settings
          </Link>
        </div>
      </div>
    </div>
  )
}
