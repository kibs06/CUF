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
        secondary: '#3B2314',
        accent: '#4ECDC4',
        surface: '#F5F0EB',
        border: '#D9D0C7',
        error: '#D64545',
        pending: '#E8A020',
      },
    },
  },
  plugins: [],
}
