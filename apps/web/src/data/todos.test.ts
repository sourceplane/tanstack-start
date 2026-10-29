import { describe, expect, it } from 'vitest'
import { MAX_COOKIE, MAX_TEXT, MAX_TODOS, STARTER_TODOS, add, clean, parse, serialize } from './todos'

describe('the todo store kept in the visitor’s cookie', () => {
  it('starts a visitor with no cookie on the template’s two todos', () => {
    expect(parse(undefined)).toEqual(STARTER_TODOS)
    expect(parse(undefined)).not.toBe(STARTER_TODOS)
  })

  it('round-trips a list through the cookie value, any text included', () => {
    const todos = [
      { id: 1, name: 'Tell Ada & O’Brien "hi" <now>' },
      { id: 2, name: 'naïve café — 日本語 🎉' },
    ]
    const value = serialize(todos)
    expect(value).toMatch(/^[A-Za-z0-9_-]+$/)
    expect(parse(value)).toEqual(todos)
  })

  it('adds a todo numbered one past the list, as the template numbers them', () => {
    const result = add(parse(undefined), '  Water the plants  ')
    expect(result).toEqual({
      ok: true,
      todos: [...STARTER_TODOS, { id: 3, name: 'Water the plants' }],
    })
  })

  it('refuses an empty todo, a full list and a list the cookie cannot hold', () => {
    expect(add([], '   ')).toEqual({ ok: false, error: 'A todo needs some text.' })
    const full = Array.from({ length: MAX_TODOS }, (_, i) => ({ id: i + 1, name: 'x' }))
    expect(add(full, 'one more')).toMatchObject({ ok: false })
    const big = Array.from({ length: 40 }, (_, i) => ({ id: i + 1, name: 'y'.repeat(MAX_TEXT) }))
    const result = add(big.slice(0, 39), 'z'.repeat(MAX_TEXT))
    expect(serialize(big).length).toBeGreaterThan(MAX_COOKIE)
    expect(result).toEqual({ ok: false, error: 'That would not fit in the cookie this list is kept in.' })
  })

  it('cleans text: control characters out, trimmed, cut at MAX_TEXT code points', () => {
    expect(clean('a\u0000b\nc\u007f')).toBe('a b c')
    expect(Array.from(clean('🎉'.repeat(MAX_TEXT + 5)))).toHaveLength(MAX_TEXT)
    expect(clean(undefined)).toBe('')
  })

  it('reads a malformed cookie as what can be salvaged, never throws', () => {
    expect(parse('not base64 at all !!')).toEqual([])
    expect(parse(serialize([]))).toEqual([])
    const salvaged = Buffer.from(JSON.stringify([[1, 'keep'], 'junk', [2, 7], [9, ' also ']])).toString('base64url')
    expect(parse(salvaged)).toEqual([
      { id: 1, name: 'keep' },
      { id: 2, name: 'also' },
    ])
  })
})
