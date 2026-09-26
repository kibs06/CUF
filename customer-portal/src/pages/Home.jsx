import { Link } from 'react-router-dom'
import { ArrowRight, Clock } from 'lucide-react'

import ProductGrid from '../components/product/ProductGrid'
import Reveal from '../components/ui/Reveal'
import { ProductGridSkeleton } from '../components/ui/Skeleton'
import StoreAvatar from '../components/ui/StoreAvatar'
import { useProducts, useStores } from '../hooks/useCatalog'
import { useMySize } from '../hooks/useMySize.js'
import { ASSOCIATION_INTRO, pluralize, storeColor } from '../lib/constants'
import { euSizeLabel, euSizeValue, productsInMySize } from '../lib/sizeMatchRules'
import {
  earliestSaleEnd,
  isOnSale,
  maxDiscountPercent,
  salePercent,} from '../lib/pricing'

/**
 * The storefront home.
 *
 * Everything on it is derived from the live catalog — the discount figure, the
 * counts, the expiry, the makers. Nothing is a hard-coded marketing number, so
 * the page cannot end up claiming "up to 50% off" a week after the sale ended.
 * That is the same rule the app applies to its On Sale poster
 * (`maxDiscountPercent` reads the loaded catalog rather than a stored value).
 *
 * It is also the first surface that makes the foot profile do something while
 * shopping. The stored size used to be write-only — the Settings page collected
 * it and no page read it — so the catalog could not answer the one question a
 * shopper actually has: *which of these come in my size?* The shelf below does,
 * with the app's own match rule (`sizeMatchRules.js`), and it renders nothing at
 * all when there is no size on file or nothing matches it.
 */
