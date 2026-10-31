# 03-docs — the deployment, recorded

**Places** nothing. Its work is hooks: it records what `02-live` deployed,
from probed facts rather than from what the blueprint intended, and it puts
back the two things `02-live` deferred for the bootstrap's sake.

**Requires** `01-scaffold` placed. (`02-live` is hook-only too and derives as
`unknown`, so neither may be required; `--resume` runs `02-live` before this.)

## What runs

| hook | what it does |
|---|---|
| `promotion` | restores `environments.prod.promotion` — from now on prod deploys only after stage |
| `dev-lanes` | restores dev's activation on pushes to main |
| `render` | `hooks/render-deployment-docs.sh`: probes `/`, `/demo/start/server-funcs` and `/demo/api/names` on both environments and regenerates `ai/context/deployment.md` — the identity, the probed URLs, the secrets the deployment uses by name — and the README's live-deployment section. It asks the platform nothing: what the workspace holds right now is on the console's Secrets and Integrations pages, which the record points to |
| `task` | finds the phase's task and yields its key |
| `land` | one PR, its commit checked in the box (`checks: local`) and merged. It touches no component, so it deploys nothing — and there is nothing after it to wait for: the render's probes are the phase's check |

## Re-running it

Idempotent, and the way to refresh the record after a redeploy: every
generated section is re-rendered from scratch.

```bash
orun new --blueprint repo-blueprint.yaml --out <site-checkout> \
  --run-hooks --phase 03-docs --values <values.yaml>
```

## If a bootstrap stops before this phase

After `02-live` — a build that ran the live stage alone, say — the promotion
gate and dev's push activation stay deferred: `intent.yaml` carries a
`# @promotion-deferred:…` and a `# @dev-lanes-deferred:…` marker. The site is
live and deploys on every merge, but prod does not wait on stage. Running this
phase restores both, or by hand from the baseline checkout:

```bash
node tooling/bootstrap/promotion.mjs --restore --file <site>/intent.yaml
node tooling/bootstrap/dev-lanes.mjs --restore --file <site>/intent.yaml
```

A code-only site (stopped after `01-scaffold`) carries neither: its only
markers are stage's and prod's `# @deploys-deferred:…`, which `02-live`
restores when the site goes live.
