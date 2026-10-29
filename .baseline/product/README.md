# tanstack-start

A TanStack Start site — the welcome page, a todo list kept by server
functions in the visitor's own cookie, an API route, and the three SSR modes
(full, data-only and SPA) — on **Cloudflare Workers + Static Assets**, built
by [Cloudflare's Vite plugin](https://developers.cloudflare.com/workers/vite-plugin/),
TanStack Start's own Cloudflare target.

## Live deployment

<!-- 03-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace and the secrets the site uses into
[ai/context/deployment.md](ai/context/deployment.md); how the site deploys
and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 03-docs:end -->

## What is here

| Surface | Where |
|---|---|
| The site's name (every page's `<title>`) | `apps/web/src/lib/site.ts` |
| `/` (the welcome page), `/demo/start/server-funcs` (todos through a GET and a POST server function), `/demo/start/api-request` (a page that fetches the API route), `/demo/start/ssr/*` (full SSR, data-only, SPA mode) | `apps/web/src/routes` |
| The API route: `GET /demo/api/names` | `apps/web/src/routes/demo/api.names.ts` |
| The todo store: the visitor's list in one httpOnly cookie | `apps/web/src/data/todos.ts` |
| The header and its navigation | `apps/web/src/components/Header.tsx` |
| Workers build and deploy contract | `apps/web/vite.config.ts`, `apps/web/wrangler.jsonc`, `apps/web/component.yaml` |
| Tests (the site's name, the todo store) | `apps/web/src/**/*.test.ts` (vitest) |

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

Make the site yours in `apps/web/src/routes` (the pages; TanStack Router
writes `src/routeTree.gen.ts` from them) and `apps/web/src/lib/site.ts` (its
name). The site needs no environment variable and no secret.

The server-functions demo keeps each visitor's list in their own browser:
one httpOnly cookie holding the list as JSON — no database and no third
party. A cookie holds about 4 KB, so the list is capped (50 todos of up to
100 characters, and a todo that would not fit is refused with a message). To
share a list across devices, swap `readTodos` and the `setCookie` call in
`apps/web/src/routes/demo/start.server-funcs.tsx` for a KV namespace bound in
`apps/web/wrangler.jsonc`.

## How it deploys

Merges to `main` converge through Orun: `.github/workflows/ci.yml` plans the
changed components and runs each lane against the workspace in
`intent.yaml`. The site deploys to `stage`, then to `prod` once stage has
converged on the same commit; `dev` only verifies. The Worker is
`tanstack-start-web-<env>` on your account's workers.dev subdomain, and
every deploy is smoke-tested over HTTP. A pull request runs the same
pipeline's verify lanes: the site built and dry-deployed for each
environment, with nothing deployed. They do not lint or run the tests, so
run `pnpm typecheck`, `pnpm lint` and `pnpm test` before you push. (A push
to `main` builds, deploys and smoke-tests.)

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare token and account id are brokered per run from the workspace's
Cloudflare connection; nothing provider-shaped is stored in the repository
or in GitHub.

**Deploy by hand.** Orunbase's **Deploy** button on a component, or **Run
workflow** on the CI workflow in GitHub's Actions tab (on `main`), runs
`ci.yml` for the environment and components you pick, and each one deploys
exactly as a merge would deploy it. Leave the component blank to redeploy
every component in that environment, with nothing changed: after rotating a
secret, say. A component with nothing to run in that environment (a test
suite in `prod`) is left out with a notice.

## Custom domain

The site answers on workers.dev from its first deploy. To serve it on your
own domain, add the domain to the Cloudflare account the site deploys into
and attach it to the Worker (dashboard → Workers & Pages →
`tanstack-start-web-prod` → Settings → Domains & Routes → Add → Custom
domain). Do the same for stage with a subdomain if you want one.

Nothing else has to change: the site builds no absolute links, so it answers
on whatever origin serves it, and TanStack Start's server functions check a
request's `Origin` against the host it arrived on. The repository names the domain in
one place, `BASE_DOMAIN` in `intent.yaml` (dev, stage and prod), which the
site was born with as the reserved placeholder
`tanstack-start.example.com`. Replace it with your domain in the same
change that records it.
