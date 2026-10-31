# tanstack-start — implementation status

| Milestone | State | Landed |
|---|---|---|
| TS0 — the spec | ✅ | TS-1 |
| TS1 — TanStack Start on Workers | ✅ | TS-2 |
| TS2 — a baseline | ✅ | TS-3, tagged `baseline-v1` |
| TS3 — scaffold, then live | ✅ on `main` | TS-4, to be tagged `baseline-v2` |

## Departures from the upstream template

Everything not listed here is the template as it is upstream at `84878e5`
(vercel/vercel `examples/tanstack-start`, Apache-2.0; its licence ships as
`apps/web/LICENSE`, and `apps/web/README.md` lists the files changed).

| # | What | Why |
|---|---|---|
| 1 | The app lives in `apps/web` of a pnpm workspace (`@app/web`); upstream's `pnpm-lock.yaml` is replaced by the workspace's lockfile | The workspace's shape (sveltekit-boilerplate's) |
| 2 | `nitro` (`nitro/vite`) → `@cloudflare/vite-plugin` 1.66.0 with wrangler 4.155.0; `wrangler.jsonc` added | TanStack Start's documented Cloudflare target (design §2) |
| 3 | TanStack Start `1.133.37` → `1.169.4` (Router `1.170.46`, router devtools `1.167.2`, devtools `0.10.13`), Vite `^7.1.7` → `^8.3.4`, `@vitejs/plugin-react` `^5.0.4` → `^6.1.2`, vitest `^3.0.5` → `^5.0.4` | The current Start and the plugin's target; Start 1.169 requires Vite 8 |
| 4 | `.inputValidator` → `.validator` in `addTodo`; the SPA demo's state typed as the list's element | 1.169's rename, and its narrower inference of a server function's result |
| 5 | The todos kept in the visitor's own httpOnly cookie (`src/data/todos.ts`; `Path=/`, `SameSite=Lax`, `Secure` over HTTPS; 50 × 100 characters, 3,800 encoded bytes) instead of `todos.json` through `node:fs`; a todo the cookie cannot hold is refused with its reason, shown under the input | A Worker has no disk that outlives a request (design §2) |
| 6 | `vite-tsconfig-paths` dropped for Vite's own `resolve.tsconfigPaths` | Vite 8 resolves tsconfig paths itself and warns that the plugin is redundant |
| 7 | The `<title>` reads `SITE_NAME` from `src/lib/site.ts` (upstream's literal `TanStack Start Starter`) | One rename seam |
| 8 | The template's `biome.json`, run as `biome lint` (`@biomejs/biome` 2.2.4, the version its schema names), and the code made to pass it: `type="button"` on four buttons, the feature cards keyed by title, `submitTodo`'s hook dependencies (which drops upstream's dead `todos =` reassignment) | Upstream ships the config but not Biome, and its code fails the config's recommended rules; the formatter (tabs) is not run, so the formatting stays upstream's |
| 9 | Unused dependencies dropped: `@tanstack/react-router-ssr-query`, `@tanstack/router-plugin` (Start's plugin brings its own), `@testing-library/dom`, `@testing-library/react`, `jsdom`, `web-vitals` | Nothing imports them |
| 10 | `src/routeTree.gen.ts` regenerated | 1.169's router generator orders and names routes differently; committed as upstream commits it |
| 11 | `src/styles.css`: `@import "tailwindcss" source("./")` — Tailwind reads its classes from `src/` alone | Left to detect its sources, Tailwind scans the app's directory; outside a git checkout (a CI job's staged tree) nothing excludes `dist/`, the server build reads the client build's output, emits a stylesheet with another hash, and every page links a CSS file that is not in `dist/client` (404). The end-to-end tier caught it in the staged tree |
| 12 | Tests (vitest, node): the site's name seam, the todo store | The template has a `test` script and no tests |
| 13 | `component.yaml`, `docs/`, `vitest.config.ts`, `LICENSE` | The deploy contract, its generated pages, the tests' config without the framework plugins, and Apache-2.0's copy of the licence |

Kept as upstream, and worth knowing: TanStack's devtools render in
production (risk TS-E); `/demo/start/api-request` fetches the API route
from the browser; the drawer's SSR sub-menu is collapsed by default.

## Measured

The Worker: 1 360.69 KiB, 304.58 KiB gzipped, inside Workers Free's 3 MiB
(`wrangler deploy --dry-run`, the same from
`wrangler.jsonc` and from the plugin's `dist/server/wrangler.json`).

## TS3 — scaffold, then live (as built)

- **Three phases, two stages.** `01-scaffold` (GitHub only) places the whole
  tree, brands it, parks stage's and prod's push activation and lands it;
  `02-live` (Cloudflare) binds the subdomain, restores the lanes, defers the
  promotion gate and dev's push lanes, retouches `web`, mints the two keys,
  lands, watches and probes; `03-docs` restores the gate and dev's lanes and
  records. The card's `spec.stages` is `{scaffold: 01-scaffold, live:
  02-live}`; `expectedMinutes` 5 (1 + 3 + 1), an estimate.
- **Dev keeps its push activation in the scaffold.** orun refuses a push plan
  that no environment answers (`trigger binding "github-push-main" matched,
  but no environment references it`), so parking all three would turn `main`
  red; with dev left on, a code-only site's merge plans dev's verify lane — no
  credential — and nothing else. `promotion` and `dev-lanes` moved to
  `02-live`, the landing whose convergence they shorten.
- **The late-bound subdomain is bound by a hook.** A resume does not place
  `01-scaffold`'s files again, so `02-live`'s `subdomain` hook rewrites the
  placeholder as a whole DNS label in every tracked file, `.rebrand/values.json`
  last, refusing the placeholder itself and a move from one real subdomain to
  another. `03-docs` renders the record from the bound identity file.
- **No GitHub connection probe.** The scaffold's GitHub gate is `link`
  (`orun cloud check`): a managed-GitHub repository is linked through a
  platform connection the workspace's list never shows, so a `github`
  doctor probe would time out on a ready build. Cloudflare is probed by
  `02-live` alone, deferred to just before it when it is missing at the start.
- **Framing.** `apps/web/src/server.ts` is the Worker's entry (named in
  `vite.config.ts` in place of `@tanstack/react-start/server-entry`, which it
  wraps); `src/lib/framing.ts` holds the per-environment `frame-ancestors`
  map — on stage `'self'`, orun.work's stage and prod origins and
  `http://localhost:*`. The environment is written in at build time:
  the component's `environmentBuildVar: DEPLOY_ENV` (stack-tectonic 0.19.0
  exports it to `build-app`), passed by `apps/web/turbo.json`'s `env`, and
  `define`d as `__DEPLOY_ENV__`. The Worker grew by about 1 KiB (1 361.86 KiB,
  305.45 KiB gzipped).
- **Proven offline.** A full build ends on `baseline-v1`'s tree but for the
  framing files and the redeploy marker's phase; its three merges plan dev's
  verify lane, then the deploy to stage and prod side by side, then nothing;
  a code-only build (`--until 01-scaffold`, no subdomain) taken live later
  ends on the full build's tree byte for byte. Also run against orun v2.90.0
  (late-bound inputs), which refuses a run past the scaffold that would keep
  the placeholder.

