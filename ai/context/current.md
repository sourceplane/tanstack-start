# tanstack-start — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a site built from it; the
two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Vercel's TanStack Start template (the welcome page, a todo list read and
changed by server functions, an API route, the three SSR modes) on TanStack
Start 1.169, deployed as one Cloudflare Worker + Static Assets through
Cloudflare's Vite plugin — TanStack Start's own Cloudflare target. The todos
live in each visitor's own httpOnly cookie. Packaged as an Orun baseline:
`orun new --blueprint repo-blueprint.yaml` builds a new site in its own
repository in two stages — the code landed with GitHub alone (`01-scaffold`,
its deploy lanes parked), then live on stage and prod with Cloudflare
(`02-live`) — then records what went live (`03-docs`). A build with no
Cloudflare connection stops after the scaffold (a code-only site) and goes
live later; the card declares the split (`spec.stages`) for orun.work.
On stage, the Worker lets orun.work's preview pane frame it.

## Release

| | |
|---|---|
| Latest tag | `baseline-v2` (TS-4: the two-stage build and stage framing); orun.work's domain in the framing list is on `main` for `baseline-v3` |
| Proven live | No. Everything short of the platform is proven offline in Baseline CI (risk TS-A). The card's 5 minutes is an estimate |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/tanstack-start/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/tanstack-start/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/tanstack-start/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What the component is | `apps/web/docs/` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Cut `baseline-v3` (orun.work's domain, `orun.work` and
   `stage.orun.work`, may frame stage) and move the registry row to it.
2. Bootstrap one site from it against a workspace — code only, then live —
   and record its timings on stage in place of the estimate (closes TS-A;
   orun.work offers the baseline to apps only after that measurement).
