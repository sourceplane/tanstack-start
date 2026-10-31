import { cloudflare } from '@cloudflare/vite-plugin'
import tailwindcss from '@tailwindcss/vite'
import { tanstackStart } from '@tanstack/react-start/plugin/vite'
import viteReact from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Vercel's Nitro (`nitro/vite`) becomes Cloudflare's own Vite plugin, which
// is TanStack Start's documented Cloudflare target: `vite dev` runs the server
// in workerd, and `vite build` writes the Worker to dist/server and the
// browser's files to dist/client.
//
// The plugin reads wrangler.jsonc — the one Worker config, which also
// describes the BUILT Worker for `wrangler deploy --config wrangler.jsonc`
// (the deploy lane's exact command). So the source entry it builds from is
// named here instead of in that file's `main`, and the plugin's build warns
// once that the file's `no_bundle` and `rules` are ignored under Vite: they
// are for the deploy, which uploads the build's modules as they are.
//
// The source entry is src/server.ts: TanStack Start's own handler
// (`@tanstack/react-start/server-entry`), with the site's framing policy on
// every response (src/lib/framing.ts).
export default defineConfig({
  // tsconfig.json's `@/*` paths: Vite 8 resolves them itself (the template's
  // vite-tsconfig-paths plugin is redundant on it, and Vite says so).
  resolve: { tsconfigPaths: true },
  // The environment this build deploys to, written into the bundle: the
  // deploy lane exports DEPLOY_ENV to its build (`environmentBuildVar` in
  // component.yaml), and src/lib/framing.ts reads it to decide who may frame
  // the site. Empty when nothing names one (`vite dev`, a build by hand).
  define: {
    __DEPLOY_ENV__: JSON.stringify(process.env.DEPLOY_ENV ?? ''),
  },
  plugins: [
    cloudflare({
      viteEnvironment: { name: 'ssr' },
      config: { main: './src/server.ts' },
    }),
    tailwindcss(),
    tanstackStart(),
    viteReact(),
  ],
})
