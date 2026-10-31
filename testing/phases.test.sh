#!/usr/bin/env bash
# The phases in `repo-blueprint.yaml` must be the phases the bootstrap runs,
# placing what they are meant to place, saying what they are, and naming only
# what the engine can resolve.
#
# The partition below is the bootstrap's order, written down a second time on
# purpose: the order is load-bearing (the deployment record cannot be written
# before the site is live), and a module that drifts into another phase fails
# at landing time, live, with nothing in this repository having looked wrong.
# Moving one is a deliberate change, argued in the diff that edits both places.
#
# ONE LANDING PLACES THE SITE (SK-5, cirrus-baseline baseline-v22's shape),
# AND THE BUILD SPLITS AT A DECLARED STAGE (saas-orun-work WA5): 01-scaffold
# places every module and lands them with GitHub alone, its deploy lanes
# parked; 02-live binds the late-bound subdomain, puts the lanes back, mints
# the Cloudflare credentials and watches the one convergence that deploys;
# 03-docs only records. blueprint.yaml's `spec.stages` names the two stages,
# and the stage rules below hold each to what it may need.
#
# And the shape that keeps a bootstrap fast (orun >= v2.88.0, turso-starter
# baseline-v8's): the run-level task set-up runs in the background, each
# phase finds its task just before its landing, each landing checks its
# commit here (`checks: local`), and the convergence watch reads every few
# seconds.
#
# Adapted from sourceplane/cirrus-baseline's testing/phases.test.sh: the
# narration rules and the hook-only rule are Cirrus's, unchanged.
#
# bash + python3 + PyYAML. No network, no fakes, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

echo "── repo-blueprint.yaml phases against what the bootstrap runs"
python3 - "$root" <<'PY'
import pathlib, re, sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required for the phase contract test (pip install pyyaml)")

root = pathlib.Path(sys.argv[1])
problems = []
def bad(m): problems.append(m)

bp = yaml.safe_load((root / "repo-blueprint.yaml").read_text())
phases = bp.get("phases") or []
if not phases:
    sys.exit("repo-blueprint.yaml declares no phases — this check has gone blind")

PARTITION = {
    # One deployable component, `web`: the site's tests run inside it
    # (apps/web's vitest), so there is no test package to place beside it.
    "01-scaffold": ["ai-deployment", "ai-operations", "discovery-roots", "github-workflows",
                    "rebrand-values", "root-gitignore", "root-intent",
                    "root-package-json", "root-pnpm-lock",
                    "root-pnpm-workspace", "root-readme", "root-turbo", "tooling-eslint",
                    "tooling-tsconfig", "tooling-wire", "vscode", "web"],
    "02-live": [],
    "03-docs": [],
}
HOOK_ONLY = {"02-live", "03-docs"}
# The phases that DEPLOY, and so must give a re-run something to land.
DEPLOYS = {"02-live"}
# Each phase's pre, post and await hooks, in order. The brokered keys are one
# `secrets` reconcile, in the live stage. No phase has a `pre` hook: the task
# is found in `post`, just before the landing, so that everything before it
# runs beside the background task set-up. 01-scaffold awaits nothing (its
# merge deploys nothing), nor does 03-docs (its render probes as it writes,
# and its landing redeploys nothing).
PRE = {"01-scaffold": [], "02-live": [], "03-docs": []}
POST = {
    "01-scaffold": ["git-init", "git-stage", "rebrand", "orun-workspace", "work-tree",
                    "deploys", "git-restage", "rebrand-verify", "repo", "link", "task", "land"],
    "02-live": ["subdomain", "deploys", "promotion", "dev-lanes", "retouch",
                "secrets", "task", "land"],
    "03-docs": ["promotion", "dev-lanes", "render", "task", "land"],
}
AWAIT = {"01-scaffold": [], "02-live": ["converge", "verify"], "03-docs": []}

by_name = {p["name"]: p for p in phases}
names = [p["name"] for p in phases]

