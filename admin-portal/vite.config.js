import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      // `@gltf-transform/core` imports `node:fs` and `node:path` for its
      // *Node* IO, which this app never constructs — it uses `WebIO`, and only
      // inside the compression worker. Vite externalizes the two built-ins
      // correctly (the browser build simply never reaches them), but it warns
      // about every externalized import, and the warning is the kind that
      // trains people to ignore build output. Naming the two here says the
      // externalization is expected rather than an oversight.
      external: ['node:fs', 'node:path'],
    },
  },
})
