#!/usr/bin/env node
// The deploy lanes stay off main until the site has somewhere to deploy to
// (zero-dependency).
//
// intent.yaml activates `stage` and `prod` on `github-push-main` as well as on
// pull requests, and the component deploys on that trigger (apps/web's
// `profileRules`: `deploy` when `triggerRef: github-push-main`). That is the
// right rule for a site that is live. It is the wrong one for a site whose
// code exists before its Cloudflare account does: the build splits into a
// SCAFFOLD stage that needs GitHub only (the code placed, branded, landed)
// and a LIVE stage that needs Cloudflare (the deploy credentials minted, the
// deploy watched, the URLs probed). An app with no Cloudflare connection yet
// stops after the scaffold, and every merge to its `main` would otherwise
// plan a deploy whose credentials do not exist — a red CI on every merge, for
// as long as the app is code only.
//
// So the scaffold phase parks the two deploy rungs' push-to-main activation
// and the live phase puts it back, exactly as promotion.mjs and dev-lanes.mjs
// do for prod's gate and dev's verify lanes:
//
//   node tooling/bootstrap/deploys.mjs --defer     # 01-scaffold, before its landing
//   node tooling/bootstrap/deploys.mjs --restore   # 02-live, before its landing
//   node tooling/bootstrap/deploys.mjs --check     # prints deferred | active
//
// While deferred, a merge to main plans nothing on stage or prod (dev's push
// activation is deferred by dev-lanes.mjs for the same bootstrap), so the
// run is `plan` alone: green, and nothing deployed. Pull requests keep their
// stage and prod verify lanes (built and dry-deployed, no credential), so a
// code-only app's changes are still checked before they merge.
//
// --defer replaces each rung's `- github-push-main` trigger line with one
// marker comment that base64-encodes the exact text removed, so --restore
// reproduces intent.yaml byte-for-byte. Both are idempotent. Restoring is a
// change to intent.yaml's `environments` section only, which `orun plan
// --changed` maps to no component, so the landing that restores the lanes
// must also change the component it deploys (the live phase's retouch marker
// on its component.yaml does).
//
// The activation is deferred, never dropped: an app that stops after the
// scaffold carries the markers in intent.yaml, and `--restore` (or the live
// phase) is the whole fix.
import * as fs from "node:fs";

const FILE = process.argv.includes("--file")
  ? process.argv[process.argv.indexOf("--file") + 1]
  : "intent.yaml";
const MARKER = "@deploys-deferred";
const TRIGGER = "github-push-main";
// The rungs that DEPLOY. dev only verifies, and dev-lanes.mjs owns its lanes.
const RUNGS = new Set(["stage", "prod"]);

function usage() {
  console.error("usage: deploys.mjs --defer | --restore | --check [--file intent.yaml]");
  process.exit(2);
}

// The `- github-push-main` lines under environments.{stage,prod}.activation.
function findDeployTriggers(text) {
  const lines = text.split("\n");
  const found = [];
  let inEnvs = false;
  let envIndent = -1;
  let current = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^environments:\s*$/.test(line)) {
      inEnvs = true;
      continue;
    }
    if (!inEnvs) continue;
    if (/^\S/.test(line) && line.trim() !== "") break; // left the section
    const env = /^(\s+)([A-Za-z0-9_-]+):\s*$/.exec(line);
    if (env && (envIndent < 0 || env[1].length <= envIndent)) {
      envIndent = env[1].length;
      current = env[2];
      continue;
    }
    if (!RUNGS.has(current)) continue;
    if (new RegExp(`^\\s+-\\s+${TRIGGER}\\s*$`).test(line)) found.push({ env: current, index: i });
  }
  return { lines, found };
}

function markerFor(original) {
  const indent = /^(\s*)/.exec(original)[1];
  const b64 = Buffer.from(original, "utf8").toString("base64");
  return `${indent}# ${MARKER}:${b64} (tooling/bootstrap/deploys.mjs --restore puts it back)`;
}

const MARKER_RE = new RegExp(
  `^[ \\t]*# ${MARKER}:([A-Za-z0-9+/=]+) \\(tooling/bootstrap/deploys\\.mjs --restore puts it back\\)$`,
  "gm",
);

function defer() {
  const text = fs.readFileSync(FILE, "utf8");
  const { lines, found } = findDeployTriggers(text);
  if (found.length === 0) {
    console.log(
      text.includes(`# ${MARKER}:`)
        ? `deploys --defer: already deferred in ${FILE}`
        : `deploys --defer: neither stage nor prod is activated on ${TRIGGER} in ${FILE} — nothing to defer`,
    );
    return;
  }
  const out = [...lines];
  for (const { index } of found) out[index] = markerFor(lines[index]);
  fs.writeFileSync(FILE, out.join("\n"));
  const envs = found.map((f) => f.env).join(" and ");
  console.log(`deploys --defer: ${envs} deploy nothing on a merge to main until --restore (${FILE})`);
}

function restore() {
  const text = fs.readFileSync(FILE, "utf8");
  let n = 0;
  const out = text.replace(MARKER_RE, (_m, b64) => {
    n++;
    return Buffer.from(b64, "base64").toString("utf8");
  });
  if (n === 0) {
    console.log(`deploys --restore: nothing deferred in ${FILE}`);
    return;
  }
  fs.writeFileSync(FILE, out);
  console.log(`deploys --restore: stage and prod deploy on every merge to main again (${FILE})`);
}

function check() {
  const text = fs.readFileSync(FILE, "utf8");
  console.log(text.includes(`# ${MARKER}:`) ? "deferred" : "active");
}

const mode = process.argv[2];
if (mode === "--defer") defer();
else if (mode === "--restore") restore();
else if (mode === "--check") check();
else usage();