# ── the order IS the execution order ──────────────────────────────────────
if names != sorted(names):
    bad(f"phases are not in execution order: {names}. The numbered name IS the "
        f"order; a phase out of sequence is a barrier in the wrong place.")
if names != list(PARTITION):
    bad(f"phases are {names}; the bootstrap runs {list(PARTITION)}")

# ── the partition has not drifted ─────────────────────────────────────────
for name, want in PARTITION.items():
    if name not in by_name:
        continue
    now = sorted(by_name[name].get("modules") or [])
    if now != sorted(want):
        bad(f"phase {name} no longer places what it placed: gained "
            f"{sorted(set(now) - set(want)) or '[]'}, lost {sorted(set(want) - set(now)) or '[]'}")
declared = {m["name"] for m in bp.get("modules") or []}
placed = {m for p in phases for m in (p.get("modules") or [])}
for m in sorted(declared - placed):
    bad(f"module {m} is declared and no phase places it")
for name in HOOK_ONLY:
    if by_name.get(name, {}).get("modules"):
        bad(f"phase {name} places modules — it is declared as hooks only")

# ── nothing may GATE on a phase the tree cannot answer for ────────────────
# A hook-only phase places no files, so orun derives it as `unknown`, and
# `requires.phases` fails closed on `unknown`: a requirement naming one can
# never be satisfied.
for p in phases:
    for need in ((p.get("requires") or {}).get("phases") or []):
        if need in HOOK_ONLY:
            bad(f"phase {p['name']} requires {need}, which places no files — require "
                f"its predecessor instead")
        if need not in by_name or names.index(need) >= names.index(p["name"]):
            bad(f"phase {p['name']} requires {need}, which does not run before it")

# ── every phase says what it is and what to budget ────────────────────────
for p in phases:
    for field in ("title", "expectedMinutes"):
        if not p.get(field):
            bad(f"phase {p['name']} declares no {field} — an operator reads both")
    if not (p.get("hooks") or {}):
        bad(f"phase {p['name']} declares no hooks — a phase that only places files "
            f"still has to land them")

def hooks_of(p):
    h = p.get("hooks") or {}
    if isinstance(h, list):
        return list(h)
    return [x for slot in ("pre", "post", "await") for x in (h.get(slot) or [])]

run_hooks = list((bp.get("hooks") or {}).get("preInstantiate") or [])

# ── every phase lands, and every landing is bound to its task ─────────────
for p in phases:
    ids = [h.get("id") for h in hooks_of(p)]
    lands = [h for h in hooks_of(p) if (h.get("uses") or "").startswith("orun.pr/land@")]
    if len(lands) != 1:
        bad(f"phase {p['name']} has {len(lands)} landing(s); a phase is ONE pull request")
        continue
    w = lands[0].get("with") or {}
    if w.get("task") != "{{ .phase.hooks.task.outputs.key }}":
        bad(f"phase {p['name']} lands without binding the PR to its task key")
    if "task" not in ids or ids.index("task") > ids.index(lands[0].get("id")):
        bad(f"phase {p['name']} must ensure its task before it lands")
    if p["name"] in DEPLOYS:
        if not any("retouch.mjs" in " ".join(h.get("run") or []) for h in hooks_of(p)):
            bad(f"phase {p['name']} deploys and has no retouch hook — a re-run after a "
                f"failed convergence would land an empty diff and redeploy nothing")
        awaits = (p.get("hooks") or {}).get("await") or []
        watch = [h for h in awaits if (h.get("uses") or "").startswith("orun.run/watch@")]
        if not watch or (watch[0].get("with") or {}).get("sha") != "{{ .phase.hooks.land.outputs.mergeSha }}":
            bad(f"phase {p['name']} deploys and does not watch the convergence of the "
                f"commit it merged (orun.run/watch@v1 with sha: mergeSha)")

