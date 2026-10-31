# tanstack-start — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | Cloudflare's Vite plugin (`@cloudflare/vite-plugin`), TanStack Start's documented Cloudflare target, replaces Nitro; the component deploys the Worker and assets it builds | The framework's own target; `vite dev` runs the server in workerd too | `specs/epics/tanstack-start/design.md` §2 |
| 2 | TanStack Start 1.133 → 1.169 with Vite 8, `@vitejs/plugin-react` 6, vitest 5 | The current plugin and Start are what TanStack documents for Cloudflare; Start 1.169 requires Vite 8 | design.md §2 |
| 3 | One `wrangler.jsonc`, describing the BUILT Worker for `wrangler deploy --config wrangler.jsonc`; `vite.config.ts` names the source entry | The deploy's explicit `--config` never reads the build's redirect, and `verify-structure` checks the config before the build; one file and a test beat two files | design.md §3, risks TS-B, TS-C |
| 4 | The todos live in the visitor's own httpOnly cookie (50 × 100 characters, 3,800 encoded bytes), not `todos.json` | A Worker has no disk that outlives a request; no database is part of the template | design.md §2, risk TS-F |
| 5 | Tests live in `apps/web` (vitest over the site's name and the todo store) | One component; nothing to place separately | `repo-blueprint.yaml` |
| 6 | The site's name is one seam, `src/lib/site.ts`, read by the root route's `<title>` | The rename rewrites one line, written so that any name stays a valid string | IMPLEMENTATION-STATUS |
| 7 | The template's own `biome.json`, run as `biome lint`, and the code made to pass it (button types, keys, hook dependencies) | Upstream ships the config but never ran it; formatting stays upstream's | IMPLEMENTATION-STATUS |
| 8 | The devtools stay in production, as upstream | The template's behaviour; removing them is one line for an owner | risk TS-E |
| 9 | ~~One landing (`01-product`) then the record (`03-docs`)~~ — superseded by 12; every bootstrap landing is checked in the box (`checks: local`) | A landing has a fixed cost; the convergence on `main` builds and smoke-tests the site anyway | `repo-blueprint.yaml` |
| 10 | stack-tectonic 0.19.0 | The layout the end-to-end tier proves; one job per lane gains nothing from a shared install | risk TS-H |
| 11 | The workers.dev subdomain is read from the Cloudflare connection, and the console asks for no domain | It has one right answer; a domain is an owner's step after the site is live | `blueprint.yaml` |
| 12 | Two stages: `01-scaffold` (GitHub only: the whole site in one landing, deploy lanes parked) and `02-live` (Cloudflare: subdomain bound, credentials minted, lanes restored, one landing deployed and probed), then `03-docs`; declared as `spec.stages` | An account with no Cloudflare connection still gets its code (orun.work's code-only app); a full build pays one landing more and ends on the same tree | `repo-blueprint.yaml`, saas-orun-work WA-D8/WA-D9 |
| 13 | The scaffold parks stage's and prod's push activation (`deploys.mjs`) and leaves dev's: a merge plans dev's verify lane | orun refuses a push plan no environment answers, so parking all three turns `main` red; dev verifying is the design's "plan and verify lanes only". `promotion` and `dev-lanes` move to `02-live`, the landing they speed up | `tooling/bootstrap/deploys.mjs` |
| 14 | `subdomain` is late-bound on both card and build; `02-live` binds it with a hook over every tracked file (`subdomain.mjs`), refusing the placeholder and a move to another account | A resume does not place the scaffold's files again, so only a hook in the live stage can replace what the scaffold wrote; a targeted rewrite does not re-run the rebrand over code someone has since written | `tooling/bootstrap/subdomain.mjs` |
| 15 | No GitHub connection probe in the scaffold; the `link` check is the GitHub gate | A repository in orun.work's managed GitHub org is linked through a platform connection the workspace's connection list never shows, so a probe would wait out ten minutes on a ready build | `repo-blueprint.yaml` |
| 16 | Stage's framing policy is a `frame-ancestors` header set by the Worker's entry from a per-environment map, the environment written in at build time (`DEPLOY_ENV`, the composition's `environmentBuildVar`) | One Worker config serves both environments, so the Worker cannot tell them apart at run time; the lane builds per environment anyway. Static Assets' `_headers` would miss every rendered page | `apps/web/src/lib/framing.ts` |
