#!/usr/bin/env bash
#
# try-plugin.sh — Try a plugin package (Work Sources and/or personas) in the
# demo team's sandbox.
#
# A git/npm spec (ssh://…, https://…, git:…, npm:…) is installed into the demo
# team first (`mpt plugins add`: clone + npm install + npm run build, into
# demo/team/.my-pizza-team/packages/, which setup-demo.sh keeps across resets).
# Then `mpt plugins doctor` (from ../my-pizza-team source), record it in
# ./plugins.local.json (gitignored; setup-demo.sh merges it into the demo team's
# config.json on every setup), re-run setup-demo.sh, and start ./run-ui.sh.
# Writes nothing outside this repo (the doctor's live run uses a temp dir it
# removes). See README.md "Trying your own plugins".
#

set -euo pipefail

# Physical path (pwd -P), so paths compare equal however you got here (symlinks).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MPT_SOURCE="$SCRIPT_DIR/../my-pizza-team"
LOCAL_PLUGINS="$SCRIPT_DIR/plugins.local.json"
TEAM_DIR="$SCRIPT_DIR/demo/team/.my-pizza-team"

usage() {
  cat <<EOF
Usage:
  ./try-plugin.sh <path|spec> [--config '<json>'] [--no-start] [--update]
  ./try-plugin.sh --remove <path|spec>
  ./try-plugin.sh --list

Try a plugin package in the demo team (README.md "Trying your own plugins") —
Work Sources, personas ("mpt": { "personas": [...] }), or both. A persona-only
package needs no build; its personas show on Config → Personas, read-only, as
<package.json name>/<file name> (e.g. ./plugins/mpt-personas-demo, which the
demo fixture already loads).

  0. git/npm specs only: ./setup-demo.sh, then install it into the demo team —
     mpt plugins add <spec> [--config '<json>'] (clone + npm install + npm run
     build). Already installed (a re-run): skipped, unless --update
     (mpt plugins update <spec>). Stops here on failure.
  1. mpt plugins doctor <path|spec> [--config '<json>']   (stops here on failure;
     --config also runs init + one live sync on a throwaway context). A spec
     installed by step 0 of this run is removed again on failure.
  2. adds or updates its entry in plugins.local.json (gitignored), with the
     --config as its config (without --config an existing config is kept)
  3. ./setup-demo.sh (merges plugins.local.json into demo/team/.my-pizza-team/config.json)
  4. ./run-ui.sh --restart (the daemon, no agents; stops one already running), unless --no-start

Options:
  --config '<json>'  The package's config object, as in config.json "packages".
                     Relative paths in it are up to the plugin (the daemon passes
                     the team dir, demo/team/.my-pizza-team; the doctor a temp
                     dir), so prefer absolute ones.
  --no-start         Set up the demo but don't start the daemon.
  --update           git/npm specs: re-fetch and rebuild an installed package
                     (mpt plugins update) before the doctor.
  --remove <target>  Remove the entry from plugins.local.json, and a git/npm
                     spec's install from the demo team (then re-run setup or
                     ./run-ui.sh --restart).
  --list             Show the entries in plugins.local.json.
  -h, --help         This help.

A <path> is relative to the current directory (or absolute, or ~/); it's stored
relative to this repo when inside it, else absolute. npm:/git: specs and git
URLs (ssh://…, https://…, with an optional @ref) are stored as is; their
installs live in demo/team/.my-pizza-team/packages/, kept across
./setup-demo.sh resets (./setup-demo.sh --fresh clears them; the daemon
reinstalls missing ones on start). A git plugin must install and build with
plain npm (npm install --omit=peer; npm run build) or ship prebuilt entries.

After rebuilding the plugin (e.g. brazil-build in its package): ./run-ui.sh --restart
EOF
}

err() { echo -e "\033[0;31m✗\033[0m $1" >&2; }

# mpt from ../my-pizza-team source, against the demo team.
mpt() { TEAM_DIR="$TEAM_DIR" node "$MPT_SOURCE/cli/main.ts" "$@"; }

# "<configured> <installed> <install dir>" (each 0|1, then a path) for a git/npm
# spec in the demo team: whether its config.json has an entry with the same
# identity (merged from plugins.local.json by setup), and whether its install
# dir exists. Uses MPT's
# own spec parser and install layout, so it agrees with `mpt plugins`.
spec_state() {
  node --no-warnings --input-type=module -e '
import * as fs from "node:fs";
import * as path from "node:path";
const [mpt, teamDir, raw] = process.argv.slice(1);
const { parsePackageEntries } = await import(path.join(mpt, "daemon/plugins/spec.ts"));
const { packageInstallDir } = await import(path.join(mpt, "daemon/plugins/loader.ts"));
const spec = parsePackageEntries([raw], teamDir).packages[0]?.spec;
if (!spec) { console.log("0 0 -"); process.exit(0); }
let packages = [];
try { packages = JSON.parse(fs.readFileSync(path.join(teamDir, "config.json"), "utf8")).packages || []; } catch {}
const configured = parsePackageEntries(packages, teamDir).packages.some((p) => p.spec.identity === spec.identity);
const dir = packageInstallDir(spec, teamDir);
console.log(`${configured ? 1 : 0} ${fs.existsSync(dir) ? 1 : 0} ${dir}`);
' "$MPT_SOURCE" "$TEAM_DIR" "$1"
}

