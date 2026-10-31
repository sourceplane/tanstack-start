#!/usr/bin/env bash
# TIER 1 — the tree is placed, branded, and made to answer.
#
# A real bootstrap is `orun new --run-hooks --resume` against a workspace: it
# places each phase, runs that phase's hooks, lands a pull request and watches
# the convergence. Everything in that sentence except the platform can run
# here, offline, and this file runs it:
#
#   1. the whole blueprint placed in one go — orun runs `validate` and
#      `plan --dry-run` inside the produced tree and says so; asserted, because
#      a future orun that stopped running them would weaken this tier in silence;
#   2. THE OFFLINE BOOTSTRAP (testing/lib/bootstrap.sh) — every phase placed in
#      order onto what the previous one landed, finished by the blueprint's OWN
#      `run:` hooks (rebrand, re-tenant, work-tree strip, the deferrals, the
#      retouch marker, the deployment record), each landing a commit;
#   3. the product it ends with: branded with no residue, carrying nothing of
#      the factory, re-tenanted, its gates and deploy lanes restored, its
#      record rendered;
#   4. what the product's own CI would do with each merge: `orun plan` for a
#      push to main over exactly that commit — the scaffold's onto the
#      repository's empty first commit (dev's verify lane, nothing deployed,
#      no credential), the live stage's (the site deployed to stage and prod
#      side by side, nothing on dev, the Worker, the smoke and the secret refs
#      the product's own), the record's (nothing);
#   5. a `--resume` over the finished site places nothing and un-brands
#      nothing;
#   6. THE CODE-ONLY SITE (saas-orun-work WA5): a build with no subdomain
#      stopped after 01-scaffold — the placeholder in place, the deploy lanes
#      parked, main's plan deploying nothing — then taken live later with
#      the account's subdomain, ending on exactly the tree the full build
#      ended on.
#
# testing/e2e.test.sh goes on from here: it installs, builds and serves the
# product and runs its smoke against it.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git. No credential. The
# deployment-record probes reach the network if they can, and pass without it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git; do
  command -v "$bin" >/dev/null || { echo "placement.test.sh needs $bin on PATH" >&2; exit 1; }
done

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
fails=0
fail() { echo "  ✕ $*" >&2; fails=$((fails + 1)); }
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"

sets=()
while IFS=$'\t' read -r k v; do sets+=( --set "$k=$v" ); done < <(
  python3 - "$values" <<'PY'
import json, sys
for k, v in json.load(open(sys.argv[1])).items():
    if not k.startswith("_"):
        print(f"{k}\t{'true' if v is True else 'false' if v is False else v}")
PY
)

# ── 1. the whole blueprint, one placement ──────────────────────────────────
echo "── placing the whole blueprint at once (offline, no credential)"
whole="$scratch/whole"
mkdir -p "$whole"/{apps,infra,packages,tests}
for d in apps infra packages tests; do touch "$whole/$d/.gitkeep"; done
if ! orun new --blueprint "$root/repo-blueprint.yaml" --out "$whole" "${sets[@]}" > "$scratch/whole.log" 2>&1; then
  echo "FAIL: the placement did not run" >&2; tail -20 "$scratch/whole.log" >&2; exit 1
fi
# The line's wording moved between orun releases (v2.58: `repo gate: validate +
# plan --dry-run passed`; v2.79: `Verified  intent valid · N components …`).
grep -Eq "repo gate: validate \+ plan --dry-run passed|Verified +intent valid" "$scratch/whole.log" \
  || fail "the placement did not report the repo-scale gate (orun validate + plan --dry-run inside the tree)"
n="$(find "$whole" -type f -not -path '*/.orun/*' | wc -l | tr -d ' ')"
[ "$n" -ge 50 ] || fail "only $n files placed — that is not a site"
[ "$fails" -eq 0 ] && echo "   $n files placed; the repo-scale gate ran"

