import { Component } from 'react'
import { Link } from 'react-router-dom'
import { AlertTriangle, RotateCcw } from 'lucide-react'

import EmptyState from './ui/EmptyState'

/**
 * The last line of defence against a blank screen.
 *
 * React unmounts the entire tree when a render throws, and the customer is left
 * looking at white with no idea whether the site is down, their connection
 * dropped, or the page just needs a reload. There is nothing to click and
 * nothing to read. This turns that into a sentence, a reason to reload, and a
 * way back to the catalog — which is the difference between "this shop is
 * broken" and "let me try again".
 *
 * It sits *inside* `AppLayout`, around the routed page only, so a page that
 * fails still leaves the header, the search box and the cart usable, and
 * `AppLayout` remounts it per `pathname` — navigating somewhere else clears the
 * error instead of pinning the customer to a broken page.
 *
 * A class component because there is still no hook equivalent of
 * `componentDidCatch`; that is a React limitation, not a style choice.
 */
export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props)
    this.state = { error: null }
    this.reset = this.reset.bind(this)
  }

  static getDerivedStateFromError(error) {
    return { error }
  }

  componentDidCatch(error, info) {
    // Surfaced in the console rather than swallowed: this is the one place the
    // real stack is still available, and its whole purpose is to be reported.
    console.error('A page failed to render:', error, info)
  }

  reset() {
    this.setState({ error: null })
  }

  render() {
    const { error } = this.state

    if (!error) return this.props.children

    return (
      <div className="mx-auto max-w-3xl px-4 py-16 sm:px-6 lg:px-8">
        <EmptyState
          Icon={AlertTriangle}
          title="This page did not load"
          description="Something went wrong while drawing this page. Reloading usually fixes it, and your cart and orders are safe either way."
          action={
            <div className="flex flex-wrap items-center justify-center gap-3">
              <button
                type="button"
                className="btn btn-primary"
                onClick={() => window.location.reload()}
              >
                <RotateCcw size={16} strokeWidth={2} />
                Reload the page
              </button>
              <Link to="/" className="btn btn-outline" onClick={this.reset}>
                Back to the catalog
              </Link>
            </div>
          }
        />
      </div>
    )
  }
}
