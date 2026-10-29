// The server-functions demo's todos live with the visitor: one httpOnly
// cookie holding the list as JSON — base64url-encoded, so every byte of it is
// cookie-safe. The template kept them in a todos.json beside the server
// (node:fs); a Worker has no disk to keep a file on between requests, and no
// database is part of this starter, so the list rides with the requests that
// read and change it instead. Path=/ because the page's loader runs at the
// page's URL on the server and at /_serverFn/… when the browser calls it.
//
// A browser keeps about 4 KB per cookie, so the list is capped: at most
// MAX_TODOS todos, each cut to MAX_TEXT characters, and a change that would
// push the encoded list past MAX_COOKIE bytes is refused rather than written
// (a cookie over the limit is dropped by the browser, list and all).

export const COOKIE = 'todos'
export const MAX_TODOS = 50
export const MAX_TEXT = 100
export const MAX_COOKIE = 3800

export type Todo = { id: number; name: string }

// What a visitor with no list yet sees: the template's own two todos.
export const STARTER_TODOS: Todo[] = [
  { id: 1, name: 'Get groceries' },
  { id: 2, name: 'Buy a new phone' },
]

function toBase64url(value: string) {
  let binary = ''
  for (const byte of new TextEncoder().encode(value)) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function fromBase64url(value: string) {
  const binary = atob(value.replace(/-/g, '+').replace(/_/g, '/'))
  return new TextDecoder().decode(Uint8Array.from(binary, (c) => c.charCodeAt(0)))
}

/**
 * A todo's text as it is kept: control characters out, trimmed, and cut to
 * MAX_TEXT characters (code points, so a character is never split).
 */
export function clean(value: unknown) {
  const text = String(value ?? '')
    // biome-ignore lint/suspicious/noControlCharactersInRegex: control characters are what this removes
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .trim()
  return Array.from(text).slice(0, MAX_TEXT).join('')
}

/**
 * The list a cookie value holds; no cookie is the starter list. Anything
 * malformed — a cookie from an older shape, or one edited by hand — reads as
 * what can be salvaged from it.
 */
export function parse(raw: string | undefined): Todo[] {
  if (raw === undefined) return STARTER_TODOS.map((t) => ({ ...t }))
  let rows: unknown
  try {
    rows = JSON.parse(fromBase64url(raw))
  } catch {
    return []
  }
  if (!Array.isArray(rows)) return []
  const todos: Todo[] = []
  for (const row of rows) {
    if (!Array.isArray(row) || typeof row[1] !== 'string') continue
    const name = clean(row[1])
    if (!name) continue
    todos.push({ id: todos.length + 1, name })
    if (todos.length === MAX_TODOS) break
  }
  return todos
}

/** The cookie value for a list: compact rows of [id, name]. */
export function serialize(todos: Todo[]) {
  return toBase64url(JSON.stringify(todos.map((t) => [t.id, t.name])))
}

export type Added = { ok: true; todos: Todo[] } | { ok: false; error: string }

/**
 * The list with one more todo — numbered as the template numbers them, one
 * past the list's length — or why it cannot be kept.
 */
export function add(todos: Todo[], value: unknown): Added {
  const name = clean(value)
  if (!name) return { ok: false, error: 'A todo needs some text.' }
  if (todos.length >= MAX_TODOS) {
    return { ok: false, error: `The list holds ${MAX_TODOS} todos.` }
  }
  const next = [...todos, { id: todos.length + 1, name }]
  if (serialize(next).length > MAX_COOKIE) {
    return { ok: false, error: 'That would not fit in the cookie this list is kept in.' }
  }
  return { ok: true, todos: next }
}
