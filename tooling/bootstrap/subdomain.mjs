#!/usr/bin/env node
// Bind the site's workers.dev subdomain when it goes live (zero-dependency).
//
// The subdomain is a LATE-BOUND input. It belongs to the Cloudflare account
// the site deploys into, and a build that stops after the scaffold stage —
// an app with no Cloudflare connection yet — does not have one. So the
// scaffold places and brands the tree with the placeholder,
// `your-workers-subdomain` (the baseline's own, `.baseline/identity.json`),
// and the live stage must replace it before anything deploys: in the
// component's `workersDevSubdomain` (the deploy's smoke URL), in
// intent.yaml's environment URLs, in the operating contract's examples, and
// in `.rebrand/values.json`, the identity every later phase reads back.
//
// A build that runs both stages at once was given the real value from the
// start, so the rebrand already wrote it everywhere and binding finds
// nothing to change.
//
//   node subdomain.mjs --bind <subdomain>   # 02-live, before its landing
//   node subdomain.mjs --check              # prints `bound <subdomain>` | `placeholder`
//
// --bind refuses the placeholder itself (or nothing): the live stage may
// never keep it, because every URL the deploy smokes and the phase probes is
// built from it. It also refuses to MOVE a site already bound to another
// subdomain: that is another Cloudflare account, whose deploy token this
// workspace's secrets do not hold, not a step of a bootstrap.
//
// Only the placeholder is replaced, and only where it stands as a whole DNS
// label, so a subdomain that merely contains it is left alone; the
// `.rebrand/values.json` record is written LAST, so an interrupted bind is
// finished by the next one. Idempotent. Runs in the product checkout, over
// the files git tracks there.
import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const VALUES = ".rebrand/values.json";
const SUBDOMAIN_RE = /^[a-z0-9][a-z0-9-]{0,62}$/; // = blueprint.yaml's pattern

function usage(msg) {
  if (msg) console.error(`subdomain: ${msg}`);
  console.error("usage: subdomain.mjs --bind <subdomain> | --check [--baseline-identity <file>]");
  process.exit(2);
}

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

// The placeholder, from the baseline's declared identity — the same file the
// rebrand reads its FROM side from, beside this script.
function placeholder() {
  const file =
    arg("baseline-identity") ??
    path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", ".baseline", "identity.json");
  try {
    const declared = JSON.parse(fs.readFileSync(file, "utf8")).subdomain;
    if (typeof declared === "string" && declared.length > 0) return declared;
  } catch {
    // absent is fine: the default IS this baseline's placeholder
  }
  return "your-workers-subdomain";
}

function readValues() {
  try {
    return { text: fs.readFileSync(VALUES, "utf8") };
  } catch {
    console.error(`subdomain: ${VALUES} is missing — is this a scaffolded site?`);
    process.exit(1);
  }
}

function recorded(text, fallback) {
  let v;
  try {
    v = JSON.parse(text).subdomain;
  } catch (e) {
    console.error(`subdomain: ${VALUES} does not parse: ${e.message}`);
    process.exit(1);
  }
  return typeof v === "string" && v.trim() ? v.trim() : fallback;
}

// The placeholder as a whole DNS label: not preceded or followed by a label
// character, so `your-workers-subdomain-2` is somebody's real subdomain.
const labelRe = (label) =>
  new RegExp(`(?<![A-Za-z0-9-])${label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![A-Za-z0-9-])`, "g");

function trackedTextFiles() {
  let out;
  try {
    out = execFileSync("git", ["ls-files", "-z"], { encoding: "utf8" });
  } catch (e) {
    console.error(`subdomain: git ls-files failed — run it in the site's checkout (${e.message.trim()})`);
    process.exit(1);
  }
  return out
    .split("\0")
    .filter((f) => f && !f.startsWith(".rebrand/") && !/^pnpm-lock\.yaml$/.test(f))
    .filter((f) => !/\.(png|jpe?g|ico|gif|webp|woff2?|ttf|eot)$/i.test(f))
    .filter((f) => {
      try {
        return fs.statSync(f).isFile();
      } catch {
        return false;
      }
    });
}

function bind(value) {
  const hold = placeholder();
  const want = String(value ?? "").trim();
  if (!want || want === hold) {
    console.error(
      `subdomain --bind: the site goes live on <worker>.<subdomain>.workers.dev and was given ${want ? `the placeholder "${hold}"` : "no subdomain"}. ` +
        "The live stage needs the workers.dev subdomain of the Cloudflare account it deploys into: a console or orun.work " +
        "build reads it from the Cloudflare connection; a hand-run build passes --set subdomain=<subdomain>.",
    );
    process.exit(1);
  }
  if (!SUBDOMAIN_RE.test(want)) {
    console.error(`subdomain --bind: "${want}" is not a workers.dev subdomain (${SUBDOMAIN_RE})`);
    process.exit(1);
  }
  const { text } = readValues();
  const was = recorded(text, hold);
  if (was !== hold && was !== want) {
    console.error(
      `subdomain --bind: this site is bound to ${was}.workers.dev and was given ${want}. Moving a site to another ` +
        "Cloudflare account's subdomain is not a step of a bootstrap — its Workers, deploy token and URLs belong to the " +
        `old one. To move it on purpose, replace "${was}" with "${want}" in .rebrand/values.json, intent.yaml and ` +
        "apps/web/component.yaml in one change.",
    );
    process.exit(1);
  }

  const re = labelRe(hold);
  const changed = [];
  for (const file of trackedTextFiles()) {
    const before = fs.readFileSync(file, "utf8");
    if (before.includes("\0")) continue; // binary safety net
    const after = before.replace(re, want);
    if (after !== before) {
      fs.writeFileSync(file, after);
      changed.push(file);
    }
  }
  // The record last: until it names the subdomain, the next bind redoes the rest.
  if (was !== want) {
    const line = /("subdomain"\s*:\s*)"[^"]*"/;
    let next = line.test(text) ? text.replace(line, `$1${JSON.stringify(want)}`) : null;
    if (next === null || recorded(next, hold) !== want) {
      const obj = JSON.parse(text);
      obj.subdomain = want;
      next = `${JSON.stringify(obj, null, 2)}\n`;
    }
    fs.writeFileSync(VALUES, next);
    changed.push(VALUES);
  }

  const left = trackedTextFiles().filter((f) => labelRe(hold).test(fs.readFileSync(f, "utf8")));
  if (left.length > 0) {
    console.error(`subdomain --bind: the placeholder "${hold}" is still in ${left.join(", ")}`);
    process.exit(1);
  }
  console.log(
    changed.length > 0
      ? `subdomain --bind: ${want}.workers.dev bound in ${changed.length} file(s): ${changed.join(", ")}`
      : `subdomain --bind: already bound to ${want}.workers.dev — nothing to change`,
  );
}

function check() {
  const hold = placeholder();
  const was = recorded(readValues().text, hold);
  console.log(was === hold ? "placeholder" : `bound ${was}`);
}

const argv = process.argv.slice(2);
const at = argv.indexOf("--bind");
if (at >= 0) {
  // The value may be empty (an input nobody set renders as ""), which bind()
  // refuses with the reason; only a MISSING one is a usage error.
  if (at + 1 >= argv.length || argv[at + 1].startsWith("--")) usage("--bind needs a value");
  bind(argv[at + 1]);
} else if (argv.includes("--check")) check();
else usage();