# ── the hooks run in the one-landing order ────────────────────────────────
for name, want in PRE.items():
    got = [h.get("id") for h in ((by_name.get(name, {}).get("hooks") or {}).get("pre") or [])]
    if got != want:
        bad(f"phase {name}'s pre hooks are {got}; want {want} — a task found in `pre` waits "
            f"for the background task set-up before the phase has done anything")
for name, want in POST.items():
    got = [h.get("id") for h in ((by_name.get(name, {}).get("hooks") or {}).get("post") or [])]
    if got != want:
        bad(f"phase {name}'s post hooks are {got}; the one-landing order is {want}")
for name, want in AWAIT.items():
    got = [h.get("id") for h in ((by_name.get(name, {}).get("hooks") or {}).get("await") or [])]
    if got != want:
        bad(f"phase {name}'s await hooks are {got}; want {want}")
for p in phases:
    if p["name"] not in DEPLOYS:
        for h in hooks_of(p):
            if (h.get("uses") or "").startswith(("orun.integrations/reconcile@", "orun.run/watch@")):
                bad(f"phase {p['name']} deploys nothing and runs {h['uses']} ({h.get('id')})")

# ── EVERY DEFERRAL IS PUT BACK ────────────────────────────────────────────
# promotion.mjs, dev-lanes.mjs and deploys.mjs each park something in the
# site's intent.yaml for the bootstrap's sake. In phase order, each `--restore`
# must follow a `--defer`, and the last phase must leave nothing parked: a
# finished site deploys on every merge, prod after stage, dev verifying.
def tool_runs(p):
    for h in ((p.get("hooks") or {}).get("post") or []):
        argv = h.get("run") or []
        for tool in ("promotion", "dev-lanes", "deploys"):
            if any(a.endswith(f"tooling/bootstrap/{tool}.mjs") for a in argv):
                for mode in ("--defer", "--restore"):
                    if mode in argv:
                        yield tool, mode
for tool in ("promotion", "dev-lanes", "deploys"):
    state, seen = "active", []
    for p in phases:
        for t, mode in tool_runs(p):
            if t != tool:
                continue
            seen.append(f"{p['name']} {mode}")
            if mode == "--restore" and state != "deferred":
                bad(f"{p['name']} restores {tool}.mjs, which nothing before it deferred")
            state = "deferred" if mode == "--defer" else "active"
    if state != "active":
        bad(f"{tool}.mjs is deferred and never restored ({', '.join(seen)}) — the finished site "
            f"would keep the bootstrap's shortcut")

# ── THE STAGES (saas-orun-work WA5, blueprint.yaml `spec.stages`) ─────────
# SCAFFOLD needs GitHub only: no phase up to and including it may mint a
# credential, watch a convergence, probe a URL, ask for a provider other than
# github, or read a late-bound input (a code-only build does not have one);
# and it must park the deploy lanes before it lands, so main's CI deploys
# nothing. LIVE needs the card's `requires.integrations`: it asks for them,
# binds every late-bound input before it lands, puts the deploy lanes back,
# and deploys.
card = yaml.safe_load((root / "blueprint.yaml").read_text())
cspec = (card or {}).get("spec") or {}
stages = cspec.get("stages") or {}
late = {f.get("key") for f in cspec.get("inputs") or [] if f.get("lateBound") is True}
needs = [i for i in ((cspec.get("requires") or {}).get("integrations") or []) if i != "github"]
def expressions(p):
    """Every templated string a phase renders: argv, `with:`, narration, probes."""
    out = []
    def walk(v):
        if isinstance(v, str):
            out.append(v)
        elif isinstance(v, dict):
            for x in v.values():
                walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)
    walk(p.get("hooks") or {})
    walk(p.get("narrate") or {})
    walk(((p.get("requires") or {}).get("probe")) or [])
    return out
def post_ids(p):
    return [h.get("id") for h in ((p.get("hooks") or {}).get("post") or [])]