export default function Home() {
  const productsQuery = useProducts()
  const storesQuery = useStores()

  const products = productsQuery.data ?? []
  const stores = storesQuery.data ?? []
  const bestDiscount = maxDiscountPercent(products)
  const featured = products.slice(0, 8)
  const makers = stores.slice(0, 3)

  /*
    Everything the sale band says is computed here, once. Note the arrow
    functions: `isOnSale(product, now)` takes a second argument, so passing the
    function reference straight to `filter` would hand it the array INDEX as
    `now` and throw on `now.getTime()`.
  */
  const onSale = products.filter((product) => isOnSale(product))
  const onSaleMakers = new Set(onSale.map((product) => product.store_id)).size
  const saleEnds = earliestSaleEnd(products)
  // The three deepest cuts, so the band illustrates its claim instead of only
  // asserting it. Sorted by the same percent the tiles badge.
  const deepestDeals = [...onSale]
    .sort((a, b) => (salePercent(b) ?? 0) - (salePercent(a) ?? 0))
    .slice(0, 3)

  /*
    "My size" — null for a signed-out visitor and for a customer who never gave
    a size, and then `productsInMySize` is empty and the shelf does not render.

    The shelf is filtered from the catalog that is ALREADY loaded, so this costs
    no request, and it follows the same rule as every other size-aware surface:
    an exact size with stock behind it, read from `inventory`. A product whose
    size is sold out, or whose nearest size is half a size away, is not "in your
    size" and must not be here.

    Capped at eight — the same as the collection above. The cap itself is the
    app's own reasoning (plan §6 P3: the shelf is a taste and `See all` is the
    door to the rest), and eight rather than ten is what keeps it two full rows
    of that collection's grid at `xl` instead of a row with a stump on the end.
  */
  const mySize = useMySize()
  const inMySize = productsInMySize(products, mySize).slice(0, 8)

  const isLoading = productsQuery.isLoading || storesQuery.isLoading
  const hasError = productsQuery.isError || storesQuery.isError

  return (
    <>
      {/* ── Hero ───────────────────────────────────────────────── */}
      <section className="relative overflow-hidden bg-chrome">
        {/*
          Two soft radial washes rather than a photograph: a real hero image
          would need a product shot the association owns, and a stock one would
          misrepresent the craft. The clay glow is the brand colour doing the
          work instead.
        */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0"
          style={{
            background:
              'radial-gradient(58% 72% at 12% 18%, rgba(139,90,43,0.55) 0%, rgba(139,90,43,0) 62%), radial-gradient(48% 58% at 88% 82%, rgba(78,205,196,0.16) 0%, rgba(78,205,196,0) 66%)',
          }}
        />

        <div className="relative mx-auto max-w-7xl px-4 py-20 sm:px-6 sm:py-28 lg:px-8 lg:py-32">
          <div className="max-w-2xl">
            <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-celadon">
              Carcar City, Cebu · Est. 2004
            </p>
            <h1 className="mt-5 font-display text-[2.5rem] font-semibold leading-[1.06] text-white sm:text-5xl lg:text-[3.75rem]">
              Handcrafted footwear, direct from the makers.
            </h1>
            <p className="mt-6 max-w-xl text-base leading-relaxed text-white/70">
              Carcar has been the footwear capital of the south for
              generations. Every pair here is made by a CUFMAI member artisan —
              hand-welted soles, full-grain leather, and a craft passed down
              rather than taught.
            </p>

            <div className="mt-9 flex flex-wrap gap-3">
              <Link to="/shop" className="btn btn-primary">
                Shop the catalog
                <ArrowRight size={16} strokeWidth={2.5} />
              </Link>
              <Link to="/makers" className="btn btn-ghost">
                Meet the makers
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* ── On sale ───────────────────────────────────────────────
          Pulled up over the hero's foot, and FULL BLEED — outside the 7xl
          container the rest of the page sits in. Both halves of that are the
          point: it overlaps ground the hero already occupies, so it costs no
          extra height, and a brand ribbon running to both edges reads as the
          storefront's own footing where the 7xl card it replaced read as one
          more panel on a page of panels. `relative z-10` lives on the Reveal
          wrapper because the fade-in gives it a stacking context; without it
          the ribbon would paint underneath the hero for the length of the
          animation. */}
      {bestDiscount !== null && (
        <Reveal className="relative z-10 -mt-6 sm:-mt-12 lg:-mt-14">
          <OnSaleBand
            discount={bestDiscount}
            productCount={onSale.length}
            makerCount={onSaleMakers}
            endsAt={saleEnds ? shortDay(saleEnds) : null}
            thumbs={deepestDeals}
          />
        </Reveal>
      )}

      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        {/* ── Catalog ───────────────────────────────────────────── */}
        <section className="pt-16">
          <div className="flex items-end justify-between gap-6">
            <div>
              <p className="overline">The Workshop Collection</p>
              <h2 className="mt-2 font-display text-2xl font-semibold text-ink sm:text-3xl">
                Fresh from the bench
              </h2>
            </div>
            <Link
              to="/shop"
              className="group hidden shrink-0 items-center gap-1.5 text-sm font-semibold text-clay-ink sm:inline-flex"
            >
              Browse all
              <ArrowRight
                size={15}
                strokeWidth={2.5}
                className="transition-transform duration-300 ease-out-cubic group-hover:translate-x-1"
              />
            </Link>
          </div>

          <div className="mt-8">
            {isLoading ? (
              <ProductGridSkeleton count={8} />
            ) : hasError ? (
              <RequestFailed />
            ) : featured.length > 0 ? (
              <ProductGrid products={featured} />
            ) : (
              <p className="rounded-card border border-hairline bg-subtle/60 px-6 py-12 text-center text-sm text-muted">
                No products are available right now. Check back shortly.
              </p>
            )}
          </div>

          <div className="mt-8 sm:hidden">
            <Link to="/shop" className="btn btn-outline w-full">
              Browse all products
            </Link>
          </div>
        </section>

        {/* ── In your size ─────────────────────────────────────────
            Sits between the catalog and the makers, because it is a shelf OF
            the catalog rather than a separate thing to explain. The heading
            names the size the shelf was built on: a customer whose profile says
            EU 42 should be able to see that number here and know where to
            correct it if it is wrong. */}
        {inMySize.length > 0 && (
          <section className="pt-20" aria-labelledby="home-my-size">
            <div className="flex items-end justify-between gap-6">
              <div>
                <p className="overline">Based on your size</p>
                <h2
                  id="home-my-size"
                  className="mt-2 font-display text-2xl font-semibold text-ink sm:text-3xl"
                >
                  In your size — {euSizeLabel(mySize)}
                </h2>
              </div>
              <Link
                to={`/shop?size=${euSizeValue(mySize)}`}
                className="group hidden shrink-0 items-center gap-1.5 text-sm font-semibold text-clay-ink sm:inline-flex"
              >
                See all in your size
                <ArrowRight
                  size={15}
                  strokeWidth={2.5}
                  className="transition-transform duration-300 ease-out-cubic group-hover:translate-x-1"
                />
              </Link>
            </div>

            {/*
              The collection's own grid, and deliberately not a rail: as a
              horizontal scroller these were the same `ProductCard` at 224px
              instead of a full column — a different size, no size tag, and a
              row whose cards could end at different heights (the flex item was
              the wrapper, not the card). The shelf is a slice OF the catalog, so
              it has to look like the catalog or it reads as a second, lesser
              one — which is exactly what it did.

              `ProductGrid` rather than a hand-rolled grid is the point of the
              change: one component, so the two cannot drift apart again, and the
              size tag comes back with it.
            */}
            <div className="mt-8">
              <ProductGrid products={inMySize} />
            </div>

            {/* `mt-8` where the rail could get away with `mt-2`: the scroller
                carried its own `pb-4` gutter, and a grid carries none — so the
                button would otherwise sit 8px under the last row of cards. This
                matches the collection's own mobile button. */}
            <div className="mt-8 sm:hidden">
              <Link
                to={`/shop?size=${euSizeValue(mySize)}`}
                className="btn btn-outline w-full"
              >
                See all in your size
              </Link>
            </div>
          </section>
        )}

        {/* ── Makers ────────────────────────────────────────────── */}
        <section className="pt-20">
          {/*
            Heading only, where every other section on this page pairs one with
            a link to "more". The banner below IS that link now, and a header
            `All makers →` sitting an inch above a banner that also goes to
            `/makers` is two doors to the same room — the one thing a doorway
            must not look like.
          */}
          <div>
            <p className="overline">The Association</p>
            <h2 className="mt-2 font-display text-2xl font-semibold text-ink sm:text-3xl">
              Meet the makers
            </h2>
          </div>

          <div className="mt-8">
            {isLoading ? (
              /* One banner's worth, not three cards': the placeholder has to be
                 the height of the thing that replaces it. */
              <div className="shimmer h-[360px] rounded-premium sm:h-[380px] lg:h-[400px]" />
            ) : makers.length > 0 ? (
              <MakersBanner stores={makers} />
            ) : null}
          </div>
        </section>
      </div>
    </>
  )
}

