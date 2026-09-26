import { Navigate, Outlet, useLocation } from 'react-router-dom'

import { useAuth } from '../../hooks/useAuth.jsx'

/**
 * Gates the routes that need an account.
 *
 * The current path is handed to sign-in through router state so the customer
 * lands back where they were aiming. `replace` on the redirect keeps the
 * protected URL out of the history, so pressing back from sign-in does not
 * bounce them into the same gate.
 *
 * While the session is still being restored it renders a placeholder rather
 * than redirecting: redirecting on "not yet known" would throw a signed-in
 * customer onto the sign-in page every time they reload.
 */
export default function RequireAuth() {
  const { isSignedIn, loading } = useAuth()
  const location = useLocation()

  if (loading) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-24 sm:px-6">
        <div className="shimmer h-52 rounded-premium" />
      </div>
    )
  }

  if (!isSignedIn) {
    return (
      <Navigate to="/signin" state={{ from: location.pathname }} replace />
    )
  }

  return <Outlet />
}
