import { useCallback, useState } from 'react'
import { createFileRoute, useRouter } from '@tanstack/react-router'
import { createServerFn } from '@tanstack/react-start'
import { getCookie, getRequestUrl, setCookie } from '@tanstack/react-start/server'
import { COOKIE, add, parse, serialize } from '@/data/todos'

/*
const loggingMiddleware = createMiddleware().server(
  async ({ next, request }) => {
    console.log("Request:", request.url);
    return next();
  }
);
const loggedServerFunction = createServerFn({ method: "GET" }).middleware([
  loggingMiddleware,
]);
*/

// The list is the visitor's own, kept in their cookie (src/data/todos.ts):
// a Worker has no disk for the template's todos.json.
async function readTodos() {
  return parse(getCookie(COOKIE))
}

const getTodos = createServerFn({
  method: 'GET',
}).handler(async () => await readTodos())

const addTodo = createServerFn({ method: 'POST' })
  .validator((d: string) => d)
  .handler(async ({ data }) => {
    const result = add(await readTodos(), data)
    if (!result.ok) throw new Error(result.error)
    setCookie(COOKIE, serialize(result.todos), {
      path: '/',
      httpOnly: true,
      sameSite: 'lax',
      // Secure wherever the site is served over HTTPS (every deployment);
      // a plain-http local server keeps the cookie too.
      secure: getRequestUrl().protocol === 'https:',
      maxAge: 60 * 60 * 24 * 365,
    })
    return result.todos
  })

export const Route = createFileRoute('/demo/start/server-funcs')({
  component: Home,
  loader: async () => await getTodos(),
})

function Home() {
  const router = useRouter()
  const todos = Route.useLoaderData()

  const [todo, setTodo] = useState('')
  const [error, setError] = useState('')

  const submitTodo = useCallback(async () => {
    try {
      await addTodo({ data: todo })
      setTodo('')
      setError('')
    } catch (e) {
      // A list the cookie cannot hold is refused, not dropped: say so.
      setError(e instanceof Error ? e.message : String(e))
    }
    router.invalidate()
  }, [todo, router])

  return (
    <div
      className="flex items-center justify-center min-h-screen bg-gradient-to-br from-zinc-800 to-black p-4 text-white"
      style={{
        backgroundImage:
          'radial-gradient(50% 50% at 20% 60%, #23272a 0%, #18181b 50%, #000000 100%)',
      }}
    >
      <div className="w-full max-w-2xl p-8 rounded-xl backdrop-blur-md bg-black/50 shadow-xl border-8 border-black/10">
        <h1 className="text-2xl mb-4">Start Server Functions - Todo Example</h1>
        <ul className="mb-4 space-y-2">
          {todos?.map((t) => (
            <li
              key={t.id}
              className="bg-white/10 border border-white/20 rounded-lg p-3 backdrop-blur-sm shadow-md"
            >
              <span className="text-lg text-white">{t.name}</span>
            </li>
          ))}
        </ul>
        <div className="flex flex-col gap-2">
          <input
            type="text"
            value={todo}
            onChange={(e) => setTodo(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                submitTodo()
              }
            }}
            placeholder="Enter a new todo..."
            className="w-full px-4 py-3 rounded-lg border border-white/20 bg-white/10 backdrop-blur-sm text-white placeholder-white/60 focus:outline-none focus:ring-2 focus:ring-blue-400 focus:border-transparent"
          />
          <button
            type="button"
            disabled={todo.trim().length === 0}
            onClick={submitTodo}
            className="bg-blue-500 hover:bg-blue-600 disabled:bg-blue-500/50 disabled:cursor-not-allowed text-white font-bold py-3 px-4 rounded-lg transition-colors"
          >
            Add todo
          </button>
          {error && (
            <p role="alert" className="text-sm text-red-300">
              {error}
            </p>
          )}
        </div>
      </div>
    </div>
  )
}
