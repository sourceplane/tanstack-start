import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { DEPLOY_ENV, FRAME_ANCESTORS, frameAncestorsPolicy, withFramingPolicy } from './framing'

// orun.work's preview pane frames a site's stage deploy, from these origins.
const ORUN_WORK = [
  'https://orun.work',
  'https://stage.orun.work',
  'https://orun-agent-web-stage.oruncloud.workers.dev',
  'https://orun-agent-web-prod.oruncloud.workers.dev',
]

describe('who may frame the site', () => {
  it('on stage: itself, orun.work on stage and prod, and orun.work run locally', () => {
    expect(frameAncestorsPolicy('stage')).toBe(
      `frame-ancestors 'self' ${ORUN_WORK.join(' ')} http://localhost:*`,
    )
  })

  it('on prod, dev and a build that names no environment: no policy at all', () => {
    for (const environment of ['prod', 'dev', '']) {
      expect(frameAncestorsPolicy(environment)).toBeNull()
    }
  })

  it('reads only its own entries, never one an object inherits', () => {
    expect(frameAncestorsPolicy('constructor')).toBeNull()
    expect(frameAncestorsPolicy('toString')).toBeNull()
  })

  it('lists only source expressions a browser accepts in frame-ancestors', () => {
    const source = /^('self'|'none'|https?:\/\/[a-z0-9.-]+(:(\d+|\*))?)$/
    for (const sources of Object.values(FRAME_ANCESTORS)) {
      for (const s of sources) expect(s).toMatch(source)
    }
  })

  it('outside a deploy build, the environment is empty', () => {
    expect(DEPLOY_ENV).toBe('')
  })
})

describe('a response, with the policy added', () => {
  it('stage: the header is added, and the response is otherwise the one rendered', async () => {
    const rendered = new Response('<p>hi</p>', { status: 404, headers: { 'content-type': 'text/html' } })
    const out = withFramingPolicy(rendered, 'stage')
    expect(out.status).toBe(404)
    expect(out.headers.get('content-type')).toBe('text/html')
    expect(out.headers.get('content-security-policy')).toBe(frameAncestorsPolicy('stage'))
    expect(await out.text()).toBe('<p>hi</p>')
  })

  it('prod: the very response, untouched', () => {
    const rendered = new Response('ok')
    expect(withFramingPolicy(rendered, 'prod')).toBe(rendered)
    expect(rendered.headers.has('content-security-policy')).toBe(false)
  })

  it('a policy the response already carries is kept beside it', () => {
    const rendered = new Response('ok', { headers: { 'content-security-policy': "default-src 'self'" } })
    const header = withFramingPolicy(rendered, 'stage').headers.get('content-security-policy')
    expect(header).toBe(`default-src 'self', ${frameAncestorsPolicy('stage')}`)
  })

  it('a response with immutable headers is copied, not refused', async () => {
    const rendered = Response.redirect('https://example.com/elsewhere', 302)
    const out = withFramingPolicy(rendered, 'stage')
    expect(out.status).toBe(302)
    expect(out.headers.get('location')).toBe('https://example.com/elsewhere')
    expect(out.headers.get('content-security-policy')).toBe(frameAncestorsPolicy('stage'))
  })
})

describe('the Worker', () => {
  it('renders every response through the policy (src/server.ts is its entry)', () => {
    const server = readFileSync(new URL('../server.ts', import.meta.url), 'utf8')
    expect(server).toContain('withFramingPolicy(await handler.fetch(request))')
    const vite = readFileSync(new URL('../../vite.config.ts', import.meta.url), 'utf8')
    expect(vite).toContain("main: './src/server.ts'")
    expect(vite).toContain('__DEPLOY_ENV__: JSON.stringify(process.env.DEPLOY_ENV')
  })

  it('learns its environment from the deploy lane (component.yaml names DEPLOY_ENV)', () => {
    const component = readFileSync(new URL('../../component.yaml', import.meta.url), 'utf8')
    expect(component).toMatch(/^ {4}environmentBuildVar: DEPLOY_ENV$/m)
    const turbo = JSON.parse(readFileSync(new URL('../../turbo.json', import.meta.url), 'utf8'))
    expect(turbo.tasks.build.env).toContain('DEPLOY_ENV')
  })
})