/**
 * "Sep 26" — no year.
 *
 * The shared `formatDate` prints one because it labels order rows, where the
 * year matters for a record. In a promo line it is four characters of noise:
 * a sale that ends in 2027 is not being advertised as an urgent one.
 */
function shortDay(value) {
  return new Date(value).toLocaleDateString('en-PH', {
    month: 'short',
    day: 'numeric',
  })
}

function OnSaleBand({ discount, productCount, makerCount, endsAt, thumbs }) {
  /*
    The link's label, spelled out, because the band is a *poster*: the figure is
    decoration, the timing is a chip and the facts are one line, and read in that
    order they are not a sentence anyone should be handed. Same move the product
    tiles make, for the same reason — one destination, one announcement.
  */
  const label = [
    `On sale — up to ${discount}% off${endsAt ? `, ends ${endsAt}` : ''}`,
    `${pluralize(productCount, 'pair')} from ${pluralize(makerCount, 'maker')}`,
    'See what’s on sale',
  ].join('. ')

  return (
    <Link
      to="/shop?onSale=1"
      aria-label={label}
      /*
        `bg-clay` is the brand fill and it does not follow the theme (see the
        token comments in tailwind.config.js), so everything drawn on it is
        white at a weight rather than an ink token — there is no brightness in
        which white-on-clay stops being the right ink.

        The focus ring is `ring-inset` for a reason that only bites at this
        width: the band is edge to edge, and an outer ring on a full-bleed
        element is clipped by the viewport on both sides.
      */
      className="group relative block w-full overflow-hidden bg-clay text-ink-inverse outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-white/70"
    >
      {/*
        Depth, all of it CSS: a light-to-shadow wash so the strip reads as a
        pressed band rather than a flat rectangle, the woven texture the old card
        carried (every maker in the association actually weaves something, which
        no stock photograph could say), and a letterpress pair of hairlines — a
        highlight on top, a shadow below.
      */}
      <span
        aria-hidden="true"
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            'linear-gradient(180deg, rgba(255,255,255,0.10) 0%, rgba(255,255,255,0) 46%, rgba(0,0,0,0.18) 100%)',
        }}
      />
      <span
        aria-hidden="true"
        className="pointer-events-none absolute inset-y-0 right-0 w-1/2"
        style={{
          backgroundImage:
            'repeating-linear-gradient(135deg, rgba(255,255,255,0.07) 0px, rgba(255,255,255,0.07) 1px, transparent 1px, transparent 9px)',
          WebkitMaskImage:
            'linear-gradient(to left, rgba(0,0,0,1) 0%, rgba(0,0,0,0) 100%)',
          maskImage:
            'linear-gradient(to left, rgba(0,0,0,1) 0%, rgba(0,0,0,0) 100%)',
        }}
      />
      <span
        aria-hidden="true"
        className="pointer-events-none absolute inset-x-0 top-0 h-px bg-white/20"
      />
      <span
        aria-hidden="true"
        className="pointer-events-none absolute inset-x-0 bottom-0 h-px bg-black/20"
      />
      {/*
        The hover cue for the whole band: a 6% white lift, not the 2px rise the
        card used. A strip that spans the viewport and moves vertically is a page
        that jumps under the cursor; brightening is the same "this is live"
        without moving anything.
      */}
      <span
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 bg-white/0 transition-colors duration-300 ease-out-cubic group-hover:bg-white/[0.06]"
      />

      <div className="relative mx-auto flex max-w-7xl flex-col gap-4 px-4 py-5 sm:px-6 sm:py-6 lg:flex-row lg:items-center lg:gap-8 lg:px-8">
        {/*
          The figure as a poster number rather than a stamped badge: at this size
          the display face is what makes the strip read as a *sale* and not as a
          stat. It is the one number on the site that is a headline — prices,
          sizes, counts and dates all stay in `num`.
        */}
        <span aria-hidden="true" className="flex shrink-0 items-end gap-2.5">
          <span className="font-display text-[2.75rem] font-semibold leading-[0.85] tracking-[-0.02em] sm:text-5xl lg:text-[3.5rem]">
            −{discount}%
          </span>
          {/*
            The small type on this band is white at 85–90%, not the 70–75% the
            first draft used, and the numbers are why: Burnished Clay is a mid
            tone, so white/70 on it measures ~4.0:1 — under AA for 10–13px text.
            /85 clears it at ~4.7:1. Hierarchy here comes from size, weight and
            tracking instead, which does not cost contrast.
          */}
          <span className="pb-1 text-[10px] font-semibold uppercase tracking-[0.22em] text-white/85 sm:pb-1.5">
            off
          </span>
        </span>

        {/* The rule between the figure and the words: one piece of structure is
            what stops a three-part row reading as a single long caption. */}
        <span
          aria-hidden="true"
          className="hidden h-14 w-px shrink-0 bg-white/20 lg:block"
        />

        <div className="flex min-w-0 flex-1 flex-wrap items-center gap-x-3 gap-y-2">
          <span className="text-[11px] font-semibold uppercase tracking-[0.16em] text-white/85">
            Limited time
          </span>
          {endsAt && (
            <span className="num inline-flex items-center gap-1.5 rounded-full border border-white/30 px-2.5 py-1 text-[11px] font-semibold leading-none text-white/90">
              <Clock size={11} strokeWidth={2.5} className="shrink-0" />
              Ends {endsAt}
            </span>
          )}

          {/*
            The band's one sentence, and the old card's headline, kept verbatim.
            What went is the second statement of the figure — `Up to 61% off right
            now` beside a 61% poster — which is what made the old card read as
            saying the same thing twice. The label above still says it in words
            for anyone who cannot see the poster.
          */}
          <p className="w-full text-sm leading-relaxed text-white/90 sm:text-[15px]">
            {pluralize(productCount, 'pair')} from{' '}
            {pluralize(makerCount, 'maker')}, straight from the bench.
          </p>
        </div>

        {/*
          The deepest deals, as an overlapping stack of swatches — and only when
          there is more than one. A lone 44px circle of somebody's product photo
          beside a full-width call to action reads as a mistake rather than as an
          illustration, and with a catalog this small that is the common case (the
          band is shown here with exactly one pair on sale). Two is a stack; one
          is a stray. Decorative either way: the whole band is one link.
        */}
        {thumbs.length > 1 && (
          <div aria-hidden="true" className="relative hidden shrink-0 -space-x-3 lg:flex">
            {thumbs.map((product, index) => (
              <span
                key={product.id}
                style={{ transitionDelay: `${index * 45}ms` }}
                className="relative h-11 w-11 overflow-hidden rounded-full border-2 border-white/25 bg-white/10 transition-transform duration-300 ease-out-cubic group-hover:scale-105"
              >
                {product.images?.[0] ? (
                  <img
                    src={product.images[0]}
                    alt=""
                    loading="lazy"
                    decoding="async"
                    className="h-full w-full object-cover"
                  />
                ) : (
                  <span className="block h-full w-full bg-white/10" />
                )}
              </span>
            ))}
          </div>
        )}

        {/*
          `btn-ghost` rather than `btn-primary`: the primary skin is a *clay*
          fill, and a clay pill on a clay band is a button nobody can see. The
          ghost skin is the one the app already defines for ink on a dark ground,
          and this is a `span` — the whole band is the link.
        */}
        {/* The `btn` base already sets the height (`py-3` → 44px, the target a
            thumb needs); only the radius is overridden, so the pill matches the
            band it sits on rather than the form controls elsewhere. */}
        <span className="btn btn-ghost relative w-full shrink-0 justify-center rounded-full sm:w-auto">
          See what&rsquo;s on sale
          <ArrowRight
            size={15}
            strokeWidth={2.5}
            className="transition-transform duration-300 ease-out-cubic group-hover:translate-x-1"
          />
        </span>
      </div>
    </Link>
  )
}

