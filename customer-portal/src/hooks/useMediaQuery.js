import { useEffect, useState } from 'react'

/**
 * Whether the viewport currently matches a media query.
 *
 * The seller's panel has to be a docked column on a wide screen and an overlay
 * on a narrow one — two different pieces of markup, not one piece of markup with
 * two class sets. Rendering both and hiding one with CSS would mount the panel
 * twice, which means two message subscriptions, two queries under the same key
 * and two copies of a composer whose `id` has to be unique. So the answer is
 * read in JavaScript and only one of them exists.
 *
 * It starts at `false`: on a server there is no viewport, and "does not match"
 * is the honest answer — the overlay works at any width, so a first render that
 * guesses narrow is a first render that is never wrong, and the effect corrects
 * it before anyone could have acted on it. Same rule as the rest of this
 * portal's fail-open behaviour.
 */
export default function useMediaQuery(query) {
  const [matches, setMatches] = useState(false)

  useEffect(() => {
    // `?.` because `matchMedia` is not in every test environment, and a hook
    // that throws there would take a whole page down over a layout hint.
    const media = window.matchMedia?.(query)
    if (!media) return undefined

    const onChange = (event) => setMatches(event.matches)
    setMatches(media.matches)
    media.addEventListener('change', onChange)
    return () => media.removeEventListener('change', onChange)
  }, [query])

  return matches
}

/** The breakpoint the docked panel needs — Tailwind's `lg`. */
export const DOCKED_PANEL_QUERY = '(min-width: 1024px)'