def runs(p, tool, mode):
    """The id of the post hook that runs tooling/bootstrap/<tool> <mode>, or None."""
    for h in ((p.get("hooks") or {}).get("post") or []):
        argv = h.get("run") or []
        if any(a.endswith(f"tooling/bootstrap/{tool}") for a in argv) and mode in argv:
            return h.get("id")
    return None
if not stages:
    bad("blueprint.yaml declares no spec.stages — the stage rules have nothing to hold")
else:
    sc, lv = stages.get("scaffold"), stages.get("live")
    if sc not in names or lv not in names:
        bad(f"spec.stages names {sc} and {lv}; the phases are {names}")
    else:
        for p in phases[: names.index(sc) + 1]:
            for h in hooks_of(p) + list(((p.get("requires") or {}).get("probe")) or []):
                u = h.get("uses") or ""
                if u.startswith(("orun.integrations/reconcile@", "orun.run/watch@", "orun.http/probe@")):
                    bad(f"{p['name']} is in the scaffold stage and runs {u} ({h.get('id')}) — "
                        f"scaffold needs GitHub only")
                if u.startswith("orun.doctor/check@"):
                    others = [x for x in ((h.get("with") or {}).get("providers") or []) if x != "github"]
                    if others:
                        bad(f"{p['name']} is in the scaffold stage and asks for {others} — "
                            f"scaffold needs GitHub only")
            for text in expressions(p):
                for key in sorted(late):
                    if re.search(rf"\.inputs\.{key}\b", text):
                        bad(f"{p['name']} is in the scaffold stage and reads the late-bound input "
                            f"{key} — a code-only build runs it without one")
        scp, lvp = by_name[sc], by_name[lv]
        if names.index(sc) >= names.index(lv):
            bad(f"scaffold {sc} does not run before live {lv}")
        defer = runs(scp, "deploys.mjs", "--defer")
        if not defer or post_ids(scp).index(defer) > post_ids(scp).index("land"):
            bad(f"{sc} does not park the deploy lanes (deploys.mjs --defer) before it lands — "
                f"main's CI would deploy without credentials")
        if lv not in DEPLOYS:
            bad(f"the live stage {lv} is not a deploying phase")
        restore = runs(lvp, "deploys.mjs", "--restore")
        if not restore or post_ids(lvp).index(restore) > post_ids(lvp).index("land"):
            bad(f"{lv} does not put the deploy lanes back (deploys.mjs --restore) before it lands")
        asked = set()
        for h in ((lvp.get("requires") or {}).get("probe")) or []:
            if (h.get("uses") or "").startswith("orun.doctor/check@"):
                asked |= set((h.get("with") or {}).get("providers") or [])
        for need in needs:
            if need not in asked:
                bad(f"the live stage {lv} does not ask for {need} (requires.probe), which the card "
                    f"requires — it would mint and deploy without checking the connection")
        for key in sorted(late):
            binds = [h.get("id") for h in ((lvp.get("hooks") or {}).get("post") or [])
                     if (h.get("run") and "--bind" in h["run"]
                         and any(f"{{{{ .inputs.{key} }}}}" == a for a in h["run"]))]
            if not binds or post_ids(lvp).index(binds[0]) > post_ids(lvp).index("land"):
                bad(f"the live stage {lv} does not bind the late-bound input {key} "
                    f"(a `--bind \"{{{{ .inputs.{key} }}}}\"` hook) before it lands")

# ── THE FAST SHAPE (orun >= v2.88.0) ──────────────────────────────────────
# The run-level list is the task set-up, all of it in the background: the
# first phase's provider check, placement, rebrand, repository and secrets
# run while it opens the epic, the milestones and the tasks.
for h in run_hooks:
    if not h.get("background"):
        bad(f"hooks.preInstantiate {h.get('id')} is not `background: true` — the first phase "
            f"waits for it before doing anything, though nothing before its landing reads it")
