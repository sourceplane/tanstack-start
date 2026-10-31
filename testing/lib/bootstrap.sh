#!/usr/bin/env bash
# The offline bootstrap: every phase of repo-blueprint.yaml, placed by orun and
# finished by the blueprint's own `run:` hooks, in order, the way a real
# `orun new --run-hooks --resume` takes a site from nothing to its last
# landing — minus the platform. Sourced by placement.test.sh and e2e.test.sh.
#
#   bootstrap_offline <root> <tree> <values.json> <log-dir> [until-phase]
#   bootstrap_init    <tree>
#   bootstrap_phase   <root> <tree> <values.json> <log-dir> <phase>
#
# `bootstrap_offline` is `bootstrap_init`, then `bootstrap_phase` for every
# phase in order, stopping after `until-phase` when one is named (a code-only
# build stops after the scaffold stage: `--until 01-scaffold`). A build that
# goes on LATER — the live stage of a code-only app, with the late-bound
# subdomain it did not have before — is `bootstrap_phase` on the same tree.
#
# What stands in for the platform:
#   - the typed actions (`uses:` — task, repo, reconcile, land, watch, probe)
#     are skipped; a landing becomes a commit on `main`, which is what the
#     next phase's placement sees on the real thing too;
#   - the repository's first commit is an empty one, as on the real thing:
#     the platform's landing opens the first pull request against an empty
#     "Initial commit" by `orun`, and that commit is the base the first
#     landing's push is planned against;
#   - `link` (a `run:` hook that calls `orun cloud`) is skipped — it needs a
#     workspace;
#   - `{{ .inputs.* }}` render from the fixture.
# Everything else — the rebrand, the re-tenant, the work-tree strip, the
# deferrals and their restore, the subdomain bound, the retouch marker, the
# deployment-docs render — runs exactly as declared.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git.

# The values file as `--set k=v` arguments, one per line pair.
_bootstrap_sets() {
  python3 - "$1" <<'PY'
import json, sys
for k, v in json.load(open(sys.argv[1])).items():
    if not k.startswith("_"):
        print("--set")
        print(f"{k}={'true' if v is True else 'false' if v is False else v}")
PY
}

bootstrap_init() {
  local tree="$1" d
  mkdir -p "$tree"/{apps,infra,packages,tests}
  for d in apps infra packages tests; do touch "$tree/$d/.gitkeep"; done
  (
    cd "$tree"
    git init -q -b main
    git config user.email bootstrap@example.invalid
    git config user.name "offline bootstrap"
    git commit -q --allow-empty -m "Initial commit"
  ) || { echo "FAIL: the repository's first commit" >&2; return 1; }
}

bootstrap_phase() {
  local root="$1" tree="$2" values="$3" logs="$4" phase="$5"
  local sets=() select=(--phase "$phase") first
  mapfile -t sets < <(_bootstrap_sets "$values")
  # The FIRST phase is placed the way a code-only build places it, `--until`:
  # an orun that reads `lateBound` lets only a run that stops before the last
  # phase keep a late-bound input's placeholder, and refuses `--phase` without
  # the value. For the first phase the two select the same thing; for a later
  # one `--until` would place its predecessors again, so they take `--phase`.
  first="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['phases'][0]['name'])" "$root/repo-blueprint.yaml")"
  [ "$phase" = "$first" ] && select=(--until "$phase")
  mkdir -p "$logs"
  echo "── $phase: place"
  if ! orun new --blueprint "$root/repo-blueprint.yaml" --out "$tree" "${select[@]}" \
       "${sets[@]}" > "$logs/place-$phase.log" 2>&1; then
    echo "FAIL: $phase did not place" >&2; tail -20 "$logs/place-$phase.log" >&2; return 1
  fi
  echo "── $phase: post hooks"
  if ! python3 "$root/testing/lib/run-hooks.py" "$root/repo-blueprint.yaml" "$phase" post \
       "$tree" "$root" "$values" --skip link > "$logs/hooks-$phase.log" 2>&1; then
    echo "FAIL: $phase's post hooks" >&2; tail -30 "$logs/hooks-$phase.log" >&2; return 1
  fi
  sed 's/^/  /' "$logs/hooks-$phase.log"
  # The landing: what the PR merges is what the next phase is placed onto.
  (
    cd "$tree"
    git config user.email bootstrap@example.invalid
    git config user.name "offline bootstrap"
    git checkout -q -B main 2>/dev/null || true
    git add -A
    git commit -q -m "land $phase" --allow-empty
  ) || { echo "FAIL: $phase did not commit" >&2; return 1; }
}

bootstrap_offline() {
  local root="$1" tree="$2" values="$3" logs="$4" until="${5:-}" phase
  bootstrap_init "$tree" || return 1
  for phase in $(python3 -c "import yaml,sys;print(' '.join(p['name'] for p in yaml.safe_load(open(sys.argv[1]))['phases']))" "$root/repo-blueprint.yaml"); do
    bootstrap_phase "$root" "$tree" "$values" "$logs" "$phase" || return 1
    [ "$phase" = "$until" ] && break
  done
  return 0
}
