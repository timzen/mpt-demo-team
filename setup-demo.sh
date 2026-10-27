#!/usr/bin/env bash
#
# setup-demo.sh — Copies the demo fixtures into place for running MPT.
#
# Creates:
#   ./demo/project/          — The demo todo API code (agents work here)
#   ./demo/team/.my-pizza-team/  — The team directory (MPT daemon reads this)
#   ./demo/tracker/tracker.json  — The demo-tracker plugin's fake issue tracker
#
# The team's config.json loads the example plugin in place from
# ./plugins/mpt-source-demo-tracker (a relative local path, no install step),
# plus any entries in ./plugins.local.json (your own plugins; gitignored).
#
# Both live under ./demo/ which is .gitignored so you can freely experiment.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

echo "🍕 MPT Demo Setup"
echo "=================="
echo ""

# --- Clean slate ---
rm -rf "$SCRIPT_DIR/demo"
mkdir -p "$SCRIPT_DIR/demo/team"

# --- Copy demo project ---
echo "📁 Setting up demo project..."
cp -R "$FIXTURES_DIR/project" "$SCRIPT_DIR/demo/project"
echo "   ✓ demo/project/ created"

# --- Copy team directory ---
echo "📁 Setting up team directory..."
cp -R "$FIXTURES_DIR/team" "$SCRIPT_DIR/demo/team/.my-pizza-team"
echo "   ✓ demo/team/.my-pizza-team/ created"

# --- Copy the fake issue tracker (the demo-tracker plugin's "external system") ---
echo "📁 Setting up the demo tracker..."
cp -R "$FIXTURES_DIR/tracker" "$SCRIPT_DIR/demo/tracker"
echo "   ✓ demo/tracker/tracker.json created (3 open issues, 1 triage-mode)"

# --- Merge the local plugin overlay (plugins.local.json, gitignored) ---
#
# plugins.local.json is a JSON array of config.json `packages` entries (a spec
# string, or { source, config }) — your own plugins to try in the sandbox (see
# README "Trying your own plugins", ./try-plugin.sh). Relative local paths are
# relative to this repo; they (and ~/ paths) are made absolute so they work from
# the team dir. An entry with the same package as a fixture entry replaces it.
# Entries like { "//": "..." } are comments and skipped. Merged before the
# __DEMO_PROJECT__ substitution below, so a local config may use it too.
# run-e2e.sh sets MPT_DEMO_NO_LOCAL_PLUGINS=1 to keep e2e deterministic.
LOCAL_PLUGINS="$SCRIPT_DIR/plugins.local.json"
if [ -f "$LOCAL_PLUGINS" ] && [ "${MPT_DEMO_NO_LOCAL_PLUGINS:-}" != "1" ]; then
  echo "📁 Merging plugins.local.json..."
  node -e '
