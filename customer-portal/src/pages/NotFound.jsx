import { Link } from 'react-router-dom'
import { Compass } from 'lucide-react'

import EmptyState from '../components/ui/EmptyState'

export default function NotFound() {
  return (
    <div className="mx-auto max-w-3xl px-4 py-24 sm:px-6">
      <EmptyState
        Icon={Compass}
        title="We could not find that page"
        description="The link may be out of date, or the product may have been retired by its maker."
        action={
          <Link to="/shop" className="btn btn-primary">
            Browse the catalog
          </Link>
        }
      />
    </div>
  )
}
