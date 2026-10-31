# tanstack-start — operating contract (for humans and agents)

This is the standing guide to how this site is deployed and operated.
Instance facts (live URLs, workspace, the secrets it uses) live in
[deployment.md](deployment.md), rendered from probed reality by the
bootstrap's `03-docs` phase; this file is the contract that stays true
between deployments. It is written to give an agent with repository read
access enough context to reason about and operate the site without any
other source.

## What this system is

A TanStack Start site on Cloudflare alone, expressed as an Orun
component-native desired-state repo.

- **`apps/web`** — the site: TanStack Start built by Cloudflare's Vite plugin
  (`@cloudflare/vite-plugin`) into one Worker (`dist/server/index.js` and its
  chunks) plus Static Assets (`dist/client`: the hashed JS and CSS, and
  `public/`). The Worker renders every page, runs the server functions
  (`/_serverFn/…`, which refuse a request from another origin) and the API
  route (`/demo/api/names`), and answers an unknown path with TanStack
  Router's not-found page and a 404. The server-functions demo keeps each
  visitor's todos in their own httpOnly cookie (`src/data/todos.ts`: JSON,
  capped at 50 todos of 100 characters and refused past ~3.8 KB). There is
  no database, no third-party service and no runtime secret. The site's
  tests (vitest) live in `apps/web` and run with `pnpm test` — by hand,
  before a push: `ci.yml`'s lanes do not lint or run them.
- **`tooling/*`** — shared TypeScript and ESLint configuration, and the
  deploy-time wrangler renderer for workers that take wiring.

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and dry-deploy, nothing deploys.

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. `apps/web` builds once per environment (`vite build`; the Vite plugin
   writes the Worker and the assets where `wrangler.jsonc`'s `main` and
   `assets.directory` say), then `wrangler deploy --config wrangler.jsonc`
   ships `tanstack-start-web-<env>` and a smoke test fetches `/` (the nav
   must be there), the API route (its JSON) and an unknown path (the
   not-found page, with a 404).
4. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
5. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "site
  converged"; probe the URLs instead.
- A change to `intent.yaml`'s `environments` maps to no component and
  redeploys nothing on its own. Land it with a change under `apps/web`.
- A visitor's todos are theirs alone and live in their browser: clearing
  cookies clears the list, and nothing server-side can read or restore it.
- **Code only until it goes live.** If `intent.yaml` carries
  `# @deploys-deferred:…` markers under `stage` and `prod`, the site was
  built before its Cloudflare account was connected: merges plan dev's verify
  lane and deploy nothing, and a manual deploy of stage or prod is refused
  (`environment … is not activated by trigger github-push-main`). The
  build's live stage puts the triggers back, binds the account's workers.dev
  subdomain and deploys; do not restore them by hand without the deploy
  credentials it mints.
- **Who may frame the site.** On stage, every response the Worker renders
  carries `Content-Security-Policy: frame-ancestors …` naming the origins
  that may show it in an iframe (orun.work's preview pane among them); prod
  and dev send none. The list is `apps/web/src/lib/framing.ts`, one entry
  per environment. The Worker knows its environment from `DEPLOY_ENV`,
  which each deploy lane exports to its build (`environmentBuildVar` in
  `apps/web/component.yaml`): a build by hand names none and sends no
  policy.

## Secrets model

- **Brokered provider secrets**: `CLOUDFLARE_API_TOKEN` (Workers deploy
  scope) and `CLOUDFLARE_ACCOUNT_ID` — pointers minted per run from the
  workspace's Cloudflare connection. No long-lived values at rest; nothing
  to rotate by hand.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.
- The site needs no runtime secret and no build-time variable.

## Verifying the system

```bash
# the site on each environment (also recorded, probed, in deployment.md)
curl -s -o /dev/null -w '%{http_code}\n' https://tanstack-start-web-stage.your-workers-subdomain.workers.dev/
curl -s https://tanstack-start-web-prod.your-workers-subdomain.workers.dev/demo/api/names

# workspace readiness (integrations + repository link)
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| change a page | edit `apps/web/src/routes/…`, merge |
| rename the site | edit `SITE_NAME` in `apps/web/src/lib/site.ts`, merge |
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| deploy by hand | Orunbase's Deploy button, or `gh workflow run ci.yml --ref main -f environment=<env> [-f component=<a,b>]` — the named components (blank: every one) run in that environment as a merge runs them; started off `main` it is refused |
| redeploy without a change | edit the last line of `apps/web/component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| change who may frame the site | edit `FRAME_ANCESTORS` in `apps/web/src/lib/framing.ts` (CSP source expressions, per environment) and merge; each environment sends it from its next deploy |
| serve a custom domain | attach it to the Worker in Cloudflare (README, "Custom domain"), then replace the placeholder `tanstack-start.example.com` in `intent.yaml`'s `BASE_DOMAIN` (dev, stage and prod) with it; nothing else changes |
| share todos across devices | swap the cookie in `apps/web/src/routes/demo/start.server-funcs.tsx` (`readTodos`, `setCookie`) for a KV namespace bound in `wrangler.jsonc` |
| add a runtime secret | `orun secrets set <KEY> --org <ws> --env <env>` |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `03-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 03-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

Structural changes (a second Worker, an API, a data store) follow the same
contract that deployed the site: add a component under `apps/`, `infra/` or
`packages/` with a `component.yaml`, land it as a pull request, and the
convergence run applies it.