const fs = require("fs"), path = require("path"), os = require("os");
const [file, configFile, repo] = process.argv.slice(1);
const teamDir = path.dirname(configFile);
const fail = (m) => { console.error(`✗ ${file}: ${m}`); process.exit(1); };
let local;
try { local = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) { fail(`not valid JSON: ${e.message}`); }
if (!Array.isArray(local)) fail("expected a JSON array of package entries (a spec string, or { \"source\": ..., \"config\": {...} })");
const isLocal = (s) => path.isAbsolute(s) || s === "." || s === ".." || s === "~" || /^(\.\.?|~)\//.test(s);
const abs = (s, base) => s === "~" || s.startsWith("~/") ? path.join(os.homedir(), s.slice(1)) : path.resolve(base, s);
const sourceOf = (e) => typeof e === "string" ? e : e && e.source;
const real = (p) => { try { return fs.realpathSync(p); } catch { return p; } };
const key = (s, base) => isLocal(s) ? real(abs(s, base)) : s;
const entries = [];
local.forEach((e, i) => {
  if (e && typeof e === "object" && !Array.isArray(e) && "//" in e && !("source" in e)) return;
  const s = sourceOf(e);
  if (typeof s !== "string" || !s.trim()) fail(`entry ${i} needs a spec string or { "source": "<path|spec>", "config": {...} } (got ${JSON.stringify(e)})`);
  if (typeof e === "object" && e.config !== undefined && (typeof e.config !== "object" || e.config === null || Array.isArray(e.config))) fail(`entry ${i} (${s}): "config" must be an object`);
  const source = isLocal(s) ? abs(s, repo) : s;
  if (typeof e === "string") entries.push(source);
  else { const { "//": _c, ...rest } = e; entries.push({ ...rest, source }); }
});
const cfg = JSON.parse(fs.readFileSync(configFile, "utf8"));
const keys = new Set(entries.map((e) => key(sourceOf(e), repo)));
const kept = (cfg.packages || []).filter((e) => typeof sourceOf(e) !== "string" || !keys.has(key(sourceOf(e), teamDir)));
const seen = new Set();
const merged = entries.filter((e) => { const k = key(sourceOf(e), repo); if (seen.has(k)) return false; seen.add(k); return true; });
cfg.packages = [...kept, ...merged];
fs.writeFileSync(configFile, JSON.stringify(cfg, null, 2) + "\n");
if (!merged.length) console.log("   (no entries)");
for (const e of merged) console.log(`   ✓ ${sourceOf(e)}${typeof e === "object" && e.config ? " " + JSON.stringify(e.config) : ""}`);
' "$LOCAL_PLUGINS" "$SCRIPT_DIR/demo/team/.my-pizza-team/config.json" "$SCRIPT_DIR"
fi

# --- Patch fixtures with the real demo project path ---
DEMO_PROJECT_PATH="$SCRIPT_DIR/demo/project"
TEAM_DIR_PATH="$SCRIPT_DIR/demo/team/.my-pizza-team"

# Stories and WorkDefs ship with a `__DEMO_PROJECT__` placeholder for their
# working directory (that's the only work-selection signal now — directory
# affinity). Substitute the real absolute path in the copied team dir.
grep -rl "__DEMO_PROJECT__" "$TEAM_DIR_PATH" | while read -r f; do
  # Use a non-slash delimiter since the replacement is an absolute path.
  sed -i.bak "s|__DEMO_PROJECT__|$DEMO_PROJECT_PATH|g" "$f" && rm -f "$f.bak"
done
echo "   ✓ story, WorkDef, and plugin directories pointed at the demo project"
TRACKER_FILE="$SCRIPT_DIR/demo/tracker/tracker.json"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Demo ready! Use these paths with MPT:"
echo ""
echo "   Team dir:     $TEAM_DIR_PATH"
echo "   Project dir:  $DEMO_PROJECT_PATH"
echo "   Tracker file: $TRACKER_FILE"
echo ""
echo "To run the daemon against this demo:"
echo ""
echo "   cd $SCRIPT_DIR/demo/team"
echo "   mpt start"
echo "   (auto-detects .my-pizza-team in current dir)"
echo ""
echo "   — or —"
echo ""
echo "   TEAM_DIR=$TEAM_DIR_PATH mpt start"
echo ""
echo "Then open http://localhost:7437 to see the board."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Story: \"Add User Authentication\""
echo "   Task 1: Create auth module (hashing + tokens)"
echo "   Task 2: Add register/login endpoints"
echo "   Task 3: Add auth middleware to protect routes"
echo ""
echo "Plus a pending story (\"Polish the UI Theme\") and two standalone WorkDefs:"
echo "   • Solitary:  Audit project dependencies   (Tasks page → Run)"
echo "   • Scheduled: Nightly test run @ 2am        (Schedule page → Run now)"
echo ""
echo "Plus the demo-tracker plugin (plugins/mpt-source-demo-tracker): its 3 open"
echo "issues show up on the \"Demo Tracker\" tab of the Work page. DEMO-1 and DEMO-2"
echo "are worked; DEMO-3 (\"mode\": \"triage\") is triaged — a teammate proposes work"
echo "you Accept or Reject on its Triage tab. Edit"
echo "$TRACKER_FILE to see it re-sync (every 10s)."
echo ""
echo "The demo project is a simple todo API in demo/project/src/index.ts"
echo "Agents will modify it as they work through the tasks."
