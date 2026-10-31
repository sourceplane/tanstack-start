# tanstack-start — implementation plan

Three milestones, one task each, each landed as one pull request.

## TS0 — the spec (TS-1)

The repository is born with sveltekit-boilerplate's frame — `intent.yaml`
(dev verify-only, stage, prod after stage; the placeholder workspace
`ws_CHANGE_ME`, so CI plans nothing until it is linked), `ci.yml` byte for
byte turso-starter's (as sveltekit-boilerplate carries it), the shared
TypeScript and ESLint configuration, the wrangler renderer, the pnpm
workspace and turbo pipeline, and the spec index — and this doc set and the
three task contracts land on it.

## TS1 — TanStack Start on Workers (TS-2)

- `apps/web` is upstream's app: `src/` (the routes, the header, the punk
  songs, the styles), `public/`, `tsconfig.json`, `biome.json` — on
  TanStack Start 1.169, with `@cloudflare/vite-plugin` in place of Nitro, the
  todos in the visitor's cookie (`src/data/todos.ts`), the `<title>` read
  from `src/lib/site.ts`, and the template's own lint config made to pass.
- `wrangler.jsonc` (the built Worker), `vitest.config.ts`, and
  `component.yaml` (`cloudflare-workers-assets-turbo`) with a smoke over
  `/`, `/demo/api/names` and a 404.
- Tests (vitest): the site's name, the todo store.
- The README: run, test, deploy; how each Vercel piece maps; the licence and
  the files changed.

Done when typecheck, lint, test and build are green, and `wrangler dev`
serves every route — the todos added through their POST server function and
read back with the visitor's cookie.

## TS2 — a baseline (TS-3)

sveltekit-boilerplate's machinery on this tree: the card, the build document
(one landing, `01-product`, then the record, `03-docs`), `.baseline/`
(identity, the site's README, task contracts), the rename engine, the
bootstrap helpers, the deployment-record renderer (probing `/`, the
server-functions demo and the API route), the phase pages, the context pack,
and the baseline's tests — with the end-to-end tier holding the committed
Worker config to the Vite plugin's, and walking every route of the staged
Worker, the server functions called as the browser calls them
(`testing/lib/serverfn-payload.mjs`). Done when every Baseline CI tier is
green; tagged `baseline-v1`.

## TS3 — scaffold, then live (TS-4)

orun.work (saas-orun-work WA5) builds an app from this baseline in two
stages, and an account with no Cloudflare connection stops after the first.
So the one landing splits where its needs change: `01-scaffold` places,
brands and lands the whole site with GitHub alone, parking stage's and prod's
push activation (`tooling/bootstrap/deploys.mjs`) so main's CI is green and
deploys nothing; `02-live` binds the late-bound workers.dev subdomain
(`tooling/bootstrap/subdomain.mjs`), restores the lanes, mints the Cloudflare
credentials and lands the deploy, watched and probed; `03-docs` records it.
The card declares `spec.stages` and `lateBound: true` on `subdomain`; the
stage Worker sends a `frame-ancestors` policy naming orun.work's origins.
Done when every Baseline CI tier is green — a full build ending on
`baseline-v1`'s tree, a code-only build taken live later ending on the full
build's — and Orunbase's manifest parser reads the card; tagged
`baseline-v2`.
