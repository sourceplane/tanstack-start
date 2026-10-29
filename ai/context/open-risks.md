# tanstack-start — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted ones, is
`specs/epics/tanstack-start/risks-and-open-questions.md`; this page lists
only what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| TS-A | No live bootstrap yet: the repository created and linked, the Cloudflare token minted, a real `wrangler deploy` and the probes are unproven | OPEN | One bootstrap from `baseline-v1` against a workspace |

Accepted, and worth knowing before you change them: TS-B (`wrangler.jsonc`
is the built Worker, held to the Vite plugin's output by the end-to-end
tier), TS-D (the end-to-end tier speaks the server-function protocol),
TS-E (the devtools render in production, as upstream), TS-F (the todos are
per visitor).
