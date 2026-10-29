# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`tanstack-start/`](./tanstack-start/) | **TS** | ✅ Shipped (`baseline-v1`); not yet live | Vercel's TanStack Start template — the welcome page, server-function todos kept in the visitor's cookie, an API route and the three SSR modes — on Cloudflare Workers + Static Assets via Cloudflare's Vite plugin, and an Orun baseline that instantiates it in one landing (TS2) |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
