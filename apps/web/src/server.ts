// The Worker's entry: TanStack Start's own request handler, with this site's
// framing policy on every response it renders (src/lib/framing.ts — on stage,
// the origins that may show the site in a frame; elsewhere, nothing added).
//
// vite.config.ts names this file as the Worker's source entry, for `vite dev`
// and `vite build` alike. The browser's static files never reach it: Static
// Assets answer them before the Worker runs.
import handler, { createServerEntry } from '@tanstack/react-start/server-entry'
import { withFramingPolicy } from './lib/framing'

export default createServerEntry({
  async fetch(request) {
    return withFramingPolicy(await handler.fetch(request))
  },
})
