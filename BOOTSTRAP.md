# BOOTSTRAP — a new site from this baseline, in phases

How to go from **nothing** to a **TanStack Start site live on stage and prod,
documented**, with ONE provider consent — or, with no provider at all yet, to
the site's **code**, in its own repository, ready to go live later.

There is one artifact: **`repo-blueprint.yaml`**. It declares what to place,
in what order, what each phase needs first, and what to say while it runs.
`orun new` is the whole runtime — the phases below are its `--phase` names,
not separate workflows. The console card the platform renders is
**`blueprint.yaml`**; it names the build document and states the inputs, the
brokered secrets, the programme and the two stages a build may stop between,
and `testing/manifest.test.sh` holds it to what the build document does.

**Two stages** (`blueprint.yaml` `spec.stages`): the **scaffold**,
`01-scaffold`, needs GitHub only — the whole site placed, branded and landed
in a new repository, its deploy lanes parked so CI on `main` is green and
deploys nothing; the **live** stage, `02-live`, needs Cloudflare — the
workers.dev subdomain bound, the deploy credentials minted, the lanes put
back, one landing deployed to stage and prod, watched and probed. Then
`03-docs` records it. A build runs all three unless told to stop after the
scaffold, which is what an account with no Cloudflare connection gets: a
**code-only** site.

