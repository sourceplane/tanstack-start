#!/usr/bin/env bash
# THE LATE-BOUND SUBDOMAIN IS BOUND WHERE THE PLACEHOLDER STANDS, ONCE.
#
# A code-only site — a build that stopped after 01-scaffold, with no
# Cloudflare connection to read a workers.dev subdomain from — carries the
# placeholder `your-workers-subdomain` in its component, its intent, its
# operating contract and its identity file. 02-live's `subdomain` hook
# (tooling/bootstrap/subdomain.mjs --bind) writes the account's real
# subdomain there before anything deploys, and must:
#
#   - replace the placeholder as a whole DNS label, in every tracked file,
#     and record the value in .rebrand/values.json LAST;
#   - change nothing on a site that already has it (a build that ran both
#     stages at once), and nothing on a second run;
#   - refuse the placeholder and an empty value (the live stage may never
#     keep it), a value that is not a subdomain, and a MOVE from one real
#     subdomain to another;
#   - finish a bind that was interrupted.
#
# Needs: node, git, python3 (+PyYAML). No network.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
tool="$root/tooling/bootstrap/subdomain.mjs"
identity="$here/fixtures/baseline-identity.tanstack-start.json"
fail=0
ok() { echo "   ok  $1"; }
bad() { echo "   ✕  $1" >&2; fail=1; }
scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT

# A site as 01-scaffold leaves it without a subdomain: the four places the
# placeholder stands, and one file whose value merely CONTAINS it.
site() { # DIR SUBDOMAIN-RECORDED
  local d="$1" rec="$2"
  mkdir -p "$d/.rebrand" "$d/apps/web" "$d/ai/context" "$d/notes"
  cat > "$d/.rebrand/values.json" <<JSON
{
  "reponame": "acme-notes",
  "productname": "Acme Notes",
  "productdomain": "",
  "subdomain": "$rec",
  "orunWorkspace": "ws_X",
  "githuborg": "acme-inc",
  "epicSlug": "tanstack-start-baselining"
}
JSON
  printf 'spec:\n  parameters:\n    workersDevSubdomain: your-workers-subdomain\n' > "$d/apps/web/component.yaml"
  printf 'environments:\n  stage:\n    url: https://acme-notes-web-stage.your-workers-subdomain.workers.dev\n  prod:\n    url: https://acme-notes-web-prod.your-workers-subdomain.workers.dev\n' > "$d/intent.yaml"
  printf "curl https://acme-notes-web-stage.your-workers-subdomain.workers.dev/\n" > "$d/ai/context/operations.md"
  printf 'another site: https://x-web-stage.your-workers-subdomain-2.workers.dev\n' > "$d/notes/other.md"
  git -C "$d" init -q && git -C "$d" add -A
}
bind() { (cd "$1" && node "$tool" --baseline-identity "$identity" --bind "$2"); }
snapshot() { (cd "$1" && find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 cksum); }

echo "── a code-only site goes live"
s="$scratch/code-only"; site "$s" your-workers-subdomain
cp "$s/.rebrand/values.json" "$scratch/values.before"
bind "$s" acme > "$scratch/bind.log" 2>&1 || { bad "--bind acme failed"; cat "$scratch/bind.log" >&2; }
grep -q 'workersDevSubdomain: acme$' "$s/apps/web/component.yaml" && ok "the component's smoke URL takes the subdomain" || bad "component.yaml not bound"
[ "$(grep -c '\.acme\.workers\.dev' "$s/intent.yaml")" = 2 ] && ok "both environment URLs in intent.yaml" || bad "intent.yaml not bound"
grep -q 'acme-notes-web-stage\.acme\.workers\.dev' "$s/ai/context/operations.md" && ok "the operating contract's example" || bad "operations.md not bound"
grep -q 'your-workers-subdomain-2' "$s/notes/other.md" && ok "a subdomain that merely contains the placeholder is left alone" || bad "your-workers-subdomain-2 was rewritten"
changed_lines="$(diff "$scratch/values.before" "$s/.rebrand/values.json" | grep -c '^[<>]' || true)"
[ "$changed_lines" = 2 ] && grep -q '"subdomain": "acme",' "$s/.rebrand/values.json" \
  && ok ".rebrand/values.json records it, and only that line changed" || bad ".rebrand/values.json was not rewritten as one line"
