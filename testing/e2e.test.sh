#!/usr/bin/env bash
# TIER 2 — the site a bootstrap produces builds, deploys (dry) and serves.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree.
# This proves it WORKS, by doing to it what its own pipelines will:
#
#   1. at the finished site, the landing's own checks — install with the
#      lockfile the site ships, render fixtures, typecheck, lint, test,
#      build. The bootstrap's own landings are checked in the box with
#      `orun validate` and `orun plan` alone (`checks: local`; their PR's CI
#      on an `orun/BASE-…` branch is `plan` alone, and the convergence on
#      main builds, deploys and smoke-tests the site), and a later pull
#      request of the site runs ci.yml's verify lanes, which build and
#      dry-deploy it but do not lint or run the tests — so THIS is where a
#      site those steps refuse is caught: before the tag, not after a build
#      has merged it;
#   2. the stage lane's own steps, rendered by `orun plan` in the site: on a
#      pull request (the verify profile) `build-app` — the component's
#      buildCommand, the same step the deploy profile runs; `vite build`,
#      where Cloudflare's Vite plugin writes the Worker to dist/server and the
#      browser's files to dist/client, where wrangler.jsonc's `main` and
#      `assets.directory` point — `verify-build-output` (the component's
#      `workerEntrypoint` and `assetsDir`) and `deploy-dry-run` (`wrangler
#      deploy --dry-run --config wrangler.jsonc --name <reponame>-web-stage`).
#      They run IN THE TREE THE RUNNER STAGES for the job
#      (testing/lib/stage-job.py), with the dependency layout the pinned
#      composition produces: if its install step is `scope: lane`, the
#      top-level node_modules is a symlink to the source checkout's; if not,
#      the job's own install step runs inside the staged tree;
#   3. THE ONE WORKER CONFIG, held to the build: the deploy names
#      wrangler.jsonc, which describes the BUILT Worker, while the plugin
#      writes its own config beside the build (dist/server/wrangler.json).
#      The two must name the same Worker — compatibility date and flags, the
#      entry, the module rule, the assets — and a dry-run deploy of each
#      must upload the same modules. A plugin release that moves its output
#      fails here, before a tag;
#   4. serve the built Worker with `wrangler dev` FROM THAT STAGED TREE and run
#      the component's OWN `smokeCommand` against it, verbatim — the check the
#      real deploy ends with — and then read every route the site promises:
#      the welcome page with the site's name as its `<title>` (escaped, not
#      broken, by an `&` and an `'`), the hashed client build and the static
#      files, the API route and the page that reads it, the three SSR modes
#      (the songs in the markup, only in the loader's data, and in neither —
#      fetched by the browser through the GET server function), the todos
#      through their server functions called as the browser calls them
#      (testing/lib/serverfn-payload.mjs) — the visitor's starter list, a
#      todo added by the POST one and read back by the page and by the GET
#      one with the cookie it set, an empty todo refused, a cross-origin post
#      refused — and an unknown path's 404. And, because the lane built it
#      for STAGE (`DEPLOY_ENV`), every page it renders names who may frame
#      it — orun.work's preview pane among them (src/lib/framing.ts); the
#      static files, which never reach the Worker, carry nothing.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered Cloudflare token, deploy for real and probe workers.dev. That is a
# bootstrap against a workspace (BOOTSTRAP.md); everything short of it is here.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, and the network for
# `pnpm install` (or a warm store). A few minutes: two installs and builds
# (the landing's checks over the site, and the stage lane's own in its staged
# tree).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git curl; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done