# ── 2. the offline bootstrap ───────────────────────────────────────────────
echo "── the offline bootstrap: every phase, its own hooks, a landing each"
tree="$scratch/$repo"     # named as the repository is: orun names the project after it
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
grep -E '^── ' "$scratch/bootstrap.log" | sed 's/^/  /'
commits="$(git -C "$tree" rev-list --count HEAD)"
[ "$commits" = 4 ] || fail "the repository has $commits commits, not its first one and one per phase (1 + 3)"

# ── 3. the product it ends with ────────────────────────────────────────────
echo "── the site it produced"
(cd "$tree" && node "$root/tooling/rebrand/rebrand.mjs" --verify --values .rebrand/values.json) > "$scratch/verify.log" 2>&1 \
  || { fail "rebrand --verify found the baseline's identity in the site:"; sed 's/^/      /' "$scratch/verify.log" >&2; }

python3 - "$tree" "$values" "$root" <<'PY' || fails=$((fails + 1))
import json, pathlib, re, subprocess, sys
import yaml
tree, values, root = pathlib.Path(sys.argv[1]), json.load(open(sys.argv[2])), pathlib.Path(sys.argv[3])
problems = []
def bad(m): problems.append(m)
repo, org, name, sub = values["reponame"], values["githuborg"], values["productname"], values["subdomain"]

tracked = subprocess.run(["git", "ls-files"], cwd=tree, capture_output=True, text=True, check=True).stdout.split()

# Nothing of the factory, nothing local, exactly the two context pages.
NEVER = (".baseline/", "specs/", "tasks/", "testing/", "hooks/", "docs/phases/",
         "tooling/rebrand/", "tooling/bootstrap/", "tooling/migrations/",
         ".github/workflows/baseline.yml", ".github/workflows/tag.yml", "BOOTSTRAP.md",
         "repo-blueprint.yaml", "blueprint.yaml")
for p in tracked:
    if any(p == n or p.startswith(n) for n in NEVER):
        bad(f"{p} is in the site — it is the factory")
    if re.search(r"(^|/)(\.env(\.local)?|\.dev\.vars|node_modules|\.orun|\.tanstack|\.wrangler)(/|$)", p):
        bad(f"{p} is in the site — a local or built file")

# …and no file the site carries NAMES the factory: a comment pointing at
# `testing/` or a link into `specs/` is a dangling reference in somebody
# else's repository. (The baseline's intent.yaml names `specs/` and `tasks/`
# in its `work:` block; 01-product strips the block, so the site's must not.)
FACTORY_REF = re.compile(r"testing/|repo-blueprint|specs/|(^|[^A-Za-z0-9_-])tasks/|BOOTSTRAP\.md|\.baseline/|docs/phases")
for p in tracked:
    if p.startswith(".rebrand/"):
        continue
    try:
        text = (tree / p).read_text()
    except (UnicodeDecodeError, IsADirectoryError):
        continue
    for n, line in enumerate(text.splitlines(), 1):
        if FACTORY_REF.search(line):
            bad(f"{p}:{n} names the factory: {line.strip()[:80]}")
ai = {p for p in tracked if p.startswith("ai/")}
if ai != {"ai/context/deployment.md", "ai/context/operations.md"}:
    bad(f"ai/ in the site is {sorted(ai)}")

# The identity, where the site carries it.
site = (tree / "apps/web/src/lib/site.ts").read_text()
if f"export const SITE_NAME = {json.dumps(name)}\n" not in site:
    bad(f"apps/web/src/lib/site.ts does not name the site {name!r}")
comp = yaml.safe_load((tree / "apps/web/component.yaml").read_text())["spec"]["parameters"]
if comp["workerName"] != f"{repo}-web":
    bad(f"workerName is {comp['workerName']}, not {repo}-web")
if comp["workersDevSubdomain"] != sub:
    bad(f"workersDevSubdomain is {comp['workersDevSubdomain']}, not {sub}")