# A `pre` hook on the task plane would wait for that background at once,
# before the phase had placed a file — the old order, whatever its id.
TASK_PLANE = ("orun.task/", "orun.pr/")
for p in phases:
    for h in ((p.get("hooks") or {}).get("pre") or []):
        if (h.get("uses") or "").startswith(TASK_PLANE):
            bad(f"phase {p['name']}'s pre hook {h.get('id')} uses {h['uses']}, which waits for the "
                f"background task set-up — find the task in `post`, just before the landing")
# Every landing checks its commit here and merges, instead of waiting ~25 s
# for a runner to plan the tree this box just wrote.
for p in phases:
    for h in hooks_of(p):
        if (h.get("uses") or "").startswith("orun.pr/land@") and (h.get("with") or {}).get("checks") != "local":
            bad(f"phase {p['name']} lands with checks {(h.get('with') or {}).get('checks', 'ci')!r}, "
                f"not 'local' — it waits for a runner to plan a tree that is here")
# The convergence watch reads every few seconds, not the action's default 40.
for p in phases:
    for h in ((p.get("hooks") or {}).get("await") or []):
        if (h.get("uses") or "").startswith("orun.run/watch@"):
            every = (h.get("with") or {}).get("pollSeconds")
            if not isinstance(every, int) or every > 10:
                bad(f"phase {p['name']} watches its convergence every {every or 40} s; at most 10 — "
                    f"the build goes on that much after the run is green")

# ── every phase's task is one the run-level list opens, in the same order ─
def task_names(hooks):
    return [(h.get("with") or {}).get("name") for h in hooks
            if (h.get("uses") or "").startswith("orun.task/ensure@")
            and (h.get("with") or {}).get("kind") == "task"]
opened = task_names(run_hooks)
per_phase = [n for p in phases for n in task_names(hooks_of(p))]
if opened != per_phase:
    bad(f"the run-level list opens tasks {opened}; the phases ensure {per_phase} — "
        f"a task is found by its title, so the two must be the same words")
milestones = [(h.get("with") or {}).get("name") for h in run_hooks
              if (h.get("with") or {}).get("kind") == "milestone"]
if milestones != names:
    bad(f"the run-level list opens milestones {milestones}; the phases are {names}")

# ── every contract a hook names exists, beside the blueprint ──────────────
for h in run_hooks + [x for p in phases for x in hooks_of(p)]:
    rel = (h.get("with") or {}).get("contract")
    if rel and not (root / rel).exists():
        bad(f"hook {h.get('id')} names contract {rel}, which does not exist")
    if rel and not rel.startswith(".baseline/tasks/"):
        bad(f"hook {h.get('id')} names contract {rel} outside .baseline/tasks/ — "
            f"`tasks/` is this repository's own work tree, where an unkeyed "
            f"contract is an error")
for p in phases:
    for h in hooks_of(p):
        argv = " ".join(h.get("run") or [])
        for ref in re.findall(r"\{\{ \.baseline\.dir \}\}/(\S+?)(?:\"|'|\s|$)", argv + " "):
            if not (root / ref).exists():
                bad(f"phase {p['name']} hook {h.get('id')} runs {ref}, which this "
                    f"repository does not have")

# ── every phase has a documentation page, and every page a phase ──────────
docs_dir = root / "docs" / "phases"
pages = {f.stem for f in docs_dir.glob("*.md")} - {"README"}
for n in names:
    if n not in pages:
        bad(f"phase {n} has no page at docs/phases/{n}.md")
for page in sorted(pages - set(names)):
    bad(f"docs/phases/{page}.md documents a phase repo-blueprint.yaml does not declare")

# ── narration: authored here, printed from state (Cirrus's rules) ─────────
META_AT = {
    "start": {"files", "expectedMinutes"},
    "await": {"files", "expectedMinutes"},
    "failed": {"files", "expectedMinutes"},
    "done": {"files", "expectedMinutes", "elapsed", "next"},
}
STATE_WORDS = {"done", "failed", "complete", "completed", "succeeded", "skipped"}
PHASE_KEYS = {"name", "title"}
input_keys = set((bp.get("inputs") or {}).keys())

