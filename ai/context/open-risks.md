# tanstack-start — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted ones, is
`specs/epics/tanstack-start/risks-and-open-questions.md`; this page lists
only what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| TS-A | No live bootstrap yet: the repository created and linked, the Cloudflare token minted, a real `wrangler deploy` and the probes are unproven — nor the two-stage build's code-only stop and later go-live | OPEN | One bootstrap from `baseline-v2` against a workspace, code only then live, timed on stage |
| TS-J | Going live later needs the site's checkout as the build's `--out`: `02-live` requires `01-scaffold` derived from the tree and lands from its git. A fresh, empty `--out` re-places the scaffold instead, and its landing is refused once `main` holds files the baseline does not (a code-only app's own work) | OPEN | The platform's go-live runs in a checkout of the app's `main` |
| TS-K | Going live in the container that built the scaffold needs orun v2.90.0 (late-bound inputs); older ones refuse the real subdomain against the recorded placeholder | OPEN | v2.90.0 released and the runner's |
| TS-L | Stage's `frame-ancestors` list narrows framing from any origin (no header) to the listed ones: orun.work served from any other origin — a custom domain — cannot frame a stage site until it is listed and that site's stage redeploys | MITIGATED (baseline-v3) | orun.work's domain, `https://orun.work` and `https://stage.orun.work`, is listed in `apps/web/src/lib/framing.ts`; a site cut from baseline-v2 or earlier lists only the workers.dev origins until it takes v3 |

Accepted, and worth knowing before you change them: TS-B (`wrangler.jsonc`
is the built Worker, held to the Vite plugin's output by the end-to-end
tier), TS-D (the end-to-end tier speaks the server-function protocol),
TS-E (the devtools render in production, as upstream), TS-F (the todos are
per visitor).
