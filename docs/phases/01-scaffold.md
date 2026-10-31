# 01-scaffold — the site's code, landed

The **scaffold stage** (`blueprint.yaml` `spec.stages.scaffold`): everything
that needs GitHub and nothing else. A build that stops here
(`--until 01-scaffold`; the platform's `until: scaffold`) leaves a
**code-only** site: its repository, its CI and its pull requests' checks all
work, and nothing is deployed anywhere.

**Places** the whole tree: the root manifests (`intent.yaml`, `package.json`,
the pnpm workspace and lockfile, `turbo.json`),
`.github/workflows` (`ci.yml` — the baseline's own `baseline.yml` and
`tag.yml` are ignored), the shared TypeScript/ESLint
config and the wrangler renderer, the site's README and its two context
pages, the identity file `.rebrand/values.json`, `.gitkeep` files for the
four discovery roots, and `apps/web` — the TanStack Start site, its
Cloudflare Vite plugin build, its deploy contract and its tests (vitest, run
inside the app).

**Requires** nothing a probe can see. GitHub is proven by the repository's
link to the workspace, which `link` checks before the landing: the platform
sees a pull request only through the GitHub App installation on the account
that owns the repository, and a linked repository is one it sees. (A
connection probe would read the workspace's own connection list, which never
shows the platform connection a repository in orun.work's managed GitHub org
is linked through.) Cloudflare is `02-live`'s to ask for.

The subdomain is late-bound: without one (a code-only build), the identity
file and the tree carry the placeholder `your-workers-subdomain`, and
`02-live` binds the real value before anything deploys.

## What runs

The run's task set-up — the epic, the three milestones, the three tasks —
runs in the background from the start (`background: true`), so every hook up
to `task` runs beside it; `task` is the first that waits for it.

| hook | what it does |
|---|---|
| `git-init`, `git-stage` | the rebrand enumerates with `git ls-files`, so the tree is a staged repo first |
| `rebrand` | renames the baseline's identity to the site's over the whole tree (`tooling/rebrand/rebrand.mjs`) |
| `orun-workspace` | writes the site's workspace into `intent.yaml` (`ws_SET_ME` if there is none — loud, not silent) |
| `work-tree` | removes the baseline's own `work:` block from `intent.yaml` — `specs/` and `tasks/` do not ship |
| `deploys` | parks stage's and prod's activation on a push to `main` until `02-live` (`tooling/bootstrap/deploys.mjs`) — a merge plans dev's verify lane and deploys nothing |
| `git-restage`, `rebrand-verify` | refuses the landing if any baseline identity is left |
| `repo` | `orun.repo/ensure@v1` — creates `githuborg/reponame` (private unless `repoPrivate=false`), or finds it |
| `link` | `orun cloud link` (best effort) then `orun cloud check` — an unlinked repo stops here |
| `task` | finds the phase's task (opened by the run-level list) and yields its key — waiting, if it must, for the background set-up |
| `land` | one PR bound to the task, its commit checked in the box first (`checks: local`: `orun validate`, then `orun plan` as the PR and as the merge would plan it, under a second); merged without waiting for the PR's CI |

Nothing is awaited: the merge deploys nothing, so there is no convergence to
watch.

## What CI on main does with it

`orun plan --changed` for the merge plans `web` on **dev** with the verify
profile — the site built and dry-deployed, no credential — and nothing on
stage or prod, whose push activation is parked. The run is green and deploys
nothing. Parking all three would not do: orun refuses a push plan that no
environment answers, and the run would be red.

Every later merge of a code-only site is the same, and every pull request
runs the verify lanes on dev, stage and prod. A manual deploy (Orunbase's
Deploy button, or **Run workflow** with an environment) of stage or prod is
refused by `orun plan` — `environment stage is not activated by trigger
github-push-main` — until `02-live` has run: there is no credential to deploy
with.

## Verified

The repository exists and is linked to the workspace, and the site is on
`main`, branded. The landing's own check planned the merge before it was
pushed.

## Troubleshooting

| symptom | cause → fix |
|---|---|
| `link` fails: `… is not linked to workspace` | the credential cannot write links and the platform has not linked the repo — or the GitHub App is not installed on `githuborg`. Install it (console → Integrations → GitHub), allow-list the repo (console → Settings → Git repos) and re-run the phase |
| `land`: `the landing's own check failed — orun plan for …` | the placed tree does not plan; the next line is orun's error. Nothing was pushed. Fix it and re-run the phase |
| `rebrand-verify` lists leftovers | a file carries an identity form no rule renames. Add a rule to `tooling/rebrand/rebrand.mjs` (and a case to `testing/rebrand.test.sh`) |
| `intent.yaml` says `workspace: ws_SET_ME` | `orunWorkspace` was empty and the build ran outside a workspace. Set it and re-run |
| the site deploys nothing after a merge | expected while it is code only: `intent.yaml` carries two `# @deploys-deferred:…` markers. Run `02-live` |
