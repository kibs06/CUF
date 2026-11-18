/** @type {import('tailwindcss').Config} */

// Every brand colour is a CSS variable (as "r g b" so Tailwind's `/opacity`
// modifiers keep working). The light values live in :root and the dark ones in
// .dark — see src/index.css — so `bg-canvas`, `text-ink` and `border-border`
// follow the theme without a single `dark:` variant in the pages.
const token = (name) => `rgb(var(--c-${name}) / <alpha-value>)`

export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        display: ['"Playfair Display"', 'serif'],
        sans: ['"DM Sans"', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'monospace'],
      },
      colors: {
        primary: token('primary'),
        primaryDeep: token('primary-deep'),
        secondary: token('secondary'),
        ink: token('ink'),
        muted: token('muted'),
        faint: token('faint'),
        accent: token('accent'),
        accentSoft: token('accent-soft'),
        surface: token('surface'),
        canvas: token('canvas'),
        border: token('border'),
        error: token('error'),
        errorSoft: token('error-soft'),
        pending: token('pending'),
        pendingSoft: token('pending-soft'),
        pendingInk: token('pending-ink'),
        danger: token('danger'),
        sand: token('sand'),
        card: token('card'),
        info: token('info'),
        infoSoft: token('info-soft'),
        violet: token('violet'),
        violetSoft: token('violet-soft'),
        warning: token('warning'),
        warningSoft: token('warning-soft'),
      },
      boxShadow: {
        card: '0 1px 2px rgba(59, 35, 20, 0.05), 0 4px 16px -8px rgba(59, 35, 20, 0.12)',
        pop: '0 12px 32px -8px rgba(59, 35, 20, 0.22)',
      },
    },
  },
  plugins: [],
}