# Edit or read plugins.local.json with node. $1 = action (list|upsert|remove),
# $2 = the source as stored, $3 = config JSON (upsert; "" = keep / none).
local_plugins() {
  node -e '
const fs = require("fs"), path = require("path"), os = require("os");
const [file, repo, action, source, configJson] = process.argv.slice(1);
const fail = (m) => { console.error(`✗ ${file}: ${m}`); process.exit(1); };
let list = [];
if (fs.existsSync(file)) {
  try { list = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) { fail(`not valid JSON: ${e.message}`); }
  if (!Array.isArray(list)) fail("expected a JSON array of package entries");
}
const isLocal = (s) => path.isAbsolute(s) || s === "." || s === ".." || s === "~" || /^(\.\.?|~)\//.test(s);
const real = (p) => { try { return fs.realpathSync(p); } catch { return p; } };
const key = (s) => !isLocal(s) ? s : real(s === "~" || s.startsWith("~/") ? path.join(os.homedir(), s.slice(1)) : path.resolve(repo, s));
const sourceOf = (e) => typeof e === "string" ? e : e && typeof e === "object" ? e.source : undefined;
const same = (e) => typeof sourceOf(e) === "string" && key(sourceOf(e)) === key(source);
const save = () => fs.writeFileSync(file, JSON.stringify(list, null, 2) + "\n");
if (action === "list") {
  const entries = list.filter((e) => sourceOf(e) !== undefined);
  if (!entries.length) console.log(`No plugins in ${path.basename(file)}.`);
  for (const e of entries) console.log(`  ${sourceOf(e)}${typeof e === "object" && e.config ? "  " + JSON.stringify(e.config) : ""}`);
} else if (action === "upsert") {
  const i = list.findIndex(same);
  const old = i >= 0 && typeof list[i] === "object" ? list[i] : undefined;
  const config = configJson ? JSON.parse(configJson) : old && old.config;
  const entry = config !== undefined ? { ...(old || {}), source, config } : source;
  if (i >= 0) list[i] = entry; else list.push(entry);
  save();
  console.log(`${i >= 0 ? "Updated" : "Added"} ${source} in ${path.basename(file)}`);
} else if (action === "remove") {
  const before = list.length;
  list = list.filter((e) => !same(e));
  if (list.length === before) fail(`no entry for ${source}`);
  save();
  console.log(`Removed ${source} from ${path.basename(file)}`);
}
' "$LOCAL_PLUGINS" "$SCRIPT_DIR" "$@"
}

