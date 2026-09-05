import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth.jsx'
import { needsMfa } from '../../lib/mfa'

export default function ProtectedRoute() {
  const { session, loading, isAdmin } = useAuth()

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-surface">
        <div className="h-10 w-10 animate-spin rounded-full border-4 border-primary border-t-transparent" />
      </div>
    )
  }

  if (!session || !isAdmin) {
    return <Navigate to="/login" replace />
  }

  // Admins with MFA enrolled must complete the code step before any
  // portal page renders.
  if (needsMfa(session)) {
    return <Navigate to="/mfa-verify" replace />
  }

  return <Outlet />
}