Target wall-clock: **about five minutes** for a full build — an estimate
summed from the phases (1 + 3 + 1) until a bootstrap measures it. The shape:
the task set-up in the background while the scaffold's landing is placed,
branded and checked in the box (`orun validate` and `orun plan`, no runner
waited for) and merged with nothing to deploy; then the live landing, whose
merge builds the site once per environment (seconds, not minutes — the long
poles are the installs, the runners and a first deploy's workers.dev route)
and deploys stage and prod side by side; then a short docs landing, checked
the same way, that restores the promotion gate. It is unmeasured: no live
bootstrap of this baseline has run yet. The sibling site baselines measured
7m07s–8m43s from the console's Build over three landings; the one-landing
shape this replaced (`baseline-v1`'s `01-product`, cirrus-baseline
baseline-v22's) dropped a landing and the Checks waits, and orun v2.88.0's
fast shape took about a minute out of turso-starter's measured build — the
same minute is assumed here. The split pays for one landing back (the
scaffold's: about a minute) and nothing else: its merge deploys nothing, so
no convergence is waited on twice.

## 0. What you need

- GitHub org access (repository creation) and a machine with `git`, `node`
  (≥ 22), `pnpm` (10.12.1), `python3` with PyYAML, `curl`, and the `orun`
  CLI **≥ v2.88.0** — the floor for RUNNING the bootstrap (the phase overlay,
  landings that commit per phase, a probe deferred until the phase that
  needs it, `from: workspace`, the deploy credentials minted in one
  `secrets` reconcile, the task set-up run in the background
  (`background: true`), and landings checked in the box before they merge
  (`checks: local`)). A code-only site taken live **in the container that
  built its scaffold** also needs the orun that reads `lateBound` (v2.90.0):
  older ones refuse the real subdomain as an input conflict with the
  placeholder they recorded (a fresh container has no record, and works on
  the floor). The site's own `ci.yml` pins its lanes separately (v2.78.4).
- For the live stage: a Cloudflare account (the free plan is enough for one
  Worker with static assets) and its **Account API token** with Workers
  Scripts Write (the console's Connect recipe lists the exact permission
  groups). It is the ONLY provider credential this baseline needs, and the
  scaffold stage does not need it at all.
- An Orun Cloud workspace for the site — `orunWorkspace`, or the workspace
  the build runs in (ORUN_WORKSPACE) when that is unset — with an
  **admin-role API key** for headless runs (secret writes below admin are
  masked as `not_found`).
- **The repository allow-listed in the workspace** (console → Settings → Git
  repos), unless the credential can write links. `01-scaffold`'s `link` step
  stops and names the fix if it is not — it is the build's GitHub check: a
  linked repository is one the platform sees through the GitHub App, and the
  scaffold asks for no connection row (a repository in orun.work's managed
  GitHub org has none in the workspace).

## 1. One command: `--resume`

The whole bootstrap, unattended. `--resume` places every phase not already
derived as done, in order, honouring each phase's barrier:

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/tanstack-start
cd tanstack-start

orun new --blueprint repo-blueprint.yaml \
  --out ~/sites/acme-notes --run-hooks --resume \
  --set reponame=acme-notes --set productname="Acme Notes" \
  --set githuborg=acme-inc \
  --set orunWorkspace=ws_XXXXXXXX \
  --set subdomain=<workers-dev-subdomain>
```

`subdomain` is the workers.dev subdomain of the Cloudflare account you deploy
into (Workers & Pages → your subdomain). A build started from the console, or
with `orun baseline new --from bst_…`, never asks for it: the platform reads
it from the workspace's Cloudflare connection, the same one the deploy token
is minted from. Only a hand-run build like this one passes it.

**Code only, then live.** With no Cloudflare account yet, stop after the
scaffold and leave the subdomain out — it is **late-bound**, and the tree
carries the placeholder `your-workers-subdomain` until the site goes live:

```bash
orun new --blueprint repo-blueprint.yaml \
  --out ~/sites/acme-notes --run-hooks --until 01-scaffold \
  --set reponame=acme-notes --set productname="Acme Notes" \
  --set githuborg=acme-inc --set orunWorkspace=ws_XXXXXXXX
```

The repository, its CI (dev's verify lane on every merge; every lane on a
pull request) and its pull requests all work; nothing deploys. To go live,
run the same `--resume` command as above, with the account's `subdomain`:
it finds `01-scaffold` placed and runs `02-live` and `03-docs`. (This is what
the platform's go-live does: a resume with no stop.) Only a run that stops
before the last phase may keep the placeholder — the orun that reads
`lateBound` refuses any other before it writes a byte, and `02-live`'s
`subdomain` hook refuses it on any orun.

**`--run-hooks` is the difference between placing files and bootstrapping a
site.** Without it `orun new` writes the tree and stops: no repository, no
landing, no convergence watch, no probe. That is deliberate — it is what
makes the offline bootstrap in `testing/` possible with no workspace and no
provider.

`--resume` is safe to re-run from anywhere, a fresh container with a fresh
`--out` included: **phase state is derived from the tree, never stored.** A
phase whose files are present but branded derives as `drifted`, and
`--resume` leaves it placed rather than reverting the site's identity.

## 1b. Or phase by phase

| stage | phase | what it lands | verified by |
|---|---|---|---|
| scaffold | `01-scaffold` | the repository, created and linked; then the whole site in one PR — intent, CI, tooling, identity, `apps/web` (the site and its tests) — with stage's and prod's deploy lanes parked | its commit validated and planned in the box (as the PR and as the merge), then merged; main's run plans dev's verify lane and deploys nothing |
| live | `02-live` | the workers.dev subdomain bound; the deploy lanes put back; the brokered Cloudflare secrets; one PR whose merge deploys | the convergence green (build, deploy, smoke) and both workers.dev URLs answering |
| | `03-docs` | `ai/context/deployment.md` from probed facts; prod's promotion gate and dev's push lanes restored | the render's own probes, recorded; the commit checked in the box and merged |

```bash
orun new --blueprint repo-blueprint.yaml --out ~/sites/acme-notes --run-hooks \
  --until 01-scaffold --values ~/acme-notes.values.yaml
# … then --phase 02-live (with the subdomain), then --phase 03-docs
```

The first phase is selected with `--until`: it selects the same one phase, and
it is the selection that may run without the late-bound subdomain.

Every later phase reads the identity back from `.rebrand/values.json` in the
placed tree, but the blueprint's **required** inputs — `reponame`,
`productname`, `githuborg` — are validated before anything runs, so pass them
every time (a `--values` file is easier). The domain is not one of them: the
site goes live on workers.dev, and `productdomain` defaults to empty, which
brands the reserved placeholder `<reponame>.example.com` into `BASE_DOMAIN`
for an owner to replace when they attach a domain (README, "Custom domain").
Pass `--set productdomain=` only for a site that already has its domain.
The full guide, one page per phase: [docs/phases/README.md](docs/phases/README.md).

| flag | what it does |
|---|---|
| `--status` | derives and prints every phase's state and writes nothing. It parses the document, validates each hook against the action registry and compiles every template; it needs no credential and no network |
| `--phase <name>` | places exactly that phase; its `requires.phases` still gates |
| `--until <name>` | places every phase through that one and stops — `--until 01-scaffold` is a code-only build |

What lands in the site is PRODUCT-ONLY: the app (its tests inside it), its
CI, its tooling, its README and its two context pages. None of this
repository's machinery (`.baseline/`, the blueprints, `tooling/rebrand`,
`tooling/bootstrap`, `hooks/`, `testing/`, `docs/phases/`, `specs/`,
`tasks/`, this file) ships, nor does `tooling/migrations` (the D1 manifest
check for a database the site does not have). That promise is a test:
`testing/leak.test.sh` derives what every phase would place and gates the
set, and `testing/placement.test.sh` gates the same rules over a placed,
branded tree.

## 2. Headless / container mode

The blueprint's source is this repository (`sources: [{kind: dir, path: .}]`),
so the container contract is a shallow clone at a pinned tag plus two
tokens:

```bash
export ORUN_TOKEN=…          # orun auth, headless
export GITHUB_TOKEN=…        # fine-grained PAT (below)

git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/tanstack-start
cd tanstack-start
orun new --blueprint repo-blueprint.yaml \
  --out /work/acme-notes --run-hooks --resume --progress json \
  --values /work/acme-notes.values.yaml
```

| requirement | detail |
|---|---|
| `GITHUB_TOKEN` | fine-grained PAT: **read** on this repository; on the SITE's repository **contents write**, **pull-requests write**, **actions read+write** (`orun.run/watch@v1` resumes runs with `gh run rerun`), **checks read**; **repository create** on the owner if `01-scaffold` creates it (or pre-create it — supported) |
| classic token caveat | a classic PAT or gh OAuth token also needs the `workflow` scope to push `.github/workflows/` |
| pinning | the clone's `--branch <tag>` pins everything: the blueprint, its modules and its hooks' scripts all come from that one commit |

## 3. After the site is live

- **Write**: the pages are `apps/web/src/routes/` (TanStack Router writes
  `src/routeTree.gen.ts` from them); the site's name is
  `apps/web/src/lib/site.ts`. Every merge to `main` redeploys.
- **Framing**: the stage Worker sends `Content-Security-Policy:
  frame-ancestors 'self' https://orun.work https://stage.orun.work
  https://orun-agent-web-stage.oruncloud.workers.dev
  https://orun-agent-web-prod.oruncloud.workers.dev http://localhost:*`, so
  orun.work's preview pane (and orun.work run locally) can show the stage
  deploy in an iframe; prod and dev send no policy. The list is one map in
  `apps/web/src/lib/framing.ts`, per environment; each lane's build is told
  its environment (`DEPLOY_ENV`, `environmentBuildVar` in
  `apps/web/component.yaml`), so a change reaches an environment with its
  next deploy.
- **The todos**: each visitor's list lives in their own httpOnly cookie
  (`apps/web/src/data/todos.ts`), so the site depends on no third party. To
  share a list across devices, swap the cookie for a KV namespace.
- **Custom domain**: attach it to the Worker in Cloudflare, and replace the
  placeholder `<reponame>.example.com` in `intent.yaml`'s `BASE_DOMAIN` with
  it (the site's README, "Custom domain"); nothing else changes, because the
  site builds no absolute links. There is no domain phase: attaching a domain
  needs zone permissions the brokered `workers-deploy` token does not carry.
- **Refresh the record**: re-run `--phase 03-docs`; it is idempotent.

## 4. Testing this baseline

`.github/workflows/baseline.yml` runs three tiers on every pull request, and
each runs locally the same way:

```bash
for t in manifest phases coverage rebrand retouch bootstrap-defer subdomain; do bash testing/$t.test.sh; done
bash testing/leak.test.sh        # needs orun
bash testing/placement.test.sh   # needs orun, node, pnpm: the offline bootstrap
bash testing/e2e.test.sh         # + network for pnpm: the site built, dry-deployed and served
```

The offline bootstrap (`testing/lib/bootstrap.sh`) places every phase in
order and finishes each with the blueprint's OWN `run:` hooks — read out of
`repo-blueprint.yaml`, not transcribed — so the rebrand, the re-tenant, the
deferrals and their restore, the subdomain bound, the retouch marker and the
deployment record all run exactly as a real bootstrap runs them. The
placement tier runs it twice: a full build, and a code-only one stopped after
`01-scaffold` with no subdomain and taken live later — which must end on the
full build's tree, byte for byte. Only the
platform's typed actions (task, repo, link, land, watch, probe, reconcile)
are stood in for, a landing becoming a commit.

## 5. Cutting a baseline tag (maintainers)

Every site built from this repository resolves a `baseline-vN` tag, so the
tag is cut by a workflow rather than by hand:

```bash
gh workflow run tag.yml -f version=baseline-v1          # from main
gh workflow run tag.yml -f version=baseline-v1 -f ref=<sha>
```

It refuses a version that is not `baseline-v<N>` and a tag that already
exists: a baseline tag is never moved. Then move the registry row in
orun-cloud's `infra/baselines-registry/baselines.yaml` by pull request —
after the tag exists, because the registry's sync fetches `blueprint.yaml`
at the tag and refuses the whole catalogue if it 404s.

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `01-scaffold` stops at `link` | the repository is not linked to the workspace and the credential cannot link it — or the GitHub App is not installed on `githuborg`. Install it (console → Integrations → GitHub), allow-list the repo (console → Settings → Git repos) and re-run the phase |
| `02-live` waits on the `providers` probe, then stops | Cloudflare is not connected. Connect it (console → Integrations), then re-run — the probe is a wait, not a failure, and the site's code is already on `main` |
| A code-only site deploys nothing after a merge | expected: `intent.yaml` carries two `# @deploys-deferred:…` markers until `02-live` restores them. A manual deploy of stage or prod is refused (`environment stage is not activated by trigger github-push-main`) for the same reason |
| `subdomain --bind: … was given the placeholder` (or orun: `Only a run --until stops before the build's last phase … may keep a placeholder`) | the run reaches `02-live` with no workers.dev subdomain. Pass `--set subdomain=…`, or stop with `--until 01-scaffold` |
| `input conflict … subdomain: recorded "your-workers-subdomain", given "acme"` | a code-only site taken live in the container that built it, on an orun older than v2.90.0. Use v2.90.0, or a fresh container (the record is `.orun/`, which no checkout carries) |
| Secret WRITE fails `not_found` while listings work | the API key's role is below admin; re-mint it with the admin role |
| Deploy lane: Authentication error (10000) | the connection's token lacks Workers Scripts Write; re-issue it, re-connect, re-run `02-live` |
| `land` stops: `the landing's own check failed — orun plan for …` | the site's tree does not plan — the line after it is orun's own error (an unknown component type, a composition that does not resolve). Nothing was pushed. Fix the tree (or the baseline) and re-run the phase |
| `land` waits on CI after all | the site's repository requires a status check on `main` (branch protection or a ruleset), so GitHub refused the early merge; the landing waits for the check as a `checks: ci` landing would, then merges |
| Convergence failed AFTER the PR merged; re-running lands nothing | expected on its own — the files are on main. Re-run the phase (`--phase 02-live`, `--redo 02-live`, or the console's Retry): its `retouch` hook gives the landing a diff and the site redeploys |
| The site's `intent.yaml` says `workspace: ws_SET_ME` | `orunWorkspace` was empty and the build ran outside a workspace; set it and re-run `01-scaffold` |
| A bootstrap stopped before `03-docs`; prod no longer waits on stage | the gate is deferred, not dropped: run `03-docs`, or `node tooling/bootstrap/promotion.mjs --restore --file <site>/intent.yaml` (and `dev-lanes.mjs --restore`) |
| `✕ input "productname" is required` | all three required inputs (`reponame`, `productname`, `githuborg`) must be set on every invocation, single-phase ones included |
| `unknown flag: --phase`, `has no parameter "checks"`, `has no parameter "secrets"` or another parse error in the blueprint | the CLI is below the v2.88.0 floor |
| `02-live` lanes fail in `build-app` resolving a dependency | the site's intent no longer pins stack-tectonic 0.19.0. 0.20.0's lane-scoped install links each job's node_modules out of its staged tree; this site's Vite build has not been tried there, a Next.js sibling's did not build there, and the pin keeps the install the e2e tier proves. `intent.yaml` says why |
| `02-live`'s convergence reported green, then `verify` got 404 from both URLs | a second workflow ran on the push to main and the watch took its run. Only `ci.yml` may run on a push to main, and a site carries no other workflow (`testing/coverage.test.sh` holds the rule); read the CI run on main for the real result |
| orun.work's preview pane opens the stage URL in a new tab instead of framing it | the stage Worker sends no `frame-ancestors` naming orun.work: the deploy predates this baseline's framing policy, or `DEPLOY_ENV` did not reach the build (`turbo.json`'s `env`, the component's `environmentBuildVar`). `curl -sI <stage URL>` shows the header |
