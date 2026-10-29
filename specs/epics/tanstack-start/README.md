# tanstack-start — Vercel's TanStack Start template on Cloudflare Workers

**The template is TanStack Start's own starter app — a welcome page, a todo
list read by a GET server function in its loader and changed by a POST one,
an API route, and one server function rendered three ways (full SSR,
data-only, SPA) — so the port is one Worker built by Cloudflare's Vite
plugin, TanStack Start's own Cloudflare target, with the todos moved from a
file on the server's disk into the visitor's own cookie, deployed by Orun to
stage and prod on every merge — and the baseline that makes a copy of it
somebody else's site in one landing.**

| | |
|---|---|
| Status | In progress — TS1 on main: the site runs on Workers |
| Upstream | [vercel/vercel › examples/tanstack-start](https://github.com/vercel/vercel/tree/main/examples/tanstack-start), at `84878e5` — Apache-2.0 |
| Reference | [sveltekit-boilerplate](https://github.com/sourceplane/sveltekit-boilerplate) (the Vite-built Worker + Static Assets scaffolding, and the cookie-kept todos) |
| Key | `TS` |

## Read in this order

1. [design.md](design.md) — the template, how each Vercel piece maps to
   Cloudflare, the repository and the build, and the alternatives rejected.
2. [implementation-plan.md](implementation-plan.md) — the milestones and
   what each one lands.
3. [risks-and-open-questions.md](risks-and-open-questions.md) — what is not
   proven, and what was accepted.
4. [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md) — what shipped, and
   every departure from the upstream template.

## Milestones

| Milestone | What it lands | Task |
|---|---|---|
| TS0 — the spec | the repository, its intent, CI, tooling and spec index; this doc set | TS-1 |
| TS1 — TanStack Start on Workers | the template in `apps/web` on Cloudflare's Vite plugin, the cookie-kept todos, its tests, the README | TS-2 |
| TS2 — a baseline | the console card, the build document, the context pack and the baseline's tests | TS-3 |
