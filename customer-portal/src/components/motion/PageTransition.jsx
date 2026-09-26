import { useEffect } from 'react'

import { useTransitionTiming } from './transitions'

/**
 * The wrapper each route's page sits in, so navigating between pages is a
 * transition rather than a cut.
 *
 * The movement is small (10px) and fast (260ms) on purpose. A large or slow page
 * slide is the single most common way a "premium" web app ends up feeling
 * *slower* than a plain one: the customer waits for furniture to move before
 * they can read. The job here is only to make the new page feel continuous with
 * the old one.
 *
 * ## Why this is a CSS animation now
 *
 * It used to be an `AnimatePresence mode="wait"` pair: an exit, and then an
 * entrance once the exit finished. That version could leave the site showing a
 * blank page — literally empty `<main>`, header still there — and it did, in
 * Chrome, on ordinary navigation. The content was in the DOM the whole time,
 * at `opacity: 0`, because the incoming page's visibility depended on a
 * JavaScript animation getting a frame loop and finishing. Anything that
 * stopped that loop stranded the page permanently: a background tab, a
 * navigation that interrupts the previous exit, a dev-server reload mid-flight.
 *
 * Two changes remove the whole class of failure:
 *
 *  1. **No exit, so nothing gates the incoming page.** An entrance (`AppLayout`
 *     remounts this on `pathname`) plus no exit gives the same felt result —
 *     each page arrives with a small rise and fade — without ever holding the
 *     new page back while the old one leaves.
 *  2. **The animation is CSS, and its end state is the element's natural one.**
 *     There is no inline `opacity: 0` to get stuck on, so the failure mode of a
 *     missing animation is a page that appears instantly rather than a page
 *     that does not appear.
 *
 * `prefers-reduced-motion` is handled by the media query in `index.css`, which
 * collapses the duration to nothing.
 *
 * It also owns the scroll reset, because it mounts at exactly the moment the
 * new page appears: `AppLayout` renders this once per `pathname`, so an effect
 * with no dependencies is "this page has just arrived".
 */
export default function PageTransition({ children }) {
  const { reduce } = useTransitionTiming()

  useEffect(() => {
    // `behavior: 'instant'` explicitly, rather than relying on the default:
    // any inherited `scroll-behavior: smooth` would turn arriving on a new page
    // into a long scroll from wherever the last one ended.
    window.scrollTo({ top: 0, left: 0, behavior: reduce ? 'auto' : 'instant' })
  }, [reduce])

  return <div className="page-enter">{children}</div>
}