/*
  The makers banner's photograph — the one asset on this page that comes from the
  association rather than from the catalog, and the reason the banner exists at
  all: a workshop floor says "handmade in Carcar" in one glance, where a row of
  three name cards said it in nine words.

  `null` draws the placeholder ground below (each member workshop's own brand
  colour, so it is at least *their* palette rather than a generic grey). To swap
  the real thing in, either drop the file in `public/` and set this to its path
  (`'/makers-banner.jpg'`), or import it from `src/` and set it to the import.
  Nothing else has to change — same height, same caption bar, same destination.
*/
const MAKERS_BANNER = null

/**
 * The association, as one banner: photograph, caption bar, one destination.
 *
 * This replaces three maker cards, each its own link. The trade is deliberate.
 * Three cards in a `sm:grid-cols-3` row were the smallest possible version of
 * each workshop — a 52px avatar, a name and a tagline — and they were competing
 * with the catalog grid directly above them, which is the thing the page is
 * actually selling. The makers page is where a maker is the subject; on the home
 * page they are the *reason to trust the thing above them*, and that argument is
 * a photograph, not a list.
 *
 * The caption is a bar rather than text laid over the photograph. Two reasons,
 * and the second is the one that matters: white type over an asset nobody has
 * seen yet is a contrast lottery (the association's own photograph may well be a
 * bright workshop floor), and a bar of `chrome/70` with a blur keeps the ink
 * legible over any image at all — the same surface-over-photo treatment the
 * product tiles already use for their "View details" affordance.
 *
 * The whole banner is one link, so the caption and the button are not two tab
 * stops to the same place, and the avatars are `aria-hidden` decoration.
 */
