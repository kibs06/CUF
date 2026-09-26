/** @type {import('tailwindcss').Config} */

// Tokens are named after the roles in `lib/constants/app_palette.dart`, not
// after what they look like — so a class here reads the same way the Flutter
// side reads its token, and the two cannot drift apart by accident:
//
//   `bg-page`    ↔ AppPalette.page      (the surface everything sits on)
//   `text-ink`   ↔ AppPalette.onPage    (primary text/icon ink on page)
//   `border-hairline` ↔ AppPalette.hairline
//   `bg-clay`    ↔ AppConstants.primary (Burnished Clay — the brand fill)
//
// ## Why the roles are CSS variables now
//
// The surface and ink roles are declared as `rgb(var(--token) / <alpha-value>)`
// and their values live in `:root` / `.dark` in `index.css`, which is what lets
// one class (`bg-page`, `text-ink`) resolve to two palettes. The values are the
// two columns of `AppPalette` ported across:
//
//   light  = AppPalette.light, "byte-identical to the palette the app shipped
//            before dark mode existed" — light mode must not move
//   dark   = AppPalette.dark
//
// The *brand and status* fills stay literal hex, because the app pins them too:
// clay is clay in both brightnesses, and a fill someone draws ink on does not
// follow a theme.
//
// `clay-ink` is the one token with no light-mode history. The app splits the
// brand fill from brand *text* (`primaryInk`, #C08A4E on dark) because
// Burnished Clay on a dark page is about 3:1 against #111111 — readable as a
// button, not as 14px body copy. Every place the portal draws clay as text or
// an icon uses `text-clay-ink`; every place it paints a fill uses `bg-clay`.
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        // Headlines — the app's `headlineStyle`
        display: ['"Playfair Display"', 'serif'],
        // Body and labels — the app's `bodyStyle`
        sans: ['"DM Sans"', 'sans-serif'],
        // Numbers, prices, sizes — the app's `monoStyle` (Sora, tabular)
        numeric: ['"Sora"', 'sans-serif'],
      },
      colors: {
        // ── Brand & semantic fills — PINNED, same in both brightnesses ──
        // A fill someone draws ink on, or a status meaning. These do not
        // follow a theme in the app either.
        clay: '#8B5A2B', // primary   — Burnished Clay
        // The seller dashboard's own data accent — `SellerTheme.rust` and
        // `rustDeep` in the app. Added when the seller portal was built: the
        // app's seller surface has always had its own accent (it is what paints
        // today's sales figure, the sparklines and the status dots), and the
        // portal had nowhere for it to land until there was a seller page.
        rust: '#B5622E',
        'rust-deep': '#9C4E22',
        celadon: '#4ECDC4', // accent    — Celadon Teal
        basket: '#FC5E03', // cartIcon  — Basket Orange
        olive: '#6B8F47', // success   — Olive Stitch
        crimson: '#D64545', // error     — Crimson Welt
        amber: '#F59E0B', // pending   — statusPendingColor

        // ── Surface roles ──
        page: 'rgb(var(--page) / <alpha-value>)', // the page itself
        raised: 'rgb(var(--raised) / <alpha-value>)', // a card lifted off the page
        subtle: 'rgb(var(--subtle) / <alpha-value>)', // inputs, unselected chips
        band: 'rgb(var(--band) / <alpha-value>)', // grounded band
        chrome: 'rgb(var(--chrome) / <alpha-value>)', // dark bar / control fill

        // ── Hairlines ──
        hairline: 'rgb(var(--hairline) / <alpha-value>)',
        'hairline-soft': 'rgb(var(--hairline-soft) / <alpha-value>)',
        'card-edge': 'rgb(var(--card-edge) / <alpha-value>)',

        // ── Ink ──
        ink: 'rgb(var(--ink) / <alpha-value>)', // primary text on page/raised
        muted: 'rgb(var(--muted) / <alpha-value>)', // captions, overlines
        'muted-strong': 'rgb(var(--muted-strong) / <alpha-value>)',
        'ink-inverse': 'rgb(var(--ink-inverse) / <alpha-value>)', // ink on clay

        // Clay as TEXT — lifts on dark, where the fill would fail contrast.
        'clay-ink': 'rgb(var(--clay-ink) / <alpha-value>)',

        // The modal backdrop. Its variable carries its own alpha, so this is
        // used bare (`bg-scrim`) and never with an opacity modifier.
        scrim: 'rgb(var(--scrim))',
      },
      borderRadius: {
        // Mirrors AppConstants: cardRadius / productCardCorner / buttonRadius /
        // premiumCardRadius / fieldRadius.
        card: '16px',
        product: '10px',
        premium: '20px',
        field: '14px',
      },
      boxShadow: {
        // The app's shadows are all the same espresso tint at different
        // weights (`AppConstants._cardShadowTint`), never a second grey. On
        // dark they become a neutral black at a heavier weight, because the
        // espresso tint has no brightness to darken — see `index.css`.
        warm: '0 4px 12px var(--shadow-warm)',
        card: '0 6px 16px -4px var(--shadow-card-far), 0 1px 3px var(--shadow-card-near)',
        // The hover state of `card`: the SAME two layers, widened — so the
        // lift reads as one surface moving, not a different shadow arriving.
        'card-lift':
          '0 16px 36px -10px var(--shadow-lift-far), 0 2px 6px var(--shadow-lift-near)',
        premium: '0 12px 32px -4px var(--shadow-premium)',
      },
      //
      // No `keyframes`/`animation` block on purpose. Tailwind only emits the
      // @keyframes for an animation that a used `animate-*` utility references,
      // so a keyframe defined here and called from plain CSS in `index.css`
      // would silently never ship. Every animation on the site is either
      // motion-driven (entrances, hovers) or declared in `index.css` next to
      // the rule that uses it (the entrance set and the skeleton shimmer).
      //
      transitionTimingFunction: {
        // The app's `Curves.easeOutCubic`, as a Tailwind easing so declarative
        // CSS transitions and the JS motion tokens match.
        'out-cubic': 'cubic-bezier(0.33, 1, 0.68, 1)',
      },
    },
  },
  plugins: [],
}