ws_input = (bp.get("inputs") or {}).get("orunWorkspace") or {}
if ws_input.get("from") != "workspace":
    bad("inputs.orunWorkspace must declare `from: workspace` — a console build has no other way to say it")

def strip_expressions(line):
    return re.sub(r"\{\{.*?\}\}", "", line, flags=re.S)

def refs(line):
    found = []
    for expr in re.findall(r"\{\{(.*?)\}\}", line, re.S):
        found += re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)", expr)
    return found

def check_line(where, line, slot, hook_ids):
    prose = strip_expressions(line).lower()
    for w in STATE_WORDS:
        if re.search(rf"\b{w}\b", prose):
            bad(f"{where} asserts {w!r} — `state` is the truth and narration is the "
                f"caption. Describe the world, not the run.")
    for ref in refs(line):
        parts = ref.split(".")
        head = parts[0]
        if head == "phase":
            if len(parts) != 2 or parts[1] not in PHASE_KEYS:
                bad(f"{where} names .{ref}; a phase carries {sorted(PHASE_KEYS)}")
        elif head == "inputs":
            if len(parts) != 2 or parts[1] not in input_keys:
                bad(f"{where} names .{ref}, which is not a declared input")
        elif head == "meta":
            allowed = META_AT.get(slot, META_AT["start"])
            if len(parts) != 2 or parts[1] not in allowed:
                bad(f"{where} names .{ref}; the {slot} event carries {sorted(allowed)}")
        elif head == "hooks":
            if len(parts) < 2 or parts[1] not in hook_ids:
                bad(f"{where} names .{ref}; this phase has no such hook")
        else:
            bad(f"{where} names .{ref}; narration may reference phase, inputs, meta and hooks")

for p in phases:
    n = p.get("narrate") or {}
    ids = {h.get("id") for h in hooks_of(p)}
    awaits = bool((p.get("hooks") or {}).get("await"))
    for slot in ("start", "await", "done", "failed"):
        line = n.get(slot)
        if slot == "await" and not awaits:
            # A phase that waits on nothing never says its await line.
            if line:
                bad(f"phase {p['name']} declares narrate.await and has no await hooks — "
                    f"nobody would ever read it")
            continue
        if not line:
            bad(f"phase {p['name']} declares no narrate.{slot}")
            continue
        check_line(f"phase {p['name']} narrate.{slot}", line, slot, ids)
    for h in ((p.get("hooks") or {}).get("await") or []):
        line = h.get("narrate")
        if not line:
            bad(f"phase {p['name']} await hook {h.get('id')} declares no narrate — a "
                f"wait with no words reads as a stalled build")
            continue
        check_line(f"phase {p['name']} hook {h.get('id')} narrate", line, "done", ids)
    for slot in ("pre", "post"):
        for h in ((p.get("hooks") or {}).get(slot) or []):
            if h.get("narrate"):
                check_line(f"phase {p['name']} hook {h.get('id')} narrate", h["narrate"], "start", ids)

# ── what a baseline of this shape never grows back ────────────────────────
if (root / "flows").exists():
    bad("flows/ exists — the bootstrap is the blueprint; every mechanism is a typed orun action")

if problems:
    print("FAIL: the blueprint's phases and the bootstrap disagree:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

placed_n = sum(len(p.get("modules") or []) for p in phases)
narrated = sum(len(p.get("narrate") or {}) for p in phases)
narrated += sum(1 for p in phases for h in hooks_of(p) if h.get("narrate"))
print(f"   {len(phases)} phases, {placed_n} modules, {len(HOOK_ONLY)} hook-only — in execution order")
print(f"   stages: scaffold {stages.get('scaffold')} (GitHub only, deploy lanes parked), "
      f"live {stages.get('live')} ({', '.join(needs)}; binds {', '.join(sorted(late)) or 'nothing'})")
print(f"   {narrated} authored narration lines, every reference resolving")
PY

echo "phases.test.sh: ok"