wrangler = json.loads(re.sub(r"^\s*//.*$", "", (tree / "apps/web/wrangler.jsonc").read_text(), flags=re.M))
if wrangler["name"] != f"{repo}-web":
    bad(f"wrangler.jsonc names the Worker {wrangler['name']}, not {repo}-web")
# The deploy reads wrangler.jsonc, and the component checks the build's output
# where it says: the two must name the same Worker entry and assets.
if wrangler["main"] != comp["workerEntrypoint"] or wrangler["assets"]["directory"] != comp["assetsDir"]:
    bad(f"wrangler.jsonc ({wrangler['main']}, {wrangler['assets']['directory']}) and the component "
        f"({comp['workerEntrypoint']}, {comp['assetsDir']}) disagree on the build's output")
if json.loads((tree / "package.json").read_text())["name"] != repo:
    bad("package.json is not named for the site")

# The intent: re-tenanted, no work tree, both gates back.
intent_text = (tree / "intent.yaml").read_text()
intent = yaml.safe_load(intent_text)
if intent["metadata"]["name"] != repo:
    bad(f"intent metadata.name is {intent['metadata']['name']}")
if intent["execution"]["state"]["workspace"] != values["orunWorkspace"]:
    bad(f"intent workspace is {intent['execution']['state']['workspace']}, not the site's")
if "work" in intent:
    bad("intent.yaml still declares the baseline's work tree")
if "promotion" not in intent["environments"]["prod"] or "@promotion-deferred" in intent_text:
    bad("prod's promotion gate was not restored by 03-docs")
if "github-push-main" not in intent["environments"]["dev"]["activation"]["triggerRefs"] or "@dev-lanes-deferred" in intent_text:
    bad("dev's push activation was not restored by 03-docs")
for env in ("stage", "prod"):
    if "github-push-main" not in intent["environments"][env]["activation"]["triggerRefs"]:
        bad(f"{env}'s push activation (its deploy lane) was not restored by 02-live")
if "@deploys-deferred" in intent_text:
    bad("intent.yaml still carries a @deploys-deferred marker")
if json.loads((tree / ".rebrand/values.json").read_text()).get("subdomain") != sub:
    bad("the identity file does not record the site's subdomain")
for env in ("stage", "prod"):
    want = f"https://{repo}-web-{env}.{sub}.workers.dev"
    if intent["environments"][env].get("url") != want:
        bad(f"environments.{env}.url is {intent['environments'][env].get('url')}, not {want}")
for page in (intent.get("repo") or {}).get("docs", {}).get("pages", []):
    if not (tree / page["path"]).exists():
        bad(f"intent repo.docs names {page['path']}, which the site does not have")

# The landings, as the phases made them.
if not re.search(r"^# orun: redeploy 02-live \S+$", (tree / "apps/web/component.yaml").read_text(), re.M):
    bad("apps/web/component.yaml carries no 02-live redeploy marker")
dep = (tree / "ai/context/deployment.md").read_text()
if "GENERATED by the `03-docs` phase" not in dep or f"https://{repo}-web-prod.{sub}.workers.dev" not in dep:
    bad("ai/context/deployment.md was not rendered for the site")
readme = (tree / "README.md").read_text()
if not readme.startswith(f"# {repo}\n") or "This site is **live**" not in readme:
    bad("README.md is not the site's, or its live-deployment section was not rendered")

# Provenance prose, over the BRANDED files.
PROV = re.compile(r"\bfork(ed)? (of|from)\b|\bbaseline (repo|repository|commit|tag)\b|repo-blueprint|BOOTSTRAP\.md", re.I)
for rel in ("README.md", "ai/context/operations.md", "ai/context/deployment.md"):
    for n, line in enumerate((tree / rel).read_text().splitlines(), 1):
        if PROV.search(line):
            bad(f"{rel}:{n} speaks of the factory: {line.strip()[:70]}")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   {len(tracked)} tracked files; branded, re-tenanted, gates restored, record rendered")
