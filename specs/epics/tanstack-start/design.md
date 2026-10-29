# tanstack-start — design

## 1. The template

`examples/tanstack-start` in vercel/vercel is the app TanStack's CLI
generates, with Nitro as its Vercel build: TanStack Start 1.133 (React 19,
TanStack Router's file routes), Tailwind CSS 4 and `lucide-react`, Vite 7.

| Route | What it shows |
|---|---|
| `/` | the welcome page: the TanStack Start hero and six feature cards |
| `/demo/start/server-funcs` | a todo list: `getTodos` (a GET server function) runs in the route's loader, `addTodo` (POST) appends one and the route reloads |
| `/demo/start/api-request` | a page whose browser fetches `/demo/api/names` |
| `/demo/api/names` | an API route (a server route handler): `["Alice","Bob","Charlie"]` |
| `/demo/start/ssr/` | links to the three SSR modes |
| `/demo/start/ssr/full-ssr`, `/data-only`, `/spa-mode` | `getPunkSongs` (a GET server function) rendered on the server, loaded on the server and rendered in the browser, and called from the browser |

The header's drawer links them; the root renders TanStack's devtools.
Upstream keeps the todos in `todos.json` beside the server, read and written
with `node:fs`.

## 2. How each Vercel piece maps to Cloudflare

| Vercel | Here | Why |
|---|---|---|
| Nitro (`nitro/vite`) builds the server for Vercel's functions | `@cloudflare/vite-plugin` (`viteEnvironment: ssr`): `vite build` writes the Worker to `dist/server` and the browser's files to `dist/client` | TanStack Start's documented Cloudflare target; `vite dev` runs the server in workerd too |
| The functions' Node runtime | `nodejs_compat` on compatibility date 2026-10-01 | Start's server uses `AsyncLocalStorage` and other `node:` modules |
| `todos.json` on the server's disk | the visitor's own httpOnly cookie, `Path=/`, `SameSite=Lax`, `Secure` over HTTPS (`src/data/todos.ts`) | A Worker has no disk that outlives a request (a Vercel function's is read-only outside `/tmp`, so upstream's `addTodo` fails there too). The cookie needs no database and keeps the demo's point: a GET server function in a loader, a POST one that changes what it reads |
| `public/` and the hashed build on Vercel's CDN | Static Assets (`assets.directory: dist/client`), served ahead of the Worker | Same files, same URLs |
| Deploy on push | Orun's `cloudflare-workers-assets-turbo` component, `<repo>-web-{stage,prod}` | The Cirrus conventions |

TanStack Start 1.133 → 1.169 (with Vite 8, `@vitejs/plugin-react` 6 and
vitest 5): the Cloudflare target is built against the current Start, whose
plugin requires Vite 8. The upgrade renames `.inputValidator` to
`.validator` and infers server-function results more narrowly; both show in
two lines.

## 3. One Worker config for the build and the deploy

The Vite plugin reads `wrangler.jsonc` and writes the deployable config
beside its build (`dist/server/wrangler.json`), with a redirect
(`.wrangler/deploy/config.json`) that a bare `wrangler deploy` follows. The
component's deploy runs `wrangler deploy --config wrangler.jsonc`, and an
explicit `--config` never follows the redirect; its `verify-structure` step
also checks that the config exists before the build. So `wrangler.jsonc` is
the BUILT Worker — `main: dist/server/index.js`, `no_bundle` with the
plugin's `ESModule` rule, `assets.directory: dist/client` — and
`vite.config.ts` names the source entry the plugin builds
(`config: { main: '@tanstack/react-start/server-entry' }`). The plugin drops
`no_bundle` and `rules` under Vite and says so once per build.

A dry-run deploy of either config uploads the same modules. The
end-to-end tier holds the two together on every run: same name,
compatibility date and flags, entry and assets directory, and the same
upload.

## 4. The repository and the build

sveltekit-boilerplate's shape: one component, `apps/web`
(`cloudflare-workers-assets-turbo`, `lane: isolated`), its tests inside the
app (vitest over the site's name and the todo store), the shared
TypeScript/ESLint configuration and the wrangler renderer under `tooling/`,
stack-tectonic 0.19.0, `ci.yml` as turso-starter's (as sveltekit-boilerplate
carries it). The site's name is one seam: `SITE_NAME` in `src/lib/site.ts`,
read by the root route's `<title>` (upstream's `TanStack Start Starter`).
The smoke reads the home page's server-functions link, the API route's JSON
and a 404.

## 5. Alternatives rejected

- **A second, deploy-only config** (`wrangler.deploy.jsonc` beside the
  plugin's `wrangler.jsonc`): two files naming one Worker drift; one file
  and a test that it matches the plugin's output do not.
- **Deploying the plugin's own `dist/server/wrangler.json`**: the
  component's `verify-structure` step checks the config before the build,
  and the build has not written it yet.
- **Keeping TanStack Start 1.133 with Vite 7**: the current plugin and Start
  are what TanStack documents for Cloudflare; the pinned example is a
  year behind.
- **A KV namespace for the todos**: shared, durable state is a database the
  template does not have; per-visitor state in a cookie is what the demo
  needs, and swapping in KV is a README line.
