# 02-live — the site, live on stage and prod

The **live stage** (`blueprint.yaml` `spec.stages.live`): everything that
needs Cloudflare. A build with a Cloudflare connection runs it straight after
`01-scaffold`; a code-only site runs it whenever its account connects one
(`--resume`, which finds `01-scaffold` placed and runs what follows).

**Places** nothing. Its work is hooks: it takes what `01-scaffold` landed
live in one landing, whose convergence deploys the site to stage and prod.

**Requires** `01-scaffold` placed, and the Cloudflare connection live —
probed, and waited for up to ten minutes so a consent can be clicked while it
waits. The probe is asked once before the run's first phase and, if
Cloudflare is not there yet, again just before this one, so a build that has
no connection still lands its code first.

**Needs** the real workers.dev subdomain (`subdomain`, a late-bound input): a
console or orun.work build reads it from the Cloudflare connection; a
hand-run build passes `--set subdomain=…`. It may differ from the placeholder
a code-only scaffold recorded — that is what late-bound means — and the
`subdomain` hook refuses the placeholder itself.

## What runs

| hook | what it does |
|---|---|
| `subdomain` | binds the account's workers.dev subdomain where the placeholder stands: `apps/web/component.yaml` (the smoke's URL), `intent.yaml`'s environment URLs, `ai/context/operations.md`, and `.rebrand/values.json` last (`tooling/bootstrap/subdomain.mjs`). A site built with it from the start changes nothing; a site bound to another subdomain is refused (another account) |
| `deploys` | puts back stage's and prod's activation on a push to `main` |
| `promotion` | defers prod's wait on stage until `03-docs` (both environments deploy side by side) |
| `dev-lanes` | keeps dev's verify lane off main's convergences until `03-docs` |
| `retouch` | the redeploy marker on `apps/web/component.yaml` (`.baseline/tasks/02-live.TaskContract.yaml`'s `affects`) — the landing changes the component, so its merge deploys it, on the first run and on a re-run alike |
| `secrets` | `orun.integrations/reconcile@v1`, both keys in one hook, created side by side: `CLOUDFLARE_API_TOKEN` from the `workers-deploy` template (Workers Scripts, the site's deploy); `CLOUDFLARE_ACCOUNT_ID`, the connection fact. Keys that exist are kept |
| `task` | finds the phase's task and yields its key |
| `land` | one PR bound to the task, its commit checked in the box (`checks: local`) and merged without waiting for the PR's CI |
| `converge` (await) | `orun.run/watch@v1` on the merge commit's run, read every 5 s; resumes it up to three times |
| `verify` (await) | `orun.http/probe@v1` on both workers.dev URLs |

## What the convergence does

`orun plan --changed` plans `web` on stage and prod (deploy) and — dev's push
activation being deferred — nothing on dev. Each deploy lane installs the
workspace inside its own job tree, builds with `vite build` (Cloudflare's
Vite plugin writes `dist/server/index.js` and its chunks, and the browser's
files in `dist/client`, where `wrangler.jsonc`'s `main` and
`assets.directory` say), checks the build output, deploys
`<reponame>-web-<env>` with `wrangler deploy --config wrangler.jsonc`, and
smoke-tests it: the home page must carry the nav's server-functions link,
the API route must answer its JSON, and an unknown path must be TanStack
Router's not-found page with a 404, rendered by the Worker. Stage and prod
deploy side by side (this phase deferred the promotion gate).

Each lane's build is told its environment (`DEPLOY_ENV`, the component's
`environmentBuildVar`), and the stage Worker sends
`Content-Security-Policy: frame-ancestors` naming the origins that may frame
it — orun.work's preview pane among them (`apps/web/src/lib/framing.ts`).
Prod sends none.

## Verified

The convergence run for the merge commit is green, and
`https://<reponame>-web-{stage,prod}.<subdomain>.workers.dev` answer.

## Troubleshooting

| symptom | cause → fix |
|---|---|
| parks on the `providers` probe for cloudflare | Cloudflare is not connected to the workspace. Connect it (console → Integrations → Cloudflare, paste the Account API token); the site's code is already on main |
| `subdomain --bind: … was given the placeholder` | the build had no workers.dev subdomain. A console or orun.work build reads it from the connection — the account has none until one is set up in Cloudflare (Workers & Pages); a hand-run build passes `--set subdomain=…` |
| `subdomain --bind: this site is bound to … and was given …` | the build is bound to another Cloudflare account than the one the site was taken live on. Build with the original connection; moving a site between accounts is not a bootstrap step |
| `input conflict … subdomain: recorded "your-workers-subdomain"` | the live stage ran in the container that ran the scaffold, on an orun that predates late-bound inputs. Use an orun that reads `lateBound`, or a fresh container (the record is `.orun/`, which no checkout carries) |
| deploy lane: `secret resolution failed … CLOUDFLARE_API_TOKEN` | the reconcile did not run or minted against a revoked connection. Re-connect and re-run the phase; the reconcile re-mints only what is missing |
| deploy lane: Authentication error (10000) | the connection's token lacks Workers Scripts Write. Re-issue it with the permission groups the console's Connect recipe lists |
| smoke fails right after the FIRST deploy | workers.dev route propagation; the composition retries the first deploy and the smoke with backoff (stack-tectonic ≥ 0.19.0). A convergence resume clears what is left |
| `build-app` fails resolving a dependency, or `wrangler` is not found | the job's install did not run inside its tree. The site's `intent.yaml` pins stack-tectonic 0.19.0, where it does; a bump changes the install's layout — `intent.yaml`'s comment says why it is pinned |
| the watch says green, the probe says 404 | another workflow ran on the push and the watch took its run. Only `ci.yml` may run on a push to main |
| the convergence failed AFTER the PR merged | the files are on main. Re-run the phase (`--phase 02-live`, `--redo 02-live` under `--resume`, or the console's Retry): `retouch` gives the landing a new diff and the site redeploys |
| re-run lands nothing | the hooks did not run (`--run-hooks`), or the contract names no component — `node tooling/bootstrap/retouch.mjs --check --affects .baseline/tasks/02-live.TaskContract.yaml` in the site's tree says which |