PY

# ── 4. the product's own CI, over each merge ──────────────────────────────
# Each landing's push, as main sees it the moment its pull request merges.
echo "── orun plan in the site, for the push each landing merged"
s00="$(git -C "$tree" rev-parse HEAD~3)"; s01="$(git -C "$tree" rev-parse HEAD~2)"
s02="$(git -C "$tree" rev-parse HEAD~1)"; s03="$(git -C "$tree" rev-parse HEAD)"
push_plan() { # TREE BASE HEAD OUT — `orun plan` for a push to main, at HEAD
  local t="$1" base="$2" head="$3" out="$4"
  git -C "$t" checkout -q "$head"
  (cd "$t" && orun validate --intent intent.yaml) > "$out.validate.log" 2>&1 \
    || { fail "orun validate refused the site's intent at $head"; tail -10 "$out.validate.log" >&2; }
  (cd "$t" && orun plan --intent intent.yaml --trigger github-push-main --changed \
     --base "$base" --head "$head" --output "$out") > "$out.log" 2>&1 \
    || { fail "orun plan failed in the site at $head"; tail -15 "$out.log" >&2; }
  git -C "$t" checkout -q main
}
push_plan "$tree" "$s00" "$s01" "$scratch/plan-01.json"
push_plan "$tree" "$s01" "$s02" "$scratch/plan-02.json"
push_plan "$tree" "$s02" "$s03" "$scratch/plan-03.json"
python3 - "$scratch" "$values" <<'PY' || fails=$((fails + 1))
import json, sys
scratch, values = sys.argv[1], json.load(open(sys.argv[2]))
repo, sub, ws = values["reponame"], values["subdomain"], values["orunWorkspace"]
problems = []
def bad(m): problems.append(m)
def jobs(n):
    try:
        plan = json.load(open(f"{scratch}/plan-{n}.json"))
    except FileNotFoundError:
        bad(f"no plan for the {n} merge")
        return {}
    return {(j["component"], j["environment"]): j for j in plan["jobs"]}

# The scaffold: the deploy lanes are parked, so the push plans dev's verify
# lane — built and dry-deployed — binds no credential, and deploys nothing.
scaffold = jobs("01")
if set(scaffold) != {("web", "dev")}:
    bad(f"the 01-scaffold merge plans {sorted(scaffold)}; it must verify web on dev and deploy nothing")
for (comp, env), j in scaffold.items():
    if not j["profile"].endswith(".verify"):
        bad(f"the 01-scaffold merge plans {comp}@{env} with {j['profile']}, not a verify")
    if j.get("secretRefs"):
        bad(f"the 01-scaffold merge's {comp}@{env} resolves {[r['asEnv'] for r in j['secretRefs']]} — "
            f"a code-only site has no credential to give it")

# The live stage: the site deployed to stage and prod side by side.
live = jobs("02")
if set(live) != {("web", "stage"), ("web", "prod")}:
    bad(f"the 02-live merge plans {sorted(live)}; it must deploy web to stage and prod and nothing else")
