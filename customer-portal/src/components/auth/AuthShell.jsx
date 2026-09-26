import { Link } from 'react-router-dom'
import { ArrowRight, Check } from 'lucide-react'

import Reveal from '../ui/Reveal'

const ASSURANCES = [
  'Sold and shipped directly by CUFMAI member artisans',
  'All prices in Philippine Peso (₱)',
  'Delivery arranged, or pick up in Carcar City',
]

/**
 * The frame around sign-in and sign-up.
 *
 * Shared so the two forms cannot drift apart — they are the same interaction
 * twice, and a customer moving between them should not have to re-learn the
 * layout. The left panel carries the association's story because that is the
 * one thing a customer should know before handing over an e-mail address.
 *
 * The card is three bands rather than one padded box: a header (who this is and
 * what the form does), the form, and a footer. Each band is separated by a
 * hairline, which is what lets the footer sit on a tinted ground and read as a
 * footnote to the form instead of as the last field in it. The bands also do
 * the work the old `mt-*` stack was doing by hand, so a page whose form is
 * three fields long and one whose form is nine both line up on the same edges.
 *
 * `overflow-hidden` is what lets the footer band be drawn square: the corner
 * radius lives on the card and clips it. Nothing inside the card overflows
 * (there are no menus or popovers in a form), and the focus rings sit at least
 * 4px inside the padding, so none of it is clipped.
 *
 * `26rem` is the card's width and it is one value for both pages: sign-in and
 * sign-up are the same card two screens apart, and a customer who moves between
 * them should not see the frame jump — the form inside changes length, the card
 * does not change size around it. The width was widened once to 32rem and
 * brought back; the measure the story panel and the fields were both written
 * for is this one, and going wider only bought the card a longer line of empty
 * input to read across.
 */
export default function AuthShell({ title, subtitle, children, footer }) {
  return (
    <div className="mx-auto grid max-w-7xl gap-10 px-4 py-14 sm:px-6 lg:grid-cols-[1fr_26rem] lg:items-center lg:gap-16 lg:px-8 lg:py-20">
      <Reveal className="order-2 lg:order-1">
        <p className="overline">Carcar City, Cebu · Est. 2004</p>
        <h2 className="mt-3 max-w-lg font-display text-3xl font-semibold leading-tight text-ink sm:text-4xl">
          One account, whichever device you shop on.
        </h2>
        <p className="mt-5 max-w-lg text-sm leading-relaxed text-muted">
          Your cart and your orders belong to the account, not to the browser —
          so a pair you add here on the web is waiting in the CUFMAI app on your
          phone, and the other way round.
        </p>

        {/*
          A titled chip rather than a 1.5px dot. The dot was small enough that
          three lines of grey copy and three bullet marks read as one grey
          block; a tinted mark per line gives the eye somewhere to land without
          turning a reassurance list into a checklist with boxes to tick.
        */}
        <ul className="mt-8 max-w-lg space-y-3.5 text-sm text-muted-strong">
          {ASSURANCES.map((line) => (
            <li key={line} className="flex items-start gap-3">
              <span
                aria-hidden="true"
                className="mt-0.5 flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full bg-clay/10 text-clay-ink"
              >
                <Check className="h-3 w-3" strokeWidth={3} />
              </span>
              <span className="leading-snug">{line}</span>
            </li>
          ))}
        </ul>

        <Link
          to="/shop"
          className="group mt-8 inline-flex items-center gap-1.5 text-sm font-semibold text-clay-ink underline-offset-4 hover:underline"
        >
          Keep browsing without an account
          <ArrowRight
            className="h-4 w-4 transition-transform duration-200 ease-out-cubic group-hover:translate-x-0.5"
            aria-hidden="true"
          />
        </Link>
      </Reveal>

      <div className="order-1 lg:order-2">
        <div className="overflow-hidden rounded-premium border border-hairline bg-raised shadow-premium">
          <div className="p-6 sm:p-8">
            <Link
              to="/"
              className="inline-flex items-center gap-2.5"
              aria-label="CUFMAI — home"
            >
              <img src="/logo.svg" alt="" className="h-8 w-8 dark:hidden" />
              <img src="/logo-dark.svg" alt="" className="hidden h-8 w-8 dark:block" />
              <span className="font-display text-base font-semibold tracking-tight text-ink">
                CUFMAI
              </span>
            </Link>

            <h1 className="mt-6 font-display text-[1.75rem] font-semibold leading-snug text-ink">
              {title}
            </h1>
            {subtitle && (
              <p className="mt-1.5 text-sm leading-relaxed text-muted">{subtitle}</p>
            )}
          </div>

          <div className="border-t border-hairline-soft p-6 sm:p-8">{children}</div>

          {footer && (
            <div className="border-t border-hairline-soft bg-subtle/60 px-6 py-4 text-sm text-muted sm:px-8">
              {footer}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
