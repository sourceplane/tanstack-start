# tanstack-start

Vercel's [TanStack Start template](https://github.com/vercel/vercel/tree/main/examples/tanstack-start)
— the welcome page, a todo list kept by server functions, an API route, and
the three SSR modes (full, data-only and SPA) — running on **Cloudflare
Workers + Static Assets** through
[Cloudflare's Vite plugin](https://developers.cloudflare.com/workers/vite-plugin/),
TanStack Start's own Cloudflare target, and packaged as an **Orun baseline**:
one command takes a new site from nothing to live on stage and prod, in its
own repository, under its own name.

Swapping Vercel's Nitro build for Cloudflare's Vite plugin is the port; the
todo list moving from a `todos.json` on the server's disk into the visitor's
own cookie, and TanStack Start's move from 1.133 to 1.169, are the rest of
the diff, and every move is recorded. What the baseline adds is everything
needed to make a copy of it somebody else's — built the way
[cirrus-baseline](https://github.com/sourceplane/cirrus-baseline) is. See
[`specs/epics/tanstack-start`](specs/epics/tanstack-start/README.md)
for the design, the milestones and the as-built status.

## Instantiating a site

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/tanstack-start
cd tanstack-start
orun new --blueprint repo-blueprint.yaml --out ~/sites/acme-notes --run-hooks --resume \
  --set reponame=acme-notes --set productname="Acme Notes" \
  --set githuborg=acme-inc --set subdomain=<workers-dev-subdomain>
```

Or, once the platform's registry lists it, from the Orun console (Baselines →
`tanstack-start` → Build), or from orun.work. Three phases, in two stages,
each landing one pull request in the new repository:

| stage | phase | needs | lands |
|---|---|---|---|
| scaffold | `01-scaffold` | GitHub | the repository created and linked, then the whole site in one pull request, its deploy lanes parked — CI on `main` is green and deploys nothing |
| live | `02-live` | Cloudflare | the workers.dev subdomain bound, the deploy credentials minted, the lanes put back — deployed to stage and prod and smoke-tested |
| | `03-docs` | — | the live deployment recorded, the promotion gate put back |

A build with no Cloudflare connection stops after the scaffold
(`--until 01-scaffold`) and the site is **code only**; a later build takes it
live (`--resume` with the account's `subdomain`). The card declares the split
(`blueprint.yaml` `spec.stages`) and the one input that waits for it
(`subdomain`, `lateBound`). **[BOOTSTRAP.md](BOOTSTRAP.md)** is the operator
guide; [docs/phases/](docs/phases/README.md) has a page per phase.

The new repository receives the **site only** — the app and its tests, its
CI, its tooling, a README of its own and its operating contract — renamed
throughout to the site's name, repository and Cloudflare Worker. None of this
repository's machinery ships.

| What makes it a baseline | Where |
|---|---|
| The console card (inputs, secrets, programme) | `blueprint.yaml` |
| The build document (modules, phases, hooks) | `repo-blueprint.yaml` |
| This tree's identity, and the bootstrap's task contracts | `.baseline/` |
| The rename engine | `tooling/rebrand/rebrand.mjs` |
| The bootstrap's helpers (deferrals — the deploy lanes, prod's gate, dev's lanes — the late-bound subdomain, redeploy marker, work-tree strip) | `tooling/bootstrap/` |
| The deployment-record renderer | `hooks/render-deployment-docs.sh` |
| The site's README and context pack | `.baseline/product/README.md`, `ai/context/` |
| The baseline's tests: contract, leak, offline bootstrap (full and code-only), end to end | `testing/`, `.github/workflows/baseline.yml` |
| Cutting a `baseline-vN` tag | `.github/workflows/tag.yml` |

## What is here (the site)

| Surface | Where |
|---|---|
| The site's name (every page's `<title>`) | `apps/web/src/lib/site.ts` |
| `/` (the welcome page), `/demo/start/server-funcs` (todos through a GET and a POST server function), `/demo/start/api-request` (a page that fetches the API route), `/demo/start/ssr/*` (full SSR, data-only, SPA mode) | `apps/web/src/routes` |
| The API route: `GET /demo/api/names` | `apps/web/src/routes/demo/api.names.ts` |
| The todo store: the visitor's list in one httpOnly cookie | `apps/web/src/data/todos.ts` |
| The header and its navigation | `apps/web/src/components/Header.tsx` |
| Vite plugins, Worker config, deploy contract | `apps/web/vite.config.ts`, `apps/web/wrangler.jsonc`, `apps/web/component.yaml` |
| The Worker's entry: TanStack Start's handler, plus who may frame the site (on stage: orun.work's preview pane) | `apps/web/src/server.ts`, `apps/web/src/lib/framing.ts` |
| Tests (the site's name, the todo store, the framing policy) | `apps/web/src/**/*.test.ts` |

## Getting started

```bash
pnpm install
pnpm typecheck        # tsc
pnpm lint             # biome lint
pnpm test             # vitest
pnpm build            # vite build → apps/web/dist/server (the Worker) + dist/client (the browser's files)
```

```bash
pnpm --filter @app/web dev        # http://localhost:3000, the server in workerd
pnpm --filter @app/web preview    # wrangler dev over the built Worker
```

The todo list keeps each visitor's list in their own browser: one httpOnly
cookie holding the list as JSON (base64url-encoded), capped at 50 todos of
up to 100 characters and refused past ~3.8 KB so it stays under a browser's
4 KB cookie limit. The template wrote the list to a `todos.json` beside the
server with `node:fs`; a Worker has no disk that outlives a request (and
Vercel's functions none they can write), and a cookie needs no database
while keeping the demo's point: a GET server function read in a loader, a
POST one that changes what it reads. To share a list across devices, swap
the cookie for a KV namespace.

**Framing.** The stage Worker answers every page it renders with
`Content-Security-Policy: frame-ancestors 'self'
https://orun.work https://stage.orun.work
https://orun-agent-web-stage.oruncloud.workers.dev
https://orun-agent-web-prod.oruncloud.workers.dev http://localhost:*` —
orun.work's preview pane shows a site's stage deploy in an iframe, and
`localhost` on any port is orun.work run for its development. Prod and dev
send no policy, so they frame exactly as before. The list is a map per
environment in `apps/web/src/lib/framing.ts`; change it there. The Worker
knows its environment because each deploy lane exports `DEPLOY_ENV` to its
build (`environmentBuildVar` in `component.yaml`, passed through by
`apps/web/turbo.json`), and `vite.config.ts` writes it into the bundle; a
local build or `vite dev` names none and sends no policy
(`DEPLOY_ENV=stage pnpm build` builds the stage Worker).

One Worker config, `apps/web/wrangler.jsonc`, serves both sides: the Vite
plugin reads it (with the source entry, `src/server.ts` — TanStack Start's
`@tanstack/react-start/server-entry` with the framing policy — named in
`vite.config.ts`), and it
describes the BUILT Worker — `dist/server/index.js` and its chunks, uploaded
as built, and `dist/client` as Static Assets — for the deploy lane's
`wrangler deploy --config wrangler.jsonc`, which never reads the build's own
redirect. `testing/e2e.test.sh` holds the two to each other: the config the
plugin writes beside the build and this file name the same Worker, and
dry-run deploys of both upload the same modules.

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Nitro (`nitro/vite`), building for Vercel's functions | `@cloudflare/vite-plugin`: the Worker at `dist/server/index.js`, the browser's files in `dist/client` |
| Server functions and the API route in a Vercel function | The same routes in the Worker (`nodejs_compat`), behind TanStack Start's own `Origin` check |
| The todos in `todos.json` beside the server (`node:fs`) | The visitor's own httpOnly cookie (`apps/web/src/data/todos.ts`) |
| `public/` and the hashed client build on Vercel's CDN | Static Assets ahead of the Worker (`assets.directory`) |
| Deploy on push | Orun deploys `<repo>-web-{stage,prod}` on merge to `main` (`apps/web/component.yaml`) |
| "Deploy with Vercel" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, deployed |

## CI

| Workflow | What it runs | Ships to a site |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow a site carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the site built and dry-deployed per environment; they do not typecheck, lint or run the tests), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone is the check; a merge deploys stage → prod (until a site goes live, its deploy lanes are parked and a merge verifies on dev and deploys nothing). It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
| `baseline.yml` | the baseline's own tiers: contract tests, the blueprint read by the pinned orun, the leak gate, the offline bootstrap, the site installed, type-checked, linted, tested, built, dry-deployed and served (`testing/e2e.test.sh`, before every tag) | no |
| `tag.yml` | cuts a `baseline-vN` tag (manual) | no |
