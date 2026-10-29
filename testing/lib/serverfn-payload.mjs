// The request body TanStack Start's browser client sends to a server
// function: `{ data }` serialized by seroval to JSON (createServerFn's
// client RPC). Built with the very seroval the site resolves — through
// @tanstack/react-router, the app's own dependency — so the e2e posts what a
// browser running this build would, not a hand-copied wire format.
//
//   node serverfn-payload.mjs <apps/web dir> <data as JSON>
import { createRequire } from "node:module";
import path from "node:path";

const [appDir, dataJson] = process.argv.slice(2);
if (!appDir || dataJson === undefined) {
  console.error("usage: serverfn-payload.mjs <apps/web dir> <data as JSON>");
  process.exit(2);
}
const fromApp = createRequire(path.join(path.resolve(appDir), "package.json"));
const fromRouter = createRequire(fromApp.resolve("@tanstack/react-router/package.json"));
const fromCore = createRequire(fromRouter.resolve("@tanstack/router-core/package.json"));
const seroval = await import(fromCore.resolve("seroval"));
process.stdout.write(JSON.stringify(await seroval.toJSONAsync({ data: JSON.parse(dataJson) })));
