/**
 * The heading every seller page carries.
 *
 * One component so the five pages cannot drift on the one thing that makes them
 * feel like one place: the title sits on the same line at the same size, and the
 * page's own actions sit on the right of it. `eyebrow` is where a count or a
 * date goes — "3 orders today" belongs above the list, not as a card.
 */
export function SellerPageHeader({ title, eyebrow, description, actions }) {
  return (
    <header className="flex flex-wrap items-start justify-between gap-4">
      <div className="min-w-0">
        {eyebrow && <p className="overline">{eyebrow}</p>}
        <h1 className="mt-1.5 font-display text-2xl font-semibold text-ink sm:text-3xl">
          {title}
        </h1>
        {description && (
          <p className="mt-2 max-w-2xl text-sm leading-relaxed text-muted">
            {description}
          </p>
        )}
      </div>
      {actions && <div className="flex shrink-0 flex-wrap gap-2">{actions}</div>}
    </header>
  )
}

/**
 * One figure, with the label that says what it counts.
 *
 * The figure is in the numeric face with tabular figures (`.num`), because a
 * number a seller compares against another number — this week against last, mine
 * against the tray — has to line up when it changes. Colour is not decoration:
 * `tone="alert"` is only used for the count that is asking the seller to do
 * something, and it is the only tone that ever means "look here".
 */
const FIGURE_TONES = {
  neutral: 'text-ink',
  // The seller dashboard's own data accent — `SellerTheme.rust` in the app.
  accent: 'text-rust',
  alert: 'text-crimson',
  good: 'text-olive',
}

/**
 * How big a figure is, per step.
 *
 * `hero` is the dashboard's one dominant number and it is set in the **numeric
 * face** (Sora, tabular) rather than the display face, which is a deliberate
 * departure from how the storefront treats a headline number. The sale ribbon's
 * discount is Playfair because it is a *claim*; these are readings — money
 * taken, orders waiting — and the README's own rule is that prices, sizes and
 * counts stay in `num`. A hero that changed typeface would also stop lining up
 * column-to-column, which is the whole reason the numeric face is tabular.
 *
 * Sizes step rather than being one arbitrary value per call site, so "bigger"
 * always means the same amount bigger and a new figure cannot invent a fourth
 * scale by accident.
 */
const FIGURE_SIZES = {
  default: 'text-2xl',
  large: 'text-3xl',
  /*
    Tight tracking, because tabular figures at 60px are wide and "₱12,480"
    tracked out looks like a serial number rather than a total.

    The 6xl step is `xl`, not `sm`. The hero is on a full-width row below `lg`
    and inside a two-column split from `lg` up, so at exactly `lg` (1024px) the
    figure has roughly 290px — where six digits at 60px is 240px of type with a
    caption that then wraps to three lines beside it. 48px fits comfortably
    there and 60px is free again from 1280px.
  */
  hero: 'text-5xl tracking-tight xl:text-6xl',
}

/**
 * One reading: a label, a figure, and a line explaining it.
 *
 * Split out of `SellerMetric` when the dashboard's figures became a hero block,
 * because the number was suddenly being drawn in two different containers (a
 * tile and a band) and two copies of the tone map is how the same "needs you"
 * count ends up amber on one page and crimson on another.
 *
 * `value` is a node rather than a number, which is what lets a page hand it a
 * `CountUp` instead of a formatted string. The figure still arrives complete
 * either way — the counter renders the true value for anything that does not run
 * JavaScript animation — so a page that passes a plain string is not the lesser
 * case.
 */
export function SellerFigure({
  label,
  value,
  hint,
  tone = 'neutral',
  size = 'default',
  layout = 'stacked',
  className = '',
  labelClassName = '',
}) {
  const figure = `num font-semibold ${FIGURE_SIZES[size] ?? FIGURE_SIZES.default} ${
    FIGURE_TONES[tone] ?? FIGURE_TONES.neutral
  }`

  /*
    Three arrangements, and the choice between them is about **rank**, not taste.
    A reading's arrangement is what tells the eye how it compares to the one beside
    it, so the shapes are deliberately not interchangeable:

     * `stacked` (the default) — one number with room to say what it means. The
       form for a reading that stands on its own, and the biggest of the three.
     * `inline` — value then label, several of them across a page: a **strip**, read
       left to right and compared against each other (`SellerProducts`' four
       catalogue figures).
     * `row` — label left, value right, several of them down a column: a **list of
       secondary readings** that share one right edge, which is how a supporting
       column stays legible without competing with the number it supports.

    The label is sentence case in both of the compact forms, and that is the point
    rather than an oversight: an uppercase tracked eyebrow is a *heading*, which is
    what it is when it sits above a number on its own, and an interruption when it
    sits beside one.
  */
  if (layout === 'inline' || layout === 'row') {
    const labelNode = (
      <span className={`text-sm font-medium text-muted-strong ${labelClassName}`}>
        {label}
      </span>
    )

    return (
      <div className={className}>
        {layout === 'inline' ? (
          <p className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
            <span className={figure}>{value}</span>
            {labelNode}
          </p>
        ) : (
          <p className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
            {labelNode}
            <span className={figure}>{value}</span>
          </p>
        )}
        {hint && (
          <p className="mt-1 text-xs leading-relaxed text-muted">{hint}</p>
        )}
      </div>
    )
  }

  return (
    <div className={className}>
      <p
        className={`text-xs font-semibold uppercase tracking-[0.08em] text-muted ${labelClassName}`}
      >
        {label}
      </p>
      <p className={`mt-2 ${figure}`}>{value}</p>
      {hint && (
        <p className="mt-2 text-xs leading-relaxed text-muted">{hint}</p>
      )}
    </div>
  )
}

/** A figure in its own card — the reporting layout, where every reading is equal. */
export function SellerMetric({ className = '', ...props }) {
  return (
    <div
      className={`rounded-card border border-hairline bg-raised p-5 shadow-card ${className}`}
    >
      <SellerFigure {...props} />
    </div>
  )
}

/**
 * A section inside a seller page.
 *
 * The card is `bg-raised` on `bg-page`, which is the portal's own surface
 * language rather than a seller-specific one — the app's seller palette is
 * deliberately the same neutral surfaces as everywhere else, with the brand
 * browns reserved for data.
 */
export function SellerSection({ title, description, actions, children }) {
  return (
    <section className="rounded-premium border border-hairline bg-raised shadow-card">
      {(title || actions) && (
        <div className="flex flex-wrap items-start justify-between gap-3 border-b border-hairline-soft px-5 py-4">
          <div className="min-w-0">
            {title && (
              <h2 className="font-display text-lg font-semibold text-ink">
                {title}
              </h2>
            )}
            {description && (
              <p className="mt-1 text-sm text-muted">{description}</p>
            )}
          </div>
          {actions}
        </div>
      )}
      <div className="p-5">{children}</div>
    </section>
  )
}

/**
 * The standard padding for a seller page's own scroll container.
 *
 * The container and its side padding are `SellerHeader`'s, deliberately: with
 * the nav in a top bar rather than a rail, the page and the bar now share a left
 * edge, and any difference shows up as content that does not line up with the
 * logo directly above it. This was `max-w-6xl` with wider padding back when a
 * 240px sidebar sat beside it and nothing had to agree.
 */
export function SellerPageBody({ children }) {
  return (
    <div className="px-4 py-8 sm:px-6 lg:px-8 lg:py-10">
      <div className="mx-auto flex max-w-7xl flex-col gap-6">{children}</div>
    </div>
  )
}