# A local path (as on the command line) → absolute (symlinks resolved when it exists).
is_local() { case "$1" in /*|.|..|./*|../*|"~"|"~/"*) return 0;; *) return 1;; esac; }
absolute() {
  case "$1" in
    "~") echo "$HOME" ;;
    "~/"*) echo "$HOME/${1#\~/}" ;;
    *) node -e 'const fs = require("fs"), p = require("path").resolve(process.argv[1]); try { console.log(fs.realpathSync(p)); } catch { console.log(p); }' "$1" ;;
  esac
}
# What goes in plugins.local.json: ./relative inside this repo, else absolute (or the spec).
stored() {
  if ! is_local "$1"; then echo "$1"; return; fi
  case "$1" in "~"|"~/"*) echo "$1"; return;; esac
  local abs; abs="$(absolute "$1")"
  case "$abs" in
    "$SCRIPT_DIR") echo "." ;;
    "$SCRIPT_DIR"/*) echo "./${abs#"$SCRIPT_DIR"/}" ;;
    *) echo "$abs" ;;
  esac
}

# ─── Arguments ────────────────────────────────────────────────────────

TARGET=""
CONFIG=""
HAVE_CONFIG=0
NO_START=0
UPDATE=0
ACTION="try"
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --list) ACTION="list" ;;
    --remove) ACTION="remove"; [ $# -ge 2 ] || { err "--remove needs a <path|spec>"; exit 1; }; TARGET="$2"; shift ;;
    --remove=*) ACTION="remove"; TARGET="${1#--remove=}" ;;
    --config) [ $# -ge 2 ] || { err "--config needs a JSON object"; exit 1; }; CONFIG="$2"; HAVE_CONFIG=1; shift ;;
    --config=*) CONFIG="${1#--config=}"; HAVE_CONFIG=1 ;;
    --no-start) NO_START=1 ;;
    --update) UPDATE=1 ;;
    -*) err "Unknown option $1"; usage >&2; exit 1 ;;
    *) [ -z "$TARGET" ] || { err "One plugin at a time (got $TARGET and $1)"; exit 1; }; TARGET="$1" ;;
  esac
  shift
done

if ! command -v node &>/dev/null; then
  err "node not found. Install Node.js 24+: https://nodejs.org/"
  exit 1
fi

case "$ACTION" in
  list) local_plugins list; exit 0 ;;
  remove)
    local_plugins remove "$(stored "$TARGET")"
    # A git/npm spec: also delete its install from the demo team (its cache).
    if ! is_local "$TARGET" && [ -d "$TEAM_DIR" ] && [ -d "$MPT_SOURCE" ]; then
      read -r CONFIGURED INSTALLED INSTALL_DIR < <(spec_state "$TARGET")
      if [ "$CONFIGURED" = 1 ]; then
        mpt plugins remove "$TARGET" >/dev/null && echo "Deleted its install from the demo team."
      elif [ "$INSTALLED" = 1 ]; then
        # Not in the demo config (e.g. after an e2e setup): just drop the cached install.
        rm -rf "$INSTALL_DIR" && echo "Deleted its install ($INSTALL_DIR)."
      fi
    fi
    echo "Re-run ./setup-demo.sh or ./run-ui.sh --restart to apply."
    exit 0 ;;
esac

if [ -z "$TARGET" ]; then usage >&2; exit 1; fi
if [ ! -d "$MPT_SOURCE" ]; then
  err "my-pizza-team source not found at $MPT_SOURCE"
  exit 1
fi
if [ "$HAVE_CONFIG" = 1 ] && ! node -e 'const v = JSON.parse(process.argv[1]); if (!v || typeof v !== "object" || Array.isArray(v)) process.exit(1)' "$CONFIG" 2>/dev/null; then
  err "--config must be a JSON object, e.g. '{\"dryRun\":true}' (got: $CONFIG)"
  exit 1
fi

# ─── 0. Install (git/npm specs) ───────────────────────────────────────

# Into the demo team's packages/ (kept across setup resets), so the doctor and
# the daemon find it. A re-run for an installed spec only runs the doctor.
INSTALLED_NOW=0
if is_local "$TARGET"; then
  [ "$UPDATE" = 0 ] || echo "(--update ignored: a local path loads in place — rebuild it yourself)"
else
  echo "▸ ./setup-demo.sh"
  "$SCRIPT_DIR/setup-demo.sh" > /dev/null
  read -r CONFIGURED INSTALLED _ < <(spec_state "$TARGET")
  if [ "$CONFIGURED" = 0 ]; then
    ADD_ARGS=(plugins add "$TARGET")
    if [ "$HAVE_CONFIG" = 1 ]; then ADD_ARGS+=(--config "$CONFIG"); fi
    echo "▸ mpt ${ADD_ARGS[*]}"
    # On failure `mpt plugins add` deletes the half-done install and leaves config.json alone.
    if ! mpt "${ADD_ARGS[@]}"; then
      err "mpt plugins add failed (see above) — plugins.local.json is unchanged."
      exit 1
    fi
    INSTALLED_NOW=1
  elif [ "$INSTALLED" = 0 ] || [ "$UPDATE" = 1 ]; then
    # In plugins.local.json already: (re)install it in place.
    echo "▸ mpt plugins update $TARGET"
    if ! mpt plugins update "$TARGET"; then
      err "mpt plugins update failed (see above) — plugins.local.json is unchanged."
      exit 1
    fi
  else
    echo "✓ $TARGET is already installed in the demo team (--update re-fetches it)"
  fi
  echo ""
fi

# ─── 1. Doctor ────────────────────────────────────────────────────────

DOCTOR_TARGET="$TARGET"
if is_local "$TARGET"; then DOCTOR_TARGET="$(absolute "$TARGET")"; fi
DOCTOR_ARGS=(plugins doctor "$DOCTOR_TARGET")
if [ "$HAVE_CONFIG" = 1 ]; then DOCTOR_ARGS+=(--config "$CONFIG"); fi

echo "▸ mpt ${DOCTOR_ARGS[*]}"
# TEAM_DIR = the demo team (the doctor only reads it; it may not exist yet).
if ! mpt "${DOCTOR_ARGS[@]}"; then
  if [ "$INSTALLED_NOW" = 1 ]; then
    echo "▸ mpt plugins remove $TARGET   (undoing this run's install)"
    mpt plugins remove "$TARGET" >/dev/null || true
  fi
  err "mpt plugins doctor failed — fix the plugin (or its --config) and try again. plugins.local.json is unchanged."
  exit 1
fi
echo ""

# ─── 2. Record it ─────────────────────────────────────────────────────

local_plugins upsert "$(stored "$TARGET")" "$CONFIG"

# ─── 3. Setup (+ 4. start) ────────────────────────────────────────────

if [ "$NO_START" = 1 ]; then
  "$SCRIPT_DIR/setup-demo.sh"
  echo ""
  echo "Set up (not started). Start the daemon with: ./run-ui.sh"
else
  # run-ui.sh re-runs setup-demo.sh itself and prints each plugin's status;
  # --restart stops a daemon it started earlier first (and is fine without one).
  exec "$SCRIPT_DIR/run-ui.sh" --restart
fi
