import { Link } from 'react-router-dom'
import { motion } from 'motion/react'
import { ArrowUpRight, MapPin, Package, Star } from 'lucide-react'

import StoreBanner from '../ui/StoreBanner'
import { fadeUp, staggerChildren } from '../motion/transitions'
import { storeColor } from '../../lib/constants'
import { storeFacts } from '../../lib/storeIndexRules'

/**
 * The makers gallery — a port of Lightswind UI's `SeasonalHoverCards`.
 *
 * The published component is a row of full-bleed photo panels that sit at a
 * third of the width and *grow to two thirds on hover*, with the description
 * held back until then: the picture is the invitation, the words arrive when
 * the customer shows interest.
 *
 * That is a better fit for this page than the card it replaces, and it is the
 * same argument the existing card was built on, taken further. The makers page
 * exists because the artisan is the differentiator, and a workshop's own
 * storefront photograph (`stores.banner_url`) says that in one glance — which is
 * why it is the panel now rather than a 112px band above a product window.
 *
 * Three departures from the published source, all marked where they appear:
 *
 *  1. **The panel is a link, not a div.** Every maker card has always been one
 *     link to `/makers/:id`, and a gallery of photo panels that does not go
 *     anywhere is a slideshow.
 *  2. **Keyboard focus gets the same reveal as the mouse.** Two mechanisms,
 *     because the two elements are different: `md:has-[:focus-visible]:w-2/3`
 *     for the panel's own width (the `li` is what grows, and `:has()` is how a
 *     non-focusable ancestor asks about a descendant), and
 *     `group-has-[:focus-visible]:` for the description and the zoom.
 *     `group-focus-visible:` is the wrong tool here and was tried first: it
 *     compiles to `.group:focus-visible …`, which asks whether the *panel* is
 *     focused — and a `li` never is, so the description stayed mouse-only while
 *     the panel grew. `has(:focus-visible)` is true when anything inside is.
 *  3. **The description is visible below `md`.** A touch screen has no hover, so
 *     the published reveal would hide the description on every phone — the words
 *     are held back only where there is a pointer that can ask for them.
 *
 * The scrim is the one raw black in the portal, on purpose: it sits over a
 * photograph, and every ink token in `index.css` flips with the theme — a scrim
 * that turned white in dark mode would be wallpaper, not a scrim.
 */
export function SeasonalStoreCards({ stores, index, className = '' }) {
  return (
    <motion.ul
      variants={staggerChildren(0.06)}
      initial="hidden"
      animate="show"
      /* `flex-wrap md:flex-nowrap` is the published pair, and the wrap is not
         decoration: below `md` the panels are full width, so they are one per
         line either way. Above `md` it must be `nowrap` — with wrapping still
         on, the browser breaks the line using each panel's *hypothetical*
         width, so a hovered panel at two thirds pushes the third panel onto a
         second row instead of squeezing its neighbours, which reflows the page
         on every hover. */
      className={`flex flex-wrap gap-5 md:flex-nowrap ${className}`}
    >
      {stores.map((store) => (
        <motion.li
          key={store.id}
          variants={fadeUp}
          /* The group, the panel, and the thing that grows: `group` has to be
             the element whose width changes, because `group-hover` only reaches
             descendants of it. */
          className="group relative flex h-[350px] w-full overflow-hidden rounded-card shadow-card transition-[width] duration-500 ease-out-cubic md:w-1/3 md:hover:w-2/3 md:has-[:focus-visible]:w-2/3 lg:h-[450px]"
        >
          <SeasonalStoreCard
            store={store}
            count={index?.counts?.[String(store.id)] ?? 0}
          />
        </motion.li>
      ))}
    </motion.ul>
  )
}

/** How a fact is drawn — the icon for each of `storeFacts`' kinds. */
const FACT_ICONS = {
  rating: Star,
  pairs: Package,
  location: MapPin,
}

