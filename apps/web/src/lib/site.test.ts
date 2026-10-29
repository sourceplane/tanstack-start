import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { SITE_NAME } from './site'

describe('the site name', () => {
  it('is one non-empty literal on one line — the line a rebrand rewrites', () => {
    expect(SITE_NAME.length).toBeGreaterThan(0)
    const source = readFileSync(new URL('./site.ts', import.meta.url), 'utf8')
    const lines = source.split('\n').filter((l) => l.startsWith('export const SITE_NAME = '))
    expect(lines).toEqual([`export const SITE_NAME = ${JSON.stringify(SITE_NAME)}`])
  })

  it('is the <title> of every page (the root route reads it)', () => {
    const root = readFileSync(new URL('../routes/__root.tsx', import.meta.url), 'utf8')
    expect(root).toContain('title: SITE_NAME,')
  })
})
