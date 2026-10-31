// Who may show this site inside a frame, per environment.
//
// A page that says nothing about framing can be framed by any origin. This
// site says it on STAGE, and only there: every response the Worker renders
// for the stage environment carries
//
//   Content-Security-Policy: frame-ancestors <the sources below>
//
// so the origins allowed to frame it are a list in the code rather than a
// browser default, and a later change that adds `X-Frame-Options` cannot
// silently take the permission away (a browser that reads `frame-ancestors`
// ignores `X-Frame-Options`).
//
// Stage is listed for orun.work, the app builder: its preview pane shows a
// site's stage deploy in an iframe. Prod and every other environment send
// no such header, so they are framed (or not) exactly as before.
//
// TO CHANGE WHO MAY FRAME THE SITE, edit this map: one entry per environment,
// each a list of CSP source expressions (an origin, `'self'`, `'none'`, or a
// scheme/host/port pattern such as `http://localhost:*`). An environment that
// is not a key here sends no header. The build tells the Worker which
// environment it is (`DEPLOY_ENV`, see below), so the change reaches an
// environment with its next deploy.
export const FRAME_ANCESTORS: Readonly<Record<string, readonly string[]>> = {
  stage: [
    "'self'",
    // orun.work's preview pane, on its stage and prod deploys.
    'https://orun-agent-web-stage.oruncloud.workers.dev',
    'https://orun-agent-web-prod.oruncloud.workers.dev',
    // orun.work run locally, for its development: any port.
    'http://localhost:*',
  ],
}

// The environment this Worker was BUILT for. The deploy lane exports
// `DEPLOY_ENV` to the build (`environmentBuildVar` in component.yaml) and
// vite.config.ts writes it into the server bundle as `__DEPLOY_ENV__`. Every
// environment's lane runs its own build, so the stage Worker knows it is
// stage. Empty for a build that names none: `vite dev`, the unit tests, a
// build by hand.
declare const __DEPLOY_ENV__: string | undefined
export const DEPLOY_ENV: string = typeof __DEPLOY_ENV__ === 'string' ? __DEPLOY_ENV__ : ''

/** The `Content-Security-Policy` value for an environment, or null for none. */
export function frameAncestorsPolicy(environment: string): string | null {
  if (!Object.hasOwn(FRAME_ANCESTORS, environment)) return null
  const sources = FRAME_ANCESTORS[environment] ?? []
  return sources.length > 0 ? `frame-ancestors ${sources.join(' ')}` : null
}

/**
 * The response, with the environment's framing policy added. Appended rather
 * than set, so a policy the response already carries is kept: a browser
 * enforces every `Content-Security-Policy` header it receives.
 */
export function withFramingPolicy(response: Response, environment: string = DEPLOY_ENV): Response {
  const policy = frameAncestorsPolicy(environment)
  if (!policy) return response
  try {
    response.headers.append('Content-Security-Policy', policy)
    return response
  } catch {
    // A response whose headers are immutable (one passed through from a
    // fetch): copy it, then add the header to the copy.
    const copy = new Response(response.body, response)
    copy.headers.append('Content-Security-Policy', policy)
    return copy
  }
}
