/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      fontFamily: {
        display: ['"Playfair Display"', 'serif'],
        sans: ['"DM Sans"', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'monospace'],
      },
      colors: {
        primary: '#8B5A2B',
        primaryDeep: '#6F4520',
        secondary: '#3B2314',
        ink: '#1F1B16',
        muted: '#6B5C4E',
        faint: '#EDE5DB',
        accent: '#0E7C7B',
        accentSoft: '#E0F2F1',
        surface: '#F5F0EB',
        canvas: '#FAF7F2',
        border: '#D9D0C7',
        error: '#B3261E',
        errorSoft: '#FDECEA',
        pending: '#9A6B0A',
        pendingSoft: '#FFF4D6',
      },
      boxShadow: {
        card: '0 1px 2px rgba(59, 35, 20, 0.06)',
        pop: '0 8px 24px rgba(59, 35, 20, 0.12)',
      },
    },
  },
  plugins: [],
}
