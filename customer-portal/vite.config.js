import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The portal's own version, read from package.json rather than hand-typed, so
// the number Settings shows and the number a release bump changes cannot
// disagree. `define` substitutes it at build time — there is no runtime fetch.
const { version } = JSON.parse(
  readFileSync(new URL('./package.json', import.meta.url), 'utf8'),
)

// Ports are offset from the admin portal's Vite defaults (5173 / 4173) so both
// apps can run side by side during development without one stealing the other's
// port.
export default defineConfig({
  plugins: [react()],
  define: {
    __PORTAL_VERSION__: JSON.stringify(version),
  },
  server: { port: 5174 },
  preview: { port: 4174 },
  build: {
    rollupOptions: {
      output: {
        // Split the three large, slow-moving dependencies into their own
        // chunks. They change only when a dependency is upgraded, while the
        // site's own code changes on every deploy — so a customer who came
        // back after a release re-downloads the app code only, not React,
        // motion and the Supabase client with it.
        manualChunks: {
          react: ['react', 'react-dom', 'react-router-dom'],
          motion: ['motion'],
          supabase: ['@supabase/supabase-js'],
        },
      },
    },
  },
})
