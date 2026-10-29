# tanstack-start

Vercel's [TanStack Start template](https://github.com/vercel/vercel/tree/main/examples/tanstack-start)
— the welcome page, a todo list kept by server functions, an API route, and
the three SSR modes (full, data-only and SPA) — running on **Cloudflare
Workers + Static Assets** through
[Cloudflare's Vite plugin](https://developers.cloudflare.com/workers/vite-plugin/),
TanStack Start's own Cloudflare target, deployed by
[Orun](https://github.com/sourceplane/orun) to stage and prod on every merge.
Packaging it as an Orun baseline is the next milestone (TS2).

Swapping Vercel's Nitro build for Cloudflare's Vite plugin is the port; the
todo list moving from a `todos.json` on the server's disk into the visitor's
own cookie, and TanStack Start's move from 1.133 to 1.169, are the rest of
the diff, and every move is recorded. See
[`specs/epics/tanstack-start`](specs/epics/tanstack-start/README.md)
for the design, the milestones and the as-built status.

## What is here (the site)

| Surface | Where |
|---|---|
| The site's name (every page's `<title>`) | `apps/web/src/lib/site.ts` |
| `/` (the welcome page), `/demo/start/server-funcs` (todos through a GET and a POST server function), `/demo/start/api-request` (a page that fetches the API route), `/demo/start/ssr/*` (full SSR, data-only, SPA mode) | `apps/web/src/routes` |
| The API route: `GET /demo/api/names` | `apps/web/src/routes/demo/api.names.ts` |
| The todo store: the visitor's list in one httpOnly cookie | `apps/web/src/data/todos.ts` |
| The header and its navigation | `apps/web/src/components/Header.tsx` |
| Vite plugins, Worker config, deploy contract | `apps/web/vite.config.ts`, `apps/web/wrangler.jsonc`, `apps/web/component.yaml` |
| Tests (the site's name, the todo store) | `apps/web/src/**/*.test.ts` |

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

One Worker config, `apps/web/wrangler.jsonc`, serves both sides: the Vite
plugin reads it (with the source entry, TanStack Start's
`@tanstack/react-start/server-entry`, named in `vite.config.ts`), and it
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
| `ci.yml` | the Orun pipeline, and the only workflow a site carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the site built and dry-deployed per environment; they do not typecheck, lint or run the tests), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone is the check; a merge deploys stage → prod. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