/**
 * One maker, as a photograph.
 *
 * `StoreBanner` rather than an `<img>`: it carries the app's fallback rules
 * (`storeBannerRules.js`) — a store with no banner, or one whose URL fails to
 * load, gets its brand gradient instead of a hole, which matters far more on a
 * 450px panel than it did on a 112px band.
 *
 * `alt=""` throughout is the same reasoning as before: the panel is one link,
 * and the link's text is its label.
 */
function SeasonalStoreCard({ store, count }) {
  const color = storeColor(store)
  const facts = storeFacts(store, count)

  return (
    <>
      {/* The storefront, with the store's colour behind it. */}
      <div className="absolute inset-0 transition-transform duration-500 ease-out-cubic md:group-hover:scale-105 md:group-has-[:focus-visible]:scale-105">
        <StoreBanner store={store} className="h-full" />
      </div>

      <span aria-hidden="true" className="absolute inset-0 bg-black/55" />

      {/* The store's colour as a rule across the top — the one piece of the old
          card worth keeping on a photograph, and the only thing that ties a
          banner-less store and a photographed one to the same brand. */}
      <span
        aria-hidden="true"
        style={{ backgroundColor: color }}
        className="absolute inset-x-0 top-0 z-20 h-1 opacity-80"
      />

      <Link
        to={`/makers/${store.id}`}
        className="absolute inset-0 z-10 flex flex-col justify-end gap-3 p-6"
      >
        <span className="space-y-1">
          <h2 className="font-display text-xl font-semibold text-ink-inverse lg:text-2xl">
            {store.name}
          </h2>
          {store.tagline && (
            <span className="block text-sm text-ink-inverse/75">{store.tagline}</span>
          )}
        </span>

        {/* Reserved space, not hidden content: `opacity-0` keeps its height, so
            the panel does not reflow when the words arrive. */}
        {store.description && (
          <span className="line-clamp-3 text-sm leading-relaxed text-ink-inverse/85 md:translate-y-6 md:opacity-0 md:transition-[opacity,transform] md:duration-500 md:ease-out-cubic md:group-hover:translate-y-0 md:group-hover:opacity-100 md:group-has-[:focus-visible]:translate-y-0 md:group-has-[:focus-visible]:opacity-100">
            {store.description}
          </span>
        )}

        <span className="flex items-center gap-3 border-t border-ink-inverse/15 pt-3">
          <span className="flex min-w-0 flex-wrap items-center gap-x-2.5 gap-y-1 text-xs text-ink-inverse/70">
            {facts.map((fact, factIndex) => {
              const Icon = FACT_ICONS[fact.kind]
              return (
                <span key={fact.kind} className="inline-flex items-center gap-1.5">
                  {factIndex > 0 && (
                    <span aria-hidden="true" className="text-ink-inverse/25">
                      ·
                    </span>
                  )}
                  <Icon
                    size={13}
                    strokeWidth={2}
                    /* The one fact worth a colour: a rating is someone's
                       opinion, not a label, and it is absent until there is
                       one (see `storeFacts`). */
                    className={`shrink-0 ${
                      fact.kind === 'rating' ? 'text-amber' : 'text-ink-inverse/70'
                    }`}
                    {...(fact.kind === 'rating' ? { fill: 'currentColor' } : {})}
                  />
                  <span
                    className={
                      fact.kind === 'rating' ? 'num font-semibold text-ink-inverse' : ''
                    }
                  >
                    {fact.label}
                  </span>
                </span>
              )
            })}
          </span>

          <span className="ml-auto inline-flex shrink-0 items-center gap-1 text-xs font-semibold text-ink-inverse">
            Visit store
            <ArrowUpRight
              size={13}
              strokeWidth={2.5}
              className="transition-transform duration-300 ease-out-cubic md:group-hover:-translate-y-0.5 md:group-hover:translate-x-0.5"
            />
          </span>
        </span>
      </Link>
    </>
  )
}