for (comp, env), j in live.items():
    if not j["profile"].endswith(".deploy"):
        bad(f"{comp}@{env} plans profile {j['profile']}, not a deploy")
    if j.get("dependsOn"):
        bad(f"{comp}@{env} waits on {j['dependsOn']} — during the bootstrap stage and prod deploy side by side")
    steps = {s["id"]: s.get("run") or "" for s in j["steps"]}
    for need in ("build-app", "deploy", "smoke"):
        if need not in steps:
            bad(f"{comp}@{env} has no {need} step")
    if f'export DEPLOY_ENV="{env}"' not in steps.get("build-app", ""):
        bad(f"{comp}@{env}'s build is not told its environment (DEPLOY_ENV) — the stage Worker's framing policy needs it")
    if f'EFFECTIVE_WORKER_NAME="{repo}-web-{env}"' not in steps.get("deploy", ""):
        bad(f"{comp}@{env} deploys a Worker not named {repo}-web-{env}")
    if f'DEPLOYED_URL="https://${{EFFECTIVE_WORKER_NAME}}.${{WORKERS_DEV_SUBDOMAIN}}.workers.dev"' not in steps.get("smoke", "") \
            or f'WORKERS_DEV_SUBDOMAIN="{sub}"' not in steps.get("smoke", ""):
        bad(f"{comp}@{env}'s smoke does not target the site's own workers.dev URL")
    if 'href="/demo/start/server-funcs"' not in steps.get("smoke", "") or "<p>Not Found</p>" not in steps.get("smoke", "") \
            or "/demo/api/names" not in steps.get("smoke", ""):
        bad(f"{comp}@{env}'s smoke is not the site's")
    refs = {r["asEnv"]: r["ref"] for r in j.get("secretRefs") or []}
    for key in ("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"):
        ref = refs.get(key, "")
        if not ref.startswith(f"secret://{ws}/") or f"project:{repo}" not in ref:
            bad(f"{comp}@{env} resolves {key} from {ref or 'nowhere'} — not the site's workspace and project")

# The record: intent.yaml's environments and the docs — no component.
docs = jobs("03")
if docs:
    bad(f"the 03-docs merge plans {sorted(docs)}; it changes no component and must deploy nothing")
if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print("   01-scaffold → web verified on dev, nothing deployed, no credential")
print("   02-live → web deployed to stage + prod side by side; Worker, smoke, secrets and DEPLOY_ENV the site's own")
print("   03-docs → nothing")
PY

# ── 5. a resume over the finished site ────────────────────────────────────
echo "── --resume over the finished site"
before="$(git -C "$tree" status --porcelain; git -C "$tree" rev-parse HEAD)"
orun new --blueprint "$root/repo-blueprint.yaml" --out "$tree" --resume "${sets[@]}" > "$scratch/resume.log" 2>&1 \
  || { fail "--resume did not run"; tail -10 "$scratch/resume.log" >&2; }
after="$(git -C "$tree" status --porcelain; git -C "$tree" rev-parse HEAD)"
[ "$before" = "$after" ] || { fail "--resume changed the finished site:"; git -C "$tree" status --short | head -10 >&2; }
grep -q "SITE_NAME = \"Sam's Notes & Links\"" "$tree/apps/web/src/lib/site.ts" \
  || fail "--resume reverted the site's identity"
[ "$fails" -eq 0 ] && echo "   nothing placed again, nothing un-branded"

# ── 6. a code-only site, then live ────────────────────────────────────────
# The build an account with no Cloudflare connection gets (`--until
# 01-scaffold`, the platform's `until: scaffold`): no subdomain to read, so
# the late-bound input falls to its placeholder.
echo "── a code-only site: --until 01-scaffold, with no subdomain"
code="$scratch/code-only/$repo"
python3 - "$values" "$scratch/code-only.json" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
v.pop("subdomain")
json.dump(v, open(sys.argv[2], "w"))
PY
bootstrap_offline "$root" "$code" "$scratch/code-only.json" "$scratch/code-logs" 01-scaffold \
  > "$scratch/code-only.log" 2>&1 || { echo "FAIL: the code-only bootstrap stopped" >&2; tail -40 "$scratch/code-only.log" >&2; exit 1; }
[ "$(git -C "$code" rev-list --count HEAD)" = 2 ] || fail "the code-only site is not its first commit and one landing"
(cd "$code" && node "$root/tooling/rebrand/rebrand.mjs" --verify --values .rebrand/values.json) > "$scratch/code-verify.log" 2>&1 \
  || { fail "rebrand --verify refused the code-only site"; cat "$scratch/code-verify.log" >&2; }
[ "$(cd "$code" && node "$root/tooling/bootstrap/subdomain.mjs" --check)" = placeholder ] \
  || fail "the code-only site does not record the placeholder subdomain"
