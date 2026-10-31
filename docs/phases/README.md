# The phases — one blueprint, two stages, three selections

`repo-blueprint.yaml` declares three phases that take a site from **nothing**
to **live on stage and prod, documented**: one landing places the whole site
with GitHub alone, one takes it live on Cloudflare, one records it. Run them
one at a time with `--phase <name>`, stop after the code with
`--until 01-scaffold`, or run the whole sequence unattended with `--resume`.
There is no umbrella workflow and no per-phase document: a phase is a
selection on one artifact, which is what makes running one alone, months
later, from a fresh container the same operation as running them all.

## Two stages

The build splits where its needs change, and the card says where
(`blueprint.yaml` `spec.stages`):

| stage | phase | needs | leaves |
|---|---|---|---|
| **scaffold** | [`01-scaffold`](01-scaffold.md) | GitHub only | the site's code on `main` in its own linked repository; its deploy lanes parked, so CI on `main` is green and deploys nothing |
| **live** | [`02-live`](02-live.md) | Cloudflare (the card's `requires.integrations`) | the site live on stage and prod, smoke-tested and probed |

A build with a Cloudflare connection runs both, then `03-docs`, in one go —
and ends exactly where the one-landing shape (`baseline-v1`'s `01-product`)
did. A build without one stops after the scaffold (`--until 01-scaffold`;
the platform's `until: scaffold`) and the site is **code only**: its
repository, CI and pull-request checks all work and nothing is deployed. A
later build goes live: `--resume` finds `01-scaffold` placed and runs
`02-live` and `03-docs`.

The workers.dev subdomain is the one **late-bound** input: it belongs to the
Cloudflare account, so a code-only build runs without it (the tree carries
the placeholder `your-workers-subdomain`), and `02-live` binds the real value
before anything deploys.

The deploying phase follows the contract every deploying phase does:

> **land the change as one pull request, checked in the box → watch the
> convergence that merge triggers (auto-resumed) → verify the outcome over
> HTTP.**

The run's task set-up — the epic, a milestone per phase, a task per landing
— runs in the background from the start; the first hook that needs it, the
phase's `task`, waits for it.

Run from the baseline checkout (the blueprint's source is `path: .`); the
site's repository is wherever `--out` points.

## Execution order

The phase number is the EXECUTION order, and each phase's `requires.phases`
states it in the document: the engine refuses a phase whose predecessor is not
placed, and names it. `02-live` and `03-docs` place no files, so the tree
cannot answer for them (`unknown`): both require `01-scaffold`, and
`--resume` always runs them again — every hook in both is idempotent.

Every landing is a pull request on a branch named for its task
(`orun/BASE-<n>-<phase>`), checked before it is pushed: `orun validate`, then
`orun plan` as the pull request and as the merge would plan it, in the box,
in under a second (`checks: local`). Then it merges; nothing waits for the
PR's CI. On those branches `ci.yml` runs `plan` only and skips the lanes,
because the merge runs them on main moments later, for real. The site carries
no other workflow: the baseline's own CI (Tier 2) installs, renders the
fixtures, type-checks, lints, tests and builds this tree before a tag is cut,
and every later pull request in the site runs `ci.yml`'s verify lanes (built
and dry-deployed per environment; they do not lint or run the tests).

| phase | lands | what main's CI does with it | verified by |
|---|---|---|---|
| [`01-scaffold`](01-scaffold.md) | **the GitHub repo created**, then the WHOLE site in one PR: intent, CI, tooling, identity, `apps/web` (the site and its tests) — stage's and prod's deploy lanes parked | dev's verify lane; nothing deployed | repo workspace-linked; the landing's own plan |
| [`02-live`](02-live.md) | the subdomain bound, the deploy lanes put back, the deploy credentials minted; one PR whose merge deploys | the site deployed to stage and prod side by side, smoke-tested | convergence green (build, deploy, smoke) + both URLs answer |
| [`03-docs`](03-docs.md) | the live-deployment record; the promotion gate and dev lanes put back | nothing (no component changed) | committed manifest matches probed reality |

There is no custom-domain phase. Attaching a domain to a Worker needs zone
permissions the platform's brokered `workers-deploy` token does not carry, so
it is an owner's step after the bootstrap — the site's README, "Custom
domain", says how. Nothing else in the repository changes with it — the site
builds no absolute links — beyond `BASE_DOMAIN` in `intent.yaml`, which holds
the placeholder until then.

## Inputs

`01-scaffold` takes the site's identity once and writes it into the repo
(`.rebrand/values.json`); every later phase reads it back from the placed
tree. But the blueprint's **required** inputs — `reponame`, `productname`,
`githuborg` — are validated before any phase runs, so they must be supplied
on every invocation, single-phase ones included. A `--values` file is easier
than repeating `--set`.

- `productdomain` — NOT ASKED, default empty. The site goes live on
  workers.dev; empty brands the reserved placeholder `<reponame>.example.com`
  into `BASE_DOMAIN`, for an owner to replace when they attach a domain (the
  site's README, "Custom domain"). Pass it only for a site that already has
  its domain.
- `subdomain` — the workers.dev subdomain of the Cloudflare account you
  deploy into. It is in every URL `02-live` probes and the deploy's smoke
  fetches. A console or `--from bst_…` build reads it from the Cloudflare
  connection; pass it only for a hand-run build. LATE-BOUND: a code-only
  build (`--until 01-scaffold`) runs without it, and the run that goes live
  must pass it.
- `orunWorkspace` — workspace id (`ws_…`). Unset, it is the workspace the
  build runs in (`from: workspace`); with none anywhere, a placeholder that
  fails loudly rather than silently claiming another tenant's workspace.
- `epicSlug` (default `tanstack-start-baselining`) — the epic every phase clubs
  its task under. Found by slug, so a fresh run and a resumed run find the
  same work.
- `repoPrivate` (default `true`) — the repository's visibility at creation.

```bash
# the code only — GitHub, no Cloudflare
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/sites/acme-notes --run-hooks --until 01-scaffold \
  --values ~/acme-notes.values.yaml

# … later, live: the rest, with the account's subdomain
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/sites/acme-notes --run-hooks --resume \
  --values ~/acme-notes.values.yaml --set subdomain=acme
```

Drop `--run-hooks` (or add `--status`) to preview. Without it a phase places
files and stops: no repo, no landing, no convergence watch, and no probe —
which is exactly what makes a dry instantiation of this baseline possible in
CI with no workspace and no provider (`testing/placement.test.sh`,
`testing/e2e.test.sh`).

## What 01-scaffold does after it places

Placement writes the baseline's files as they are here. Before the phase
lands, its `post` hooks make them the site's:

1. `rebrand` → `rebrand --verify` — the identity rename over the whole tree,
   then a sweep that fails on any of this baseline's identity left behind.
2. `orun-workspace`, `work-tree` — the site's workspace in, the baseline's
   work tree out.
3. `deploys` — stage's and prod's push-to-main activation parked, so the
   merge deploys nothing.

The baseline's complete lockfile ships as it is: it carries no identity, and
the lanes install it with `--frozen-lockfile`, as the baseline's own CI does
on this exact tree before a tag.

## When a phase fails

- **Before it lands** (a refused link, a rebrand residue, a probe that timed
  out, the placeholder subdomain, a tree the landing's own `orun plan`
  refuses): nothing was merged. Fix what the message names and re-run the
  phase.
- **After `02-live` lands** (the convergence went red): the files are on main.
  `orun.run/watch@v1` has already resumed the run up to three times. Re-run
  the phase (`--phase 02-live`, `--redo 02-live` under `--resume`, or the
  console's Retry): its `retouch` hook gives the landing a diff and the
  component redeploys.
- **A build that stops before `03-docs`**: the site is live and deploys on
  every merge, but prod does not wait on stage and dev does not verify
  merges until `03-docs` runs ([03-docs.md](03-docs.md)).
