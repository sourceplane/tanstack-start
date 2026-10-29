import { defineConfig } from 'vitest/config'

// The unit tests are plain modules (the site's name, the todo store): no
// Worker, no Start build, so none of vite.config.ts's framework plugins.
export default defineConfig({
  // tsconfig.json's `@/*` paths, as vite.config.ts resolves them.
  resolve: { tsconfigPaths: true },
  test: {
    include: ['src/**/*.test.ts'],
    environment: 'node',
  },
})