scratch="$(mktemp -d)"
dev_pid=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So it is
# started as its own process group (setsid) and the whole group is stopped.
cleanup() {
  if [ -n "$dev_pid" ]; then
    kill -TERM -- "-$dev_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$dev_pid" 2>/dev/null || break; sleep 0.5; done
    kill -KILL -- "-$dev_pid" 2>/dev/null || true
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false TURBO_TELEMETRY_DISABLED=1

# The landing's own checks, step for step, run here at once on the whole
# tree. A pull request in the site builds and dry-deploys it through ci.yml's
# lanes; the lint and the tests run here, and by hand before a push.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   3 phases placed and landed"

# ── 1. the finished site ───────────────────────────────────────────────────
echo "── the finished site: install, the fixture render, typecheck, lint, test, build"
checks "$tree" "$scratch/checks-site.log"

# ── 2. the deploy lane's steps, for stage ──────────────────────────────────
echo "── the stage lane: build-app, verify-build-output, deploy-dry-run"
# The 01-scaffold landing over the repository's empty first commit: every file
# of the site changed, as on its pull request.
s00="$(git -C "$tree" rev-parse HEAD~3)"; s01="$(git -C "$tree" rev-parse HEAD~2)"
(cd "$tree" && orun plan --intent intent.yaml --trigger github-pull-request --changed \
   --base "$s00" --head "$s01" --env stage --output "$scratch/plan.json") > "$scratch/plan.log" 2>&1 \
  || { echo "FAIL: orun plan" >&2; tail -15 "$scratch/plan.log" >&2; exit 1; }
python3 - "$scratch/plan.json" "$scratch/steps" <<'PY'
import json, pathlib, sys
plan = json.load(open(sys.argv[1]))
out = pathlib.Path(sys.argv[2]); out.mkdir()
job = next(j for j in plan["jobs"] if j["component"] == "web" and j["environment"] == "stage")
for s in job["steps"]:
    if s["id"] in ("build-app", "verify-build-output", "deploy-dry-run"):
        (out / f"{s['id']}.sh").write_text(s.get("run") or "")
    if s["id"] == "install-workspace-dependencies":
        (out / "install.sh").write_text(s.get("run") or "")
        (out / "install.wd").write_text(s.get("working-directory") or ".")
        (out / "install.scope").write_text(s.get("scope") or "job")
(out / "path").write_text(job.get("path") or "apps/web")
for k, v in (job.get("env") or {}).items():
    (out / "env").open("a").write(f"export {k}={json.dumps(v)}\n")
PY
# The job's private tree, staged as orun stages it. The source checkout
# carries no build output (a CI checkout has none, so the plain-tree build's is
# removed rather than copied in), and its dependencies are what the pinned
# composition says: a lane-scoped install ran once in the source tree (step 1
# ran the same command) and is linked in, or the job installs its own.
rm -rf "$tree/apps/web/dist" "$tree/apps/web/.tanstack" "$tree/apps/web/.wrangler"
work="$tree/.orun/runs/e2e/web.stage.verify-deploy/work"
[ -f "$scratch/steps/install.sh" ] || { echo "FAIL: the stage lane has no install step" >&2; exit 1; }
if [ "$(cat "$scratch/steps/install.scope")" = lane ]; then
  python3 "$here/lib/stage-job.py" "$tree" "$work" --shared-deps
  [ -L "$work/node_modules" ] || { echo "FAIL: the staged tree's node_modules is not the lane's symlink" >&2; exit 1; }
  echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: lane — node_modules → the source tree's"
else
  python3 "$here/lib/stage-job.py" "$tree" "$work"
  echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: job — installing inside it"
  echo "   ▸ install-workspace-dependencies"
  (cd "$work/$(cat "$scratch/steps/path")/$(cat "$scratch/steps/install.wd")" && bash -e "$scratch/steps/install.sh") \
    > "$scratch/install.log" 2>&1 || { echo "FAIL: the lane's install step" >&2; tail -30 "$scratch/install.log" >&2; exit 1; }
  [ -d "$work/node_modules" ] && [ ! -L "$work/node_modules" ] \
    || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
fi
# The lane tells the build which environment it is for: the stage Worker's
# framing policy depends on it (component.yaml's environmentBuildVar).
grep -q '^export DEPLOY_ENV="stage"$' "$scratch/steps/build-app.sh" \
  || { echo "FAIL: the stage lane's build-app does not export DEPLOY_ENV=stage" >&2; cat "$scratch/steps/build-app.sh" >&2; exit 1; }
for step in build-app verify-build-output deploy-dry-run; do
  [ -f "$scratch/steps/$step.sh" ] || { echo "FAIL: the stage verify lane has no $step step" >&2; exit 1; }
  echo "   ▸ $step"
  # The runner's per-job environment: the job's env (intent environment
  # `env:`) and ORUN_ENVIRONMENT; the step runs in the component's directory.
  if ! (cd "$work/$(cat "$scratch/steps/path")" && \
        { [ -f "$scratch/steps/env" ] && source "$scratch/steps/env"; true; } && \
        export ORUN_ENVIRONMENT=stage && bash -e "$scratch/steps/$step.sh") > "$scratch/$step.log" 2>&1; then
    echo "FAIL: the deploy lane's $step step" >&2; tail -40 "$scratch/$step.log" >&2; exit 1
  fi
done

# ── 3. the one Worker config, held to the build ───────────────────────────
echo "── wrangler.jsonc against the config the Vite plugin wrote"
app="$work/apps/web"
python3 - "$app" <<'PY'
import json, os, re, sys
app = sys.argv[1]
def jsonc(path):
    return json.loads(re.sub(r"^\s*//.*$", "", open(path).read(), flags=re.M))
ours = jsonc(os.path.join(app, "wrangler.jsonc"))
built_path = os.path.join(app, "dist/server/wrangler.json")
if not os.path.exists(built_path):
    sys.exit("FAIL: the build wrote no dist/server/wrangler.json")
built = json.load(open(built_path))
problems = []
def same(label, a, b):
    if a != b:
        problems.append(f"{label}: wrangler.jsonc has {a!r}, the plugin's config {b!r}")
for key in ("name", "compatibility_date", "compatibility_flags", "no_bundle", "rules"):
    same(key, ours.get(key), built.get(key))
here = lambda rel: os.path.realpath(os.path.join(app, rel))
there = lambda rel: os.path.realpath(os.path.join(app, "dist/server", rel))
same("the entry", here(ours["main"]), there(built["main"]))
same("the assets directory", here(ours["assets"]["directory"]), there(built["assets"]["directory"]))
if problems:
    print("FAIL: the committed Worker config is not the Worker the build made:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)
print(f"   the same Worker: {ours['name']}, {ours['main']}, assets {ours['assets']['directory']}, "
      f"{ours['compatibility_date']} {ours['compatibility_flags']}")
PY
for which in wrangler.jsonc dist/server/wrangler.json; do
  out="$scratch/dry-$(basename "$which")"
  (cd "$app" && pnpm exec wrangler deploy --dry-run --config "$which" --name "$repo-web-stage" --outdir "$out") \
    > "$out.log" 2>&1 || { echo "FAIL: the dry-run deploy of $which" >&2; tail -20 "$out.log" >&2; exit 1; }
  (cd "$out" && find . -type f | LC_ALL=C sort) > "$out.files"
  grep -E '^Total Upload: ' "$out.log" > "$out.total" || { echo "FAIL: no upload size from $which" >&2; exit 1; }
done
cmp -s "$scratch/dry-wrangler.jsonc.files" "$scratch/dry-wrangler.json.files" \
  || { echo "FAIL: the two configs upload different modules:" >&2
       diff "$scratch/dry-wrangler.jsonc.files" "$scratch/dry-wrangler.json.files" >&2; exit 1; }
cmp -s "$scratch/dry-wrangler.jsonc.total" "$scratch/dry-wrangler.json.total" \
  || { echo "FAIL: the two configs upload different sizes" >&2; cat "$scratch"/dry-*.total >&2; exit 1; }
echo "   both upload the same $(wc -l < "$scratch/dry-wrangler.jsonc.files" | tr -d ' ') files — $(cat "$scratch/dry-wrangler.jsonc.total")"

# ── 4. serve it, and smoke it as the deploy does ───────────────────────────
echo "── wrangler dev over the built Worker"
port=$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()")
(cd "$work/apps/web" && exec setsid pnpm exec wrangler dev --config wrangler.jsonc --ip 127.0.0.1 --port "$port" \
   --name "$repo-web-stage" --show-interactive-dev-session=false) > "$scratch/dev.log" 2>&1 < /dev/null &
dev_pid=$!
url="http://127.0.0.1:$port"
for _ in $(seq 1 90); do
  curl -s -o /dev/null "$url/" && break
  kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }
  sleep 1
done
curl -s -o /dev/null "$url/" || { echo "FAIL: wrangler dev never answered" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }

echo "   ▸ the component's own smokeCommand, DEPLOYED_URL=$url"
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the site" >&2; exit 1; }

echo "   ▸ every route the site promises"
python3 - "$url" "$values" "$work/apps/web" "$here/lib/serverfn-payload.mjs" <<'PY'
import glob, html, json, re, subprocess, sys, urllib.error, urllib.request
base, values, app, payload_js = sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3], sys.argv[4]
name = values["productname"]
problems = []
def bad(m): problems.append(m)
def get(path, data=None, headers=None, method=None):
    req = urllib.request.Request(base + path, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read()
def markup(page):  # the rendered HTML, without the scripts that carry the loaders' data
    return re.sub(r"<script\b.*?</script>", "", page, flags=re.S)
def text(fragment):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", fragment))).strip()
def title(page):
    m = re.search(r"<title>(.*?)</title>", page, re.S)
    return m and html.unescape(m.group(1))
def h1s(page):
    return [text(h) for h in re.findall(r"<h1[^>]*>(.*?)</h1>", markup(page), re.S)]

# A server function's answer is seroval's JSON; read for the shapes these
# return: objects, arrays, strings, numbers, and TanStack Start's Error.
def seroval(node):
    t = node.get("t")
    if t in (0, 1):
        return node["s"]
    if t == 9:
        return [seroval(x) for x in node["a"]]
    if t == 10:
        return dict(zip(node["p"]["k"], (seroval(v) for v in node["p"]["v"])))
    if t == 25:
        return {"$error": seroval(node["s"]["message"])}
    raise ValueError(f"unexpected seroval node {node}")
def result(body, key="result"):
    try:
        return seroval(json.loads(body)).get(key)
    except Exception as e:  # reported as the value, so the failure names it
        return f"unreadable ({e}): {body[:80]!r}"
# Each server function's id, from the build's own resolver.
resolver = open(glob.glob(f"{app}/dist/server/assets/*tanstack-start-server-fn-resolver-*.js")[0]).read()
fn_ids = {m.group(2): m.group(1) for m in re.finditer(
    r'"([0-9a-f]{64})": \{\s*functionName: "(\w+)_createServerFn_handler"', resolver)}
for fn in ("getTodos", "addTodo", "getPunkSongs"):
    if fn not in fn_ids:
        sys.exit(f"FAIL: the build's server-function resolver has no {fn} ({sorted(fn_ids)})")
def serverfn(fn, data=None, cookie=None, origin=None, method="GET"):
    """Call a server function as the browser's client does (createServerFn's RPC)."""
    headers = {"x-tsr-serverFn": "true", "accept": "application/x-tss-framed, application/x-ndjson, application/json"}
    if cookie:
        headers["cookie"] = cookie
    body = None
    if method == "POST":
        headers |= {"content-type": "application/json", "origin": origin or base}
        body = subprocess.run(["node", payload_js, app, json.dumps(data)],
                              capture_output=True, text=True, check=True).stdout.encode()
    else:
        headers["sec-fetch-site"] = "same-origin"  # as a browser's fetch sends it
    return get(f"/_serverFn/{fn_ids[fn]}", data=body, headers=headers, method=method)

# / — rendered by the Worker: the welcome page, the site's name its title.
status, _, body = get("/")
page = body.decode()
if status != 200:
    bad(f"/ answered {status}")
if title(page) != name:
    bad(f"the home page's <title> is {title(page)!r}, not {name!r}")
if "TanStack Start Starter" in page or "tanstack-start" in page:
    bad("the home page still carries the baseline's name")
if "TANSTACK START" not in h1s(page) or "Powerful Server Functions" not in text(markup(page)):
    bad(f"the home page is not the welcome page (headings {h1s(page)})")
for nav in ('href="/"', 'href="/demo/start/server-funcs"', 'href="/demo/start/api-request"', 'href="/demo/start/ssr"'):
    if nav not in page:
        bad(f"the home page's navigation has no {nav}")

# The hashed client build the page boots from, and the static files.
built = sorted(set(re.findall(r'(?:href|src)="(/assets/[^"]+\.(?:js|css))"', page)))
css, js = [b for b in built if b.endswith(".css")], [b for b in built if b.endswith(".js")]
if not css or not js:
    bad(f"the home page references no hashed JS and CSS: {built}")
for asset in css[:1] + js[:3]:
    s, h, _ = get(asset)
    want = "text/css" if asset.endswith(".css") else "javascript"
    if s != 200 or want not in (h.get("content-type") or ""):
        bad(f"{asset} answered {s} {h.get('content-type')}")
for path, ctype in (("/tanstack-circle-logo.png", "image/png"),
                    ("/tanstack-word-logo-white.svg", "image/svg+xml"), ("/robots.txt", "text/plain")):
    s, h, _ = get(path)
    if s != 200 or not (h.get("content-type") or "").startswith(ctype):
        bad(f"{path} answered {s} {h.get('content-type')}, want 200 {ctype}")

# The API route, and the page whose browser reads it.
s, h, body = get("/demo/api/names")
if s != 200 or "application/json" not in (h.get("content-type") or "") or json.loads(body) != ["Alice", "Bob", "Charlie"]:
    bad(f"/demo/api/names answered {s} {h.get('content-type')} {body[:80]!r}")
s, _, body = get("/demo/start/api-request")
if s != 200 or "Start API Request Demo - Names List" not in h1s(body.decode()) or title(body.decode()) != name:
    bad(f"/demo/start/api-request answered {s} with {h1s(body.decode())}")

# The SSR modes: one GET server function, rendered three ways.
songs = ["Teenage Dirtbag", "Smells Like Teen Spirit", "The Middle", "My Own Worst Enemy", "Fat Lip",
         "All the Small Things", "Beverly Hills"]
s, _, body = get("/demo/start/ssr/")
if s != 200 or not all(f'href="/demo/start/ssr/{m}"' in body.decode() for m in ("spa-mode", "full-ssr", "data-only")):
    bad(f"/demo/start/ssr/ answered {s} without its three links")
for mode, in_markup, in_page in (("full-ssr", True, True), ("data-only", False, True), ("spa-mode", False, False)):
    s, _, body = get(f"/demo/start/ssr/{mode}")
    page = body.decode()
    shown = all(x in text(markup(page)) for x in songs)
    carried = all(x in page for x in songs)
    if s != 200 or shown != in_markup or carried != in_page:
        bad(f"/demo/start/ssr/{mode} answered {s}: the songs rendered {shown} (want {in_markup}), "
            f"anywhere in the page {carried} (want {in_page})")
s, _, body = serverfn("getPunkSongs")
got = result(body)
got = [x["name"] for x in got] if isinstance(got, list) else got
if s != 200 or got != songs:
    bad(f"getPunkSongs, called as SPA mode's browser calls it, answered {s}: {got}")

# The todos: a GET server function in the loader, a POST one that adds, the
# list in the visitor's own cookie. A browser is stood in for by a one-cookie
# jar: each response's Set-Cookie is kept and sent with the next request.
jar = {}
def keep(h):
    for line in h.get_all("set-cookie") or []:
        pair, _, attrs = line.partition(";")
        k, _, v = pair.strip().partition("=")
        if k != "todos":
            continue
        a = [x.strip().lower() for x in attrs.split(";")]
        if "path=/" not in a or "httponly" not in a or "samesite=lax" not in a:
            bad(f"the todos cookie is not httpOnly, SameSite=Lax and Path=/: {line}")
        if "secure" in a:
            bad(f"the todos cookie is Secure over plain http, where a browser would drop it: {line}")
        jar[k] = v
def cookie():
    return "; ".join(f"{k}={v}" for k, v in jar.items()) or None
def todos():
    s, _, body = get("/demo/start/server-funcs", headers={"cookie": cookie()} if cookie() else {})
    page = body.decode()
    if s != 200:
        bad(f"/demo/start/server-funcs answered {s}")
    if title(page) != name:
        bad(f"/demo/start/server-funcs's <title> is {title(page)!r}, not {name!r}")
    return [text(x) for x in re.findall(r'<span class="text-lg text-white">(.*?)</span>', markup(page), re.S)]
def names(value):
    return [x["name"] for x in value] if isinstance(value, list) else value
starter = ["Get groceries", "Buy a new phone"]
if todos() != starter:
    bad(f"a visitor with no cookie does not start with the template's two todos: {todos()}")
item = f"Tell {name} hello"
s, h, body = serverfn("addTodo", data=item, method="POST")
keep(h)
if s != 200 or names(result(body)) != starter + [item] or not jar:
    bad(f"addTodo answered {s} {names(result(body))}, its cookie {'set' if jar else 'not set'}")
if todos() != starter + [item]:
    bad(f"the page, read with the cookie addTodo set, lists {todos()}")
s, _, body = serverfn("getTodos", cookie=cookie())
if s != 200 or names(result(body)) != starter + [item]:
    bad(f"getTodos, called as the browser calls it on a client-side visit, answered {s}: {names(result(body))}")
before = dict(jar)
s, h, body = serverfn("addTodo", data="   ", cookie=cookie(), method="POST")
keep(h)
refused = result(body, "error")
refused = refused.get("$error") if isinstance(refused, dict) else refused
if refused != "A todo needs some text." or jar != before:
    bad(f"an empty todo was not refused with its reason, or it changed the cookie: {s} {refused!r}")
s, h, _ = serverfn("addTodo", data="from elsewhere", cookie=cookie(), origin="https://elsewhere.example", method="POST")
if s != 403 or h.get_all("set-cookie"):
    bad(f"a cross-origin addTodo answered {s}, not a 403 with nothing written")
if todos() != starter + [item]:
    bad(f"the list changed after the refused posts: {todos()}")
print("     the todos: the starter list; one added, read back by the page and by getTodos with its cookie; "
      "an empty one and a cross-origin one refused")

# An unknown path: TanStack Router's not-found page, in the layout, with a 404.
s, _, body = get("/no-such-page")
nf = body.decode()
if s != 404 or "<p>Not Found</p>" not in nf or 'href="/demo/start/server-funcs"' not in nf:
    bad(f"/no-such-page answered {s} without the not-found page in the layout")

# The stage Worker says who may frame it: orun.work's preview pane shows a
# site's stage deploy in an iframe. Every response the Worker renders carries
# the policy — a page, a 404, the API route, a server function; the static
# files never reach the Worker and carry none.
ORUN_WORK = ("https://orun-agent-web-stage.oruncloud.workers.dev",
             "https://orun-agent-web-prod.oruncloud.workers.dev")
for path in ("/", "/demo/start/server-funcs", "/demo/start/ssr/spa-mode", "/no-such-page", "/demo/api/names"):
    _, h, _ = get(path)
    csp = h.get_all("content-security-policy") or []
    framing = [c for c in csp if c.startswith("frame-ancestors ")]
    if len(framing) != 1 or not all(o in framing[0].split() for o in ORUN_WORK + ("'self'",)):
        bad(f"{path} on stage does not let orun.work frame it: Content-Security-Policy {csp}")
_, h, _ = serverfn("getTodos")
if not any(c.startswith("frame-ancestors ") for c in h.get_all("content-security-policy") or []):
    bad("a server function's answer from the stage Worker carries no framing policy")
_, h, _ = get("/robots.txt")
if h.get_all("content-security-policy"):
    bad(f"/robots.txt, a static file, carries {h.get_all('content-security-policy')} — the Worker never saw it")
print("     framing: every page the stage Worker renders lets orun.work's preview pane frame it")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print("   /, the client build, the static files, the API route and its page, the three SSR modes, "
      "the todos, a 404, the stage framing policy — the site's own")
PY

echo "e2e.test.sh: ok"