for t in deploys:deferred promotion:enforced dev-lanes:active; do
  [ "$(node "$root/tooling/bootstrap/${t%%:*}.mjs" --check --file "$code/intent.yaml")" = "${t#*:}" ] \
    || fail "the code-only site's ${t%%:*} is not ${t#*:}"
done
push_plan "$code" "$(git -C "$code" rev-parse HEAD~1)" "$(git -C "$code" rev-parse HEAD)" "$scratch/plan-code.json"
python3 - "$scratch/plan-code.json" <<'PY' || fails=$((fails + 1))
import json, sys
jobs = [(j["component"], j["environment"], j["profile"].split(".")[-1], bool(j.get("secretRefs")))
        for j in json.load(open(sys.argv[1]))["jobs"]]
if jobs != [("web", "dev", "verify", False)]:
    print(f"  ✕ the code-only site's merge plans {jobs}; CI on main must verify on dev and deploy nothing", file=sys.stderr)
    sys.exit(1)
print("   placeholder subdomain, deploy lanes parked; main's plan: web verified on dev, nothing deployed")
PY

# …and later, live: the account connected, its subdomain known. A fresh
# container carries no `.orun/` (no checkout does), so nothing recorded the
# placeholder there; an orun that reads `lateBound` lets the live run differ
# from the record even in the container that ran the scaffold.
echo "── the same site taken live later: 02-live and 03-docs, with the subdomain"
rm -rf -- "$code/.orun"
for phase in 02-live 03-docs; do
  bootstrap_phase "$root" "$code" "$values" "$scratch/code-logs" "$phase" > "$scratch/code-$phase.log" 2>&1 \
    || { echo "FAIL: the code-only site's $phase" >&2; tail -40 "$scratch/code-$phase.log" >&2; exit 1; }
done
grep -q 'subdomain --bind: .* bound in ' "$scratch/code-logs/hooks-02-live.log" \
  || fail "02-live did not bind the subdomain into the code-only site"
# The resume does not place 01-scaffold's files again, so 02-live's own hook
# is all that replaces the placeholder: nowhere in the site may it be left.
left="$(cd "$code" && git grep -l -E '(^|[^A-Za-z0-9-])your-workers-subdomain([^A-Za-z0-9-]|$)' || true)"
[ -z "$left" ] || fail "the placeholder subdomain is still in the code-only site after 02-live: $left"
push_plan "$code" "$(git -C "$code" rev-parse HEAD~2)" "$(git -C "$code" rev-parse HEAD~1)" "$scratch/plan-code-live.json"
python3 - "$scratch/plan-code-live.json" <<'PY' || fails=$((fails + 1))
import json, sys
jobs = sorted((j["component"], j["environment"], j["profile"].split(".")[-1])
              for j in json.load(open(sys.argv[1]))["jobs"])
if jobs != [("web", "prod", "deploy"), ("web", "stage", "deploy")]:
    print(f"  ✕ the code-only site's 02-live merge plans {jobs}; it must deploy web to stage and prod", file=sys.stderr)
    sys.exit(1)
PY
# It ends where the full build ended: the same tree, but for the stamps of
# when each one ran (the redeploy marker, the record's probe time).
if diff -r -x .git -x .orun \
     -I '^# orun: redeploy ' -I 'GENERATED by the `03-docs` phase on' -I '^## Public URLs (probed ' \
     "$tree" "$code" > "$scratch/code-vs-full.diff"; then
  echo "   02-live bound the subdomain and deployed; the site is the full build's, byte for byte"
else
  fail "the code-only site taken live is not the tree the full build made:"; head -40 "$scratch/code-vs-full.diff" >&2
fi

[ "$fails" -eq 0 ] || { echo "placement.test.sh: $fails failure(s)" >&2; exit 1; }
echo "placement.test.sh: ok"