[ "$(cd "$s" && node "$tool" --baseline-identity "$identity" --check)" = "bound acme" ] && ok "--check says bound acme" || bad "--check"
grep -q 'bound in 4 file' "$scratch/bind.log" && ok "it says which files it changed" || bad "the summary: $(cat "$scratch/bind.log")"

before="$(snapshot "$s")"
bind "$s" acme > "$scratch/again.log" 2>&1 || bad "a second --bind acme failed"
[ "$before" = "$(snapshot "$s")" ] && grep -q 'already bound' "$scratch/again.log" \
  && ok "a second bind changes nothing and says so" || bad "a second bind changed the tree"

echo "── what it refuses"
for value in your-workers-subdomain "" "Not_A_Subdomain" "-acme"; do
  t="$scratch/refuse-$RANDOM"; site "$t" your-workers-subdomain; b="$(snapshot "$t")"
  if bind "$t" "$value" > "$t.log" 2>&1; then
    bad "--bind '$value' passed"
  else
    [ "$b" = "$(snapshot "$t")" ] && ok "--bind '${value}' is refused, and nothing is written" || bad "--bind '$value' wrote before refusing"
  fi
done
grep -q 'needs the workers.dev subdomain' "$scratch"/refuse-*.log && ok "the refusal names what the live stage needs" \
  || bad "the placeholder's refusal does not say what is needed"
t="$scratch/moved"; site "$t" acme
sed -i 's/your-workers-subdomain\b/acme/; s/\.your-workers-subdomain\./.acme./g' "$t/apps/web/component.yaml" "$t/intent.yaml" "$t/ai/context/operations.md"
git -C "$t" add -A; b="$(snapshot "$t")"
if bind "$t" other > "$t.log" 2>&1; then bad "moving acme → other passed"; else
  [ "$b" = "$(snapshot "$t")" ] && grep -q 'bound to acme.workers.dev' "$t.log" \
    && ok "a site bound to acme is not moved to another account's subdomain" || bad "the move refusal wrote, or did not say why"
fi

echo "── a site built with its subdomain from the start"
t="$scratch/full"; site "$t" acme
sed -i 's/workersDevSubdomain: your-workers-subdomain$/workersDevSubdomain: acme/; s/\.your-workers-subdomain\./.acme./g' \
  "$t/apps/web/component.yaml" "$t/intent.yaml" "$t/ai/context/operations.md"
git -C "$t" add -A; b="$(snapshot "$t")"
bind "$t" acme > "$t.log" 2>&1 && [ "$b" = "$(snapshot "$t")" ] \
  && ok "binding the subdomain it already has changes nothing" || bad "a full build's bind changed the tree: $(cat "$t.log")"

echo "── an interrupted bind is finished by the next"
t="$scratch/half"; site "$t" your-workers-subdomain
sed -i 's/workersDevSubdomain: your-workers-subdomain$/workersDevSubdomain: acme/' "$t/apps/web/component.yaml"
git -C "$t" add -A
bind "$t" acme > "$t.log" 2>&1 && ! grep -rq 'your-workers-subdomain\.' "$t/intent.yaml" "$t/ai" \
  && grep -q '"subdomain": "acme"' "$t/.rebrand/values.json" \
  && ok "the record still named the placeholder, so the bind ran again over what was left" || bad "the half-done bind: $(cat "$t.log")"

echo "── the placeholder is the one the build document defaults to"
python3 - "$root" <<'PY' && ok "repo-blueprint.yaml's subdomain default = .baseline/identity.json's subdomain" || bad "the subdomain placeholder is spelled two ways"
import json, pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
default = yaml.safe_load((root / "repo-blueprint.yaml").read_text())["inputs"]["subdomain"]["default"]
declared = json.loads((root / ".baseline/identity.json").read_text())["subdomain"]
assert default == declared, (default, declared)
PY

[ "$fail" -eq 0 ] || { echo "subdomain.test.sh: failure(s)" >&2; exit 1; }
echo "subdomain.test.sh: ok"
