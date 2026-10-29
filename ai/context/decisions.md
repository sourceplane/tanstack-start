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
| 9 | One landing (`01-product`) then the record (`03-docs`); every bootstrap landing is checked in the box (`checks: local`) | A landing has a fixed cost; the convergence on `main` builds and smoke-tests the site anyway | `repo-blueprint.yaml` |
| 10 | stack-tectonic 0.19.0 | The layout the end-to-end tier proves; one job per lane gains nothing from a shared install | risk TS-H |
| 11 | The workers.dev subdomain is read from the Cloudflare connection, and the console asks for no domain | It has one right answer; a domain is an owner's step after the site is live | `blueprint.yaml` |
