# tanstack-start — risks and open questions

| ID | Risk | State |
|---|---|---|
| TS-A | No live bootstrap yet: the repository created and linked, the Cloudflare token minted, a real `wrangler deploy` and the probes are unproven | OPEN — one bootstrap from `baseline-v1` against a workspace closes it |
| TS-B | The committed `wrangler.jsonc` describes the Worker the Vite plugin builds; a plugin release that changes its output (the entry's path, the module rule, the assets directory) would leave the deploy pointing at the wrong files | MITIGATED — the end-to-end tier compares the plugin's `dist/server/wrangler.json` with `wrangler.jsonc` and the two configs' dry-run uploads on every run, so a lockfile bump that changes either fails before a tag |
| TS-C | The plugin warns on every build that `no_bundle` and `rules` are ignored under Vite | ACCEPTED — they are for the deploy; the warning is the cost of one config (design §3, §5) |
| TS-D | Server functions are an internal protocol: `/_serverFn/<id>`, a seroval body, an `Origin` (or `Sec-Fetch-Site`) check that answers 403 otherwise. The end-to-end tier speaks it | ACCEPTED — the tier builds each body with the app's own seroval and reads each id from the build's own resolver, so an upgrade that changes the wire fails the tier, not the site |
| TS-E | TanStack's devtools render in production, as upstream does on Vercel: `@tanstack/react-devtools` has no production switch and the template does not use `@tanstack/devtools-vite` | ACCEPTED — the template's behaviour; an owner removes `<TanStackDevtools>` from `src/routes/__root.tsx` (or adds the devtools Vite plugin) |
| TS-F | The todos are the visitor's own: clearing cookies clears the list, and a list does not follow a visitor to another browser | ACCEPTED — upstream's `todos.json` was one list for everyone, and on Vercel it could not be written at all; per-visitor state needs no database (design §2) |
| TS-G | `nodejs_compat` is required: Start's server imports `node:async_hooks` and friends | ACCEPTED |
| TS-H | stack-tectonic 0.19.0, not 0.20.0: 0.20.0's lane-scoped install links each job's `node_modules` out of its staged tree, and this site's build has not been tried in that layout | ACCEPTED — the pin keeps the layout the end-to-end tier proves |
| TS-I | A custom domain is the owner's step: the site goes live on workers.dev, and attaching a domain needs zone permissions the brokered `workers-deploy` token does not carry | ACCEPTED |