function MakersBanner({ stores }) {
  const names = stores.map((store) => store.name).filter(Boolean)

  /*
    Each workshop's colour as a soft wash, evenly spaced across the width — the
    placeholder's way of being about *these three* rather than about a gradient.
    The `66` is the hex alpha of the brand colour (40%).
  */
  const washes = stores
    .map((store, index) => {
      const x = ((index + 0.5) / stores.length) * 100
      const color = storeColor(store)
      return `radial-gradient(46% 130% at ${x}% 50%, ${color}66 0%, ${color}00 72%)`
    })
    .join(', ')

  const label = `Meet the makers — ${pluralize(stores.length, 'member workshop')}${
    names.length ? `: ${names.join(', ')}` : ''
  }`

  return (
    <Reveal>
      <Link
        to="/makers"
        aria-label={label}
        /*
          Taller on a phone than on a desktop (420 against 400), which looks
          backwards until you measure the caption: the banner is a photograph
          *behind* a translucent bar, so every pixel the bar takes is a pixel of
          crisp photograph gone. Stacked, the mobile caption is ~230px; at 360
          that left 78px of photograph, and the bar had become the banner.
        */
        className="group relative flex h-[420px] flex-col justify-end overflow-hidden rounded-premium bg-chrome shadow-premium outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-white/70 sm:h-[380px] lg:h-[400px]"
      >
        {MAKERS_BANNER ? (
          <img
            src={MAKERS_BANNER}
            // Decorative: the link's own label names the workshops.
            alt=""
            className="absolute inset-0 h-full w-full object-cover transition-transform duration-700 ease-out-cubic group-hover:scale-[1.03]"
          />
        ) : (
          <>
            {/* The ground and the washes zoom together, so the placeholder
                reacts to the cursor exactly as the photograph will. */}
            <span
              aria-hidden="true"
              className="absolute inset-0 bg-chrome transition-transform duration-700 ease-out-cubic group-hover:scale-[1.03]"
            />
            <span
              aria-hidden="true"
              className="absolute inset-0 transition-transform duration-700 ease-out-cubic group-hover:scale-[1.03]"
              style={{ backgroundImage: washes }}
            />
          </>
        )}

        <div className="relative flex flex-col gap-4 border-t border-white/15 bg-chrome/70 px-5 py-4 backdrop-blur-sm sm:flex-row sm:items-center sm:justify-between sm:gap-8 sm:px-7 sm:py-5">
          {/*
            The avatar stack is `sm` and up. On a 358px banner it was two
            separate problems at once: inline it squeezed the text column to
            ~200px and the sentence wrapped to six lines, and stacked above the
            words it took a 58px row of a banner that is a photograph behind a
            bar. Measured both ways — inline gave 78px of crisp photograph,
            stacked gave 160, and without it the caption is 204px of a 420px
            banner. The names line already says who they are; the photograph is
            where the faces are.
          */}
          <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
            {/*
              Each avatar keeps the surface colour behind it rather than sitting
              straight on the bar: the fallback avatar is a *tint* of the store's
              colour (see `StoreAvatar`), which is designed to be read on a card,
              not on a dark bar — this is the card, brought with it.
            */}
            <span aria-hidden="true" className="hidden shrink-0 -space-x-3 sm:flex">
              {stores.map((store) => (
                <span
                  key={store.id}
                  className="rounded-full bg-raised p-0.5 ring-1 ring-white/20"
                >
                  <StoreAvatar store={store} size={42} />
                </span>
              ))}
            </span>

            <div className="min-w-0">
              {/* The label line is desktop-only: on a phone the avatars sit
                  directly above the names, which is what the label says, and
                  the sentence below is the part worth the two lines it costs. */}
              <p className="hidden text-[11px] font-semibold uppercase tracking-[0.16em] text-white/85 sm:block">
                Member workshops
              </p>
              <p className="truncate font-display text-lg font-semibold text-white sm:mt-1.5 sm:text-xl">
                {names.join(' · ')}
              </p>
              {/*
                The association's own sentence, the same one the makers page
                opens with (`ASSOCIATION_INTRO`, so there is only ever one copy
                of it). It is the caption's *body*, under the names, because the
                photograph is the banner's claim and this is the evidence: who
                these people are and where they have always worked.
              */}
              <p className="mt-2 max-w-2xl text-[13px] leading-snug text-white/85 sm:mt-2.5 sm:text-sm sm:leading-relaxed">
                {ASSOCIATION_INTRO}
              </p>
            </div>
          </div>

          <span className="btn btn-ghost w-full shrink-0 justify-center rounded-full sm:w-auto">
            Meet the makers
            <ArrowRight
              size={15}
              strokeWidth={2.5}
              className="transition-transform duration-300 ease-out-cubic group-hover:translate-x-1"
            />
          </span>
        </div>
      </Link>
    </Reveal>
  )
}

function RequestFailed() {
  return (
    <div className="rounded-card border border-crimson/25 bg-crimson/[0.06] px-6 py-10 text-center">
      <p className="font-semibold text-crimson">Could not load the catalog</p>
      <p className="mt-1 text-sm text-muted">
        Please check your connection and try again.
      </p>
    </div>
  )
}
