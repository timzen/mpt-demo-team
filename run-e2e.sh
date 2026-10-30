#!/usr/bin/env bash
#
# run-e2e.sh — End-to-end test run for MPT.
#
# First checks the persona migration on the pre-persona team layout
# (./setup-demo.sh --legacy: start the daemon, check what it migrated, restart it
# to prove the migration is idempotent). Then sets up the demo, starts the
# daemon, checks the persona library, the persona packages and the tracker's
# per-source / per-item personas (each run's prompt and recorded persona),
# launches a Pi leader, and spawns a worker agent to execute tasks.
#
# Prerequisites:
#   - `pi` installed globally (npm i -g @earendil-works/pi-coding-agent)
#   - the Pi extension installed (`mpt setup`, or `pi install /path/to/my-pizza-team/harnesses/pi`)
#   - `node` 24+ available (runs the daemon from source; plugins need Node's module hooks)
#   - `tmux` available (for agent spawning)
#
# Usage:
#   ./run-e2e.sh          # Run the full E2E flow
#   ./run-e2e.sh --clean  # Clean up any running processes and exit
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPT_SOURCE="$SCRIPT_DIR/../my-pizza-team"
DEMO_DIR="$SCRIPT_DIR/demo"
TEAM_DIR="$DEMO_DIR/team"
PROJECT_DIR="$DEMO_DIR/project"
TRACKER_FILE="$DEMO_DIR/tracker/tracker.json"
DAEMON_PORT=7438
DAEMON_URL="http://localhost:$DAEMON_PORT"
TMUX_SESSION="mpt-demo"
PIDFILE="$TEAM_DIR/.my-pizza-team/daemon.pid"

# ─── Colors ───────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()  { echo -e "${BLUE}▸${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; }

# ─── Cleanup ──────────────────────────────────────────────────────────

cleanup() {
  log "Cleaning up..."

  # Kill daemon if running
  if [ -f "$PIDFILE" ]; then
    local pid
    pid=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      ok "Daemon stopped (PID $pid)"
    fi
    rm -f "$PIDFILE"
  fi

  # Also try to kill by port
  local port_pid
  port_pid=$(lsof -ti :$DAEMON_PORT 2>/dev/null || true)
  if [ -n "$port_pid" ]; then
    kill "$port_pid" 2>/dev/null || true
  fi

  # Kill tmux session
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    ok "tmux session '$TMUX_SESSION' killed"
  fi

  ok "Cleanup complete"
}

if [ "${1:-}" = "--clean" ]; then
  cleanup
  exit 0
fi

# Trap to cleanup on exit
trap cleanup EXIT

# ─── Pre-clean ────────────────────────────────────────────────────────

# Kill any leftover processes from a previous run
if lsof -ti :$DAEMON_PORT >/dev/null 2>&1; then
  warn "Port $DAEMON_PORT in use, cleaning up previous run..."
  cleanup
fi
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  warn "tmux session '$TMUX_SESSION' exists, cleaning up..."
  tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
fi

# ─── Preflight Checks ────────────────────────────────────────────────

log "Preflight checks..."

if ! command -v pi &>/dev/null; then
  err "pi not found. Install: npm i -g @earendil-works/pi-coding-agent"
  exit 1
fi

if ! command -v node &>/dev/null; then
  err "node not found. Install Node.js 24+: https://nodejs.org/"
  exit 1
fi

if ! command -v tmux &>/dev/null; then
  err "tmux not found. Install: brew install tmux"
  exit 1
fi

if [ ! -d "$MPT_SOURCE" ]; then
  err "my-pizza-team source not found at $MPT_SOURCE"
  exit 1
fi

ok "All dependencies found"

# ─── Daemon helpers ──────────────────────────────────────────────────

DAEMON_LOG="$DEMO_DIR/daemon.log"
json_field() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }
http_code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }

# Start the daemon from source in the background (output appended to
# $DAEMON_LOG) and wait for /health. Sets DAEMON_PID.
start_daemon() {
  cd "$MPT_SOURCE"
  TEAM_DIR="$TEAM_DIR/.my-pizza-team" PORT=$DAEMON_PORT \
    node daemon/main.ts >> "$DAEMON_LOG" 2>&1 &
  DAEMON_PID=$!
  cd "$SCRIPT_DIR"
  for i in $(seq 1 30); do
    if curl -sf "$DAEMON_URL/health" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 $DAEMON_PID 2>/dev/null; then
      err "Daemon process exited unexpectedly; see $DAEMON_LOG"
      exit 1
    fi
    sleep 0.5
  done
  err "Daemon failed to start within 15 seconds; see $DAEMON_LOG"
  exit 1
}

# Stop the daemon start_daemon started and wait for the port to be released.
stop_daemon() {
  kill "$DAEMON_PID" 2>/dev/null || true
  wait "$DAEMON_PID" 2>/dev/null || true
  for i in $(seq 1 20); do
    lsof -ti :$DAEMON_PORT >/dev/null 2>&1 || return 0
    sleep 0.5
  done
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🍕 MPT End-to-End Test Run"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── Persona migration (the legacy layout) ───────────────────────────
#
# fixtures/team-legacy is a pre-persona team (my-pizza-team docs/DESIGN.md
# "Migration: on load, lossless, idempotent"): a workflow state .md file,
# triage.md, a context library (a persona-tagged entry, an entry attached to a
# story and to a Solitary task, an unattached one), and the demo-tracker in
# source-wide triage mode with no triage persona. Start the daemon on it, check
# each step's result, then restart it and check the second start changes nothing.

log "Checking the persona migration on the legacy layout (./setup-demo.sh --legacy)..."
MPT_DEMO_NO_LOCAL_PLUGINS=1 "$SCRIPT_DIR/setup-demo.sh" --legacy > /dev/null
LEGACY_TEAM="$TEAM_DIR/.my-pizza-team"
start_daemon

python3 - "$LEGACY_TEAM" <<'PY' || { err "The legacy team wasn't migrated as expected; see $DAEMON_LOG"; exit 1; }
import json, os, sys
team = sys.argv[1]
def read(p): return open(os.path.join(team, p)).read()
def gone(p): return not os.path.exists(os.path.join(team, p))
def fail(m): print(f"  ✗ {m}", file=sys.stderr); sys.exit(1)
cfg = json.loads(read("config.json"))
wf = json.loads(read("workflows/default/workflow.json"))
# 1. the workflow state file → persona <wf>-<state>, selected by the state
state = [s for s in wf["states"] if s["name"] == "in_progress"][0]
if state.get("persona") != "default-in-progress": fail(f"in_progress state persona: {state.get('persona')}")
if not gone("workflows/default/in_progress.md"): fail("in_progress.md is still there")
if "Run tests with `npm test`" not in read("personas/default-in-progress.md"): fail("default-in-progress lost the state file's text")
# 2. triage.md → persona triage + config triage.persona
if (cfg.get("triage") or {}).get("persona") != "triage": fail(f"triage.persona: {cfg.get('triage')}")
if not gone("triage.md"): fail("triage.md is still there")
# 3. the triage-mode source keeps what it ran with: the team's triage persona
if (cfg.get("sourcePersonas") or {}).get("demo-tracker", {}).get("triagePersona") != "triage": fail(f"sourcePersonas: {cfg.get('sourcePersonas')}")
# 4. the persona-tagged context entry → a team persona
if "pair programmer" not in read("personas/pair-programmer.md"): fail("pair-programmer persona missing")
# 6. attached context inlined into Additional Context (the story's onto its task, and the task's own); attachments dropped
for t in ("add-user-auth-1", "audit-project-dependencies"):
    md = read(f"tasks/{t}/workdef.md")
    if "### Reference: Project Conventions (from the former context library, `project-conventions`)" not in md: fail(f"{t}: project-conventions wasn't inlined")
    if "Error responses:" not in md: fail(f"{t}: the inlined entry lost its text")
    if "contextRefs" in md: fail(f"{t}: contextRefs is still there")
if "context" in json.loads(read("stories/add-user-auth.json")): fail("the story still has context")
# 7. context/ archived (with a README), nothing deleted
if not gone("context"): fail("context/ is still there")
archived = sorted(os.listdir(os.path.join(team, "context.migrated")))
if archived != ["README.md", "pair-programmer.md", "project-conventions.md", "release-checklist.md"]: fail(f"context.migrated/: {archived}")
PY
LEGACY_PERSONAS=$(curl -sf "$DAEMON_URL/api/personas" | json_field "' '.join(sorted(p['id'] for p in d['personas'] if p['origin']['kind'] == 'team'))")
[ "$LEGACY_PERSONAS" = "default-in-progress pair-programmer triage" ] || { err "GET /api/personas after the migration lists team personas '$LEGACY_PERSONAS'"; exit 1; }
LEGACY_NOTICE=$(curl -sf "$DAEMON_URL/api/status" | json_field "' | '.join(n['message'] for n in d.get('notices', []))")
case "$LEGACY_NOTICE" in
  *"context library was removed"*"1 unattached entry is in context.migrated/"*) ;;
  *) err "No context-library notice on /api/status (got: '$LEGACY_NOTICE')"; exit 1 ;;
esac
[ "$(http_code "$DAEMON_URL/api/context")" = "410" ] || { err "/api/context isn't 410 Gone"; exit 1; }

# Idempotent: a second start changes no migrated file.
legacy_snapshot() {
  (cd "$LEGACY_TEAM" && find config.json personas workflows stories tasks/add-user-auth-1/workdef.md tasks/audit-project-dependencies/workdef.md context.migrated* -type f -print0 | sort -z | xargs -0 md5sum)
}
BEFORE_RESTART=$(legacy_snapshot)
stop_daemon
start_daemon
AFTER_RESTART=$(legacy_snapshot)
[ "$BEFORE_RESTART" = "$AFTER_RESTART" ] || { err "The migration isn't idempotent: a restart changed files"; diff <(echo "$BEFORE_RESTART") <(echo "$AFTER_RESTART") >&2 || true; exit 1; }
stop_daemon
ok "Migration: state file, triage.md, tagged entry → personas; triage-mode source seeded; context inlined + archived; notice; 410; idempotent"

# ─── Setup Demo ──────────────────────────────────────────────────────

log "Setting up demo fixtures..."
# Without plugins.local.json (your own plugins; see ./try-plugin.sh), so e2e
# runs against the fixtures only and stays deterministic.
MPT_DEMO_NO_LOCAL_PLUGINS=1 "$SCRIPT_DIR/setup-demo.sh" > /dev/null
ok "Demo fixtures in place"

# ─── Start Daemon ────────────────────────────────────────────────────

log "Starting MPT daemon on port $DAEMON_PORT..."
start_daemon
ok "Daemon running (PID $DAEMON_PID)"

# ─── Verify Story Loaded ─────────────────────────────────────────────

log "Verifying story and tasks..."
STORIES=$(curl -sf "$DAEMON_URL/api/stories")
STORY_COUNT=$(echo "$STORIES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['stories']))")
TASK_COUNT=$(echo "$STORIES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['stories'][0]['tasks']))")

if [ "$STORY_COUNT" -eq 0 ]; then
  err "No stories found in daemon"
  exit 1
fi

ok "Story loaded: $STORY_COUNT story, $TASK_COUNT tasks"

# ─── Pending WorkDefs ────────────────────────────────────────────────
#
# A pending WorkDef must never be enqueued, stays editable until activated, and is
# locked afterwards (my-pizza-team docs/DESIGN.md "Pending: Write, Review, Activate").
# Activated with enqueue:false and then deleted, so it doesn't add work to the demo.

log "Checking pending → activate..."
PENDING_ID=$(curl -sf -X POST "$DAEMON_URL/api/work-defs" -H "Content-Type: application/json" \
  -d '{"title":"E2E pending check","goal":"never runs","pending":true}' | json_field "d['workDef']['id']")
pending_items() {
  curl -sf "$DAEMON_URL/api/work-items" | python3 -c "import sys,json; print(len([i for i in json.load(sys.stdin)['items'] if i['ref']['workDefId']=='$PENDING_ID']))"
}
[ "$(pending_items)" -eq 0 ] || { err "Pending $PENDING_ID was enqueued"; exit 1; }
[ "$(http_code -X POST "$DAEMON_URL/api/work-defs/$PENDING_ID/enqueue")" = "409" ] || { err "Run on a pending WorkDef wasn't refused"; exit 1; }
[ "$(http_code -X PUT "$DAEMON_URL/api/work-defs/$PENDING_ID" -H "Content-Type: application/json" -d '{"goal":"edited"}')" = "200" ] || { err "Editing a pending WorkDef failed"; exit 1; }
[ "$(http_code -X POST "$DAEMON_URL/api/work-defs/$PENDING_ID/activate" -H "Content-Type: application/json" -d '{"enqueue":false}')" = "200" ] || { err "Activate failed"; exit 1; }
[ "$(http_code -X PUT "$DAEMON_URL/api/work-defs/$PENDING_ID" -H "Content-Type: application/json" -d '{"goal":"too late"}')" = "409" ] || { err "Active WorkDef was still editable"; exit 1; }
curl -sf -X DELETE "$DAEMON_URL/api/work-defs/$PENDING_ID" >/dev/null
ok "Pending: not enqueued, editable, locked once activated"

# ─── Demo-tracker plugin ─────────────────────────────────────────────
#
# fixtures/team/config.json loads plugins/mpt-source-demo-tracker in place. Check
# it loaded, that its open issues were mirrored and enqueued, and that write-back
# reaches the tracker file: a thread comment, and a canceled run's outcome. The
# canceled issue is re-run afterwards so the worker still gets both issues.
# The triage-mode issue (DEMO-3) gets its own section below.

log "Checking the demo-tracker plugin..."
TRACKER_SOURCE="demo-tracker"
PLUGIN_STATE=$(curl -sf "$DAEMON_URL/api/work-sources" | python3 -c "
import sys, json
d = json.load(sys.stdin)
p = [p for p in d['plugins'] if '$TRACKER_SOURCE' in p['sources']]
print(p[0]['state'] if p else 'missing: ' + json.dumps(d['plugins']))")
[ "$PLUGIN_STATE" = "loaded" ] || { err "demo-tracker plugin didn't load ($PLUGIN_STATE); see $DAEMON_LOG"; exit 1; }
ok "Plugin loaded (source '$TRACKER_SOURCE')"

# Sync runs at startup; give it a moment to mirror and enqueue the three open issues.
tracker_ready() {
  curl -sf "$DAEMON_URL/api/work-sources/$TRACKER_SOURCE/defs" | python3 -c "import sys,json; print(len([d for d in json.load(sys.stdin)['defs'] if d['latestState']=='READY']))"
}
for i in $(seq 1 30); do
  [ "$(tracker_ready)" -ge 3 ] && break
  sleep 0.5
done
[ "$(tracker_ready)" -ge 3 ] || { err "Tracker issues weren't mirrored + enqueued"; exit 1; }
ok "Tracker issues mirrored and enqueued (DEMO-1, DEMO-2, DEMO-3)"

# Wait (up to 5s) for a tracker issue's comments to contain a string.
tracker_has_comment() {
  for i in $(seq 1 10); do
    python3 -c "
import sys, json
issue = [i for i in json.load(open('$TRACKER_FILE'))['issues'] if i['id'] == '$1'][0]
sys.exit(0 if any('$2' in c['body'] for c in issue.get('comments', [])) else 1)" && return 0
    sleep 0.5
  done
  return 1
}

curl -sf -X POST "$DAEMON_URL/api/work-defs/$TRACKER_SOURCE~DEMO-1/comment" -H "Content-Type: application/json" \
  -d '{"from":"e2e","body":"e2e write-back check"}' >/dev/null
tracker_has_comment DEMO-1 "e2e write-back check" || { err "Comment wasn't written back to $TRACKER_FILE"; exit 1; }

DEMO2_ITEM=$(curl -sf "$DAEMON_URL/api/work-items?state=READY" | python3 -c "import sys,json; print([i['id'] for i in json.load(sys.stdin)['items'] if i['ref']['workDefId']=='$TRACKER_SOURCE~DEMO-2'][0])")
curl -sf -X POST "$DAEMON_URL/api/work-items/$DEMO2_ITEM/cancel" >/dev/null
tracker_has_comment DEMO-2 "ended CANCELED" || { err "Canceled run wasn't written back to $TRACKER_FILE"; exit 1; }
curl -sf -X POST "$DAEMON_URL/api/work-defs/$TRACKER_SOURCE~DEMO-2/enqueue" >/dev/null || { err "Re-running DEMO-2 failed"; exit 1; }
ok "Write-back lands in the tracker file (comment, canceled run); DEMO-2 re-queued"

# ─── Personas: the library, packages, and the tracker's personas ─────
#
# my-pizza-team docs/DESIGN.md "Personas: One Library, Selected by Reference".
# The fixture has one team persona (demo-coder, selected by the in_progress
# state), two packages shipping personas (plugins/mpt-personas-demo: personas
# only; the demo-tracker: its own tracker-worker, named as its defaultPersona),
# a Solitary task with a persona, and a per-source triage persona for the
# tracker (config.json sourcePersonas). Then each tracker item's run must get
# the persona its chain selects, and record it on the WorkItem:
#   DEMO-1 — a per-item override set here (via "workdef")
#   DEMO-2 — the source's declared default (via "source-default")
#   DEMO-3 — the per-source triage persona (via "source-setting"; next section)
# DEMO-1 and DEMO-2 are claimed as an unregistered agent and completed, then
# reopened in the tracker file (a new revision), so the worker still gets them.

log "Checking the persona library and persona packages..."
PERSONA_IDS=$(curl -sf "$DAEMON_URL/api/personas" | json_field "' '.join(sorted(p['id'] + ':' + p['origin']['kind'] + ':' + str(p['readOnly']) for p in d['personas']))")
EXPECTED_PERSONAS="builtin:assistant:builtin:True builtin:triage:builtin:True builtin:worker:builtin:True demo-coder:team:False mpt-personas-demo/careful-implementer:package:True mpt-personas-demo/careful-reviewer:package:True mpt-personas-demo/tracker-triager:package:True mpt-source-demo-tracker/tracker-worker:package:True"
[ "$PERSONA_IDS" = "$EXPECTED_PERSONAS" ] || { err "GET /api/personas: $PERSONA_IDS"; exit 1; }
PERSONAS_PLUGIN=$(curl -sf "$DAEMON_URL/api/work-sources" | json_field "[(p['state'], len(p['sources']), len(p['personas'])) for p in d['plugins'] if p['spec'].endswith('mpt-personas-demo')]")
[ "$PERSONAS_PLUGIN" = "[('loaded', 0, 3)]" ] || { err "mpt-personas-demo didn't load as a persona-only package: $PERSONAS_PLUGIN"; exit 1; }

REVIEWER="mpt-personas-demo%2Fcareful-reviewer"
[ "$(http_code -X PUT "$DAEMON_URL/api/personas/$REVIEWER" -H "Content-Type: application/json" -d '{"content":"edited"}')" = "409" ] || { err "A package persona was editable"; exit 1; }
[ "$(http_code -X DELETE "$DAEMON_URL/api/personas/$REVIEWER")" = "409" ] || { err "A package persona was deletable"; exit 1; }
COPY=$(curl -sf -X POST "$DAEMON_URL/api/personas/$REVIEWER/duplicate" -H "Content-Type: application/json" -d '{}' | json_field "d['persona']['id'], d['persona']['readOnly'], d['persona'].get('duplicatedFrom')")
[ "$COPY" = "careful-reviewer False mpt-personas-demo/careful-reviewer" ] || { err "Duplicating a package persona: $COPY"; exit 1; }
curl -sf -X DELETE "$DAEMON_URL/api/personas/careful-reviewer" >/dev/null || { err "Deleting the duplicate failed"; exit 1; }
[ "$(http_code -X DELETE "$DAEMON_URL/api/personas/demo-coder")" = "409" ] || { err "Deleting a persona in use wasn't refused"; exit 1; }

used_by() { curl -sf "$DAEMON_URL/api/personas/$1" | json_field "' '.join(sorted(u['kind'] + ':' + (u.get('state') or u.get('workDefId') or u.get('source') or '') for u in d['usedBy']))"; }
[ "$(used_by demo-coder)" = "workflow-state:in_progress" ] || { err "demo-coder isn't used by the in_progress state: $(used_by demo-coder)"; exit 1; }
[ "$(used_by "$REVIEWER")" = "workdef:audit-project-dependencies" ] || { err "careful-reviewer isn't used by the Solitary audit task: $(used_by "$REVIEWER")"; exit 1; }
[ "$(used_by mpt-personas-demo%2Ftracker-triager)" = "source-setting:demo-tracker" ] || { err "tracker-triager isn't demo-tracker's triage persona: $(used_by mpt-personas-demo%2Ftracker-triager)"; exit 1; }
TRACKER_PERSONAS=$(curl -sf "$DAEMON_URL/api/sources" | json_field "[(s['defaultPersona'], s['triagePersona'], s.get('personaError')) for s in d['sources'] if s['id'] == '$TRACKER_SOURCE']")
[ "$TRACKER_PERSONAS" = "[('mpt-source-demo-tracker/tracker-worker', 'mpt-personas-demo/tracker-triager', None)]" ] || { err "demo-tracker's personas on GET /api/sources: $TRACKER_PERSONAS"; exit 1; }
[ ! -e "$TEAM_DIR/.my-pizza-team/context.migrated" ] || { err "The persona-layout fixture was migrated (context.migrated/ exists)"; exit 1; }
ok "Personas: library lists team + built-in + package personas; package ones read-only (duplicate to edit); Used by; tracker default + triage persona"

log "Checking the tracker items' personas (prompt + recorded persona)..."
PERSONA_AGENT="e2e-persona-check"
IMPLEMENTER="mpt-personas-demo/careful-implementer"
[ "$(http_code -X PUT "$DAEMON_URL/api/work-defs/$TRACKER_SOURCE~DEMO-1/persona" -H "Content-Type: application/json" -d '{"persona":"no-such-persona"}')" = "400" ] \
  || { err "A per-item override naming a missing persona wasn't refused"; exit 1; }
curl -sf -X PUT "$DAEMON_URL/api/work-defs/$TRACKER_SOURCE~DEMO-1/persona" -H "Content-Type: application/json" -d "{\"persona\":\"$IMPLEMENTER\"}" >/dev/null \
  || { err "Setting DEMO-1's persona override failed"; exit 1; }

ready_item() { curl -sf "$DAEMON_URL/api/work-items?state=READY" | python3 -c "
import sys, json
items = [i['id'] for i in json.load(sys.stdin)['items'] if i['ref']['workDefId'] == '$TRACKER_SOURCE~$1']
print(items[0] if items else '')"; }
item_persona() { curl -sf "$DAEMON_URL/api/work-items/$1" | json_field "(lambda p: p and (p['id'], p['origin'], p['via']))(d['item'].get('persona'))"; }
# claim_check <issue> <text the prompt must contain> <expected "(id, origin, via)"> — claims, checks, completes.
claim_check() {
  local item; item=$(ready_item "$1")
  [ -n "$item" ] || { err "No READY WorkItem for $1"; exit 1; }
  curl -sf -X POST "$DAEMON_URL/api/agents/claim/$item" -H "Content-Type: application/json" -d "{\"agentId\":\"$PERSONA_AGENT\"}" \
    | python3 -c "import sys,json; p=json.load(sys.stdin)['prompt']; sys.exit(0 if p.startswith('## Your Role') and sys.argv[1] in p else 1)" "$2" \
    || { err "$1's prompt doesn't carry its persona ('$2')"; exit 1; }
  [ "$(item_persona "$item")" = "$3" ] || { err "$1's run recorded persona $(item_persona "$item"), expected $3"; exit 1; }
  curl -sf -X POST "$DAEMON_URL/api/agents/work-items/$item/state" -H "Content-Type: application/json" \
    -d "{\"agentId\":\"$PERSONA_AGENT\",\"state\":\"COMPLETE\"}" >/dev/null || { err "Completing $1 failed"; exit 1; }
  eval "$4=$item"
}
claim_check DEMO-1 "You are a **careful implementer**" "('$IMPLEMENTER', 'package:mpt-personas-demo', 'workdef')" DEMO1_RUN
claim_check DEMO-2 "You are working an issue from the **Demo Tracker**" "('mpt-source-demo-tracker/tracker-worker', 'package:mpt-source-demo-tracker', 'source-default')" DEMO2_RUN

# Reopen both in the tracker (status open + a new updatedAt = a new revision) once
# the completions are written back, and sync: both are mirrored and queued again.
for i in $(seq 1 20); do
  [ "$(python3 -c "import json; print(' '.join(i['status'] for i in json.load(open('$TRACKER_FILE'))['issues'] if i['id'] in ('DEMO-1','DEMO-2')))")" = "done done" ] && break
  sleep 0.5
done
python3 - "$TRACKER_FILE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for issue in data["issues"]:
    if issue["id"] in ("DEMO-1", "DEMO-2"):
        issue["status"], issue["updatedAt"] = "open", issue["updatedAt"].replace("2024-06-01", "2024-06-02")
json.dump(data, open(sys.argv[1], "w"), indent=2)
PY
curl -s -o /dev/null -X POST "$DAEMON_URL/api/work-sources/$TRACKER_SOURCE/sync"
for i in $(seq 1 30); do
  [ -n "$(ready_item DEMO-1)" ] && [ -n "$(ready_item DEMO-2)" ] && break
  sleep 0.5
done
[ -n "$(ready_item DEMO-1)" ] && [ -n "$(ready_item DEMO-2)" ] || { err "Reopened DEMO-1/DEMO-2 weren't queued again"; exit 1; }
OVERRIDE=$(curl -sf "$DAEMON_URL/api/work-defs/$TRACKER_SOURCE~DEMO-1" | json_field "d['workDef']['mirror'].get('personaOverride')")
[ "$OVERRIDE" = "$IMPLEMENTER" ] || { err "DEMO-1's persona override didn't survive the re-sync ($OVERRIDE)"; exit 1; }
# The finished runs keep the persona they ran with (the run history's snapshot).
[ "$(item_persona "$DEMO1_RUN")" = "('$IMPLEMENTER', 'package:mpt-personas-demo', 'workdef')" ] || { err "DEMO-1's finished run lost its persona"; exit 1; }
ok "Tracker personas: DEMO-1 per-item override, DEMO-2 source default — in each prompt and on each run; override kept across re-sync; both re-queued"

# ─── Demo-tracker: a triage-mode issue ───────────────────────────────
#
# DEMO-3 has "mode": "triage" (my-pizza-team docs/DESIGN.md "External sources" —
# "Triage mode"): its run is a *triage* of the mirror, not work on it. Play the
# teammate through the agent API as an unregistered id (so it never shows up as
# a member): claim it and get the triage prompt, post a propose_work-style
# analysis, finish, then accept the proposal as the user would. Accepting creates
# a task and never runs it; a finished triage leaves the issue open. DEMO-3 is
# re-queued at the end (Triage now) so the worker triages it for real.

log "Checking the triage-mode issue (DEMO-3)..."
TRIAGE_DEF="$TRACKER_SOURCE~DEMO-3"
TRIAGER="e2e-triager"
DEMO3_MODE=$(curl -sf "$DAEMON_URL/api/work-sources/$TRACKER_SOURCE/defs" | python3 -c "import sys,json; print([d.get('mode') for d in json.load(sys.stdin)['defs'] if d['id']=='$TRIAGE_DEF'][0])")
[ "$DEMO3_MODE" = "triage" ] || { err "DEMO-3 isn't in triage mode ($DEMO3_MODE)"; exit 1; }
DEMO3_ITEM=$(curl -sf "$DAEMON_URL/api/work-items?state=READY" | python3 -c "
import sys, json
items = [i for i in json.load(sys.stdin)['items'] if i['ref']['workDefId'] == '$TRIAGE_DEF']
print(items[0]['id'] if items and items[0]['title'].startswith('Triage: ') else '')")
[ -n "$DEMO3_ITEM" ] || { err "No 'Triage: …' WorkItem enqueued for DEMO-3"; exit 1; }

curl -sf -X POST "$DAEMON_URL/api/agents/claim/$DEMO3_ITEM" -H "Content-Type: application/json" \
  -d "{\"agentId\":\"$TRIAGER\"}" | python3 -c "
import sys, json
p = json.load(sys.stdin)['prompt']
sys.exit(0 if '## Your Role: Triage' in p and 'You are the **tracker triager**' in p and 'DEMO-3' in p and 'due date' in p else 1)" \
  || { err "DEMO-3's claim prompt isn't the triage prompt with the tracker-triager persona"; exit 1; }
# Its triage persona is the per-source setting (config.json sourcePersonas) — in the prompt and on the run.
[ "$(item_persona "$DEMO3_ITEM")" = "('mpt-personas-demo/tracker-triager', 'package:mpt-personas-demo', 'source-setting')" ] \
  || { err "DEMO-3's run recorded persona $(item_persona "$DEMO3_ITEM"), not the per-source triage persona"; exit 1; }

PROPOSE_CODE=$(http_code -X POST "$DAEMON_URL/api/agents/work-items/$DEMO3_ITEM/proposals" -H "Content-Type: application/json" -d "{
  \"agentId\": \"$TRIAGER\", \"outcome\": \"proposals\",
  \"body\": \"One small task covers it: an optional dueDate plus an overdue filter. No schedule needed yet.\",
  \"proposals\": [{ \"id\": \"p1\", \"kind\": \"task\", \"title\": \"Add due dates and GET /todos?overdue=true\",
    \"goal\": \"Accept an optional ISO dueDate on POST /todos and list overdue todos with ?overdue=true.\",
    \"directory\": \"$PROJECT_DIR\" }]
}")
[ "$PROPOSE_CODE" = "200" ] || { err "propose_work on DEMO-3 was refused ($PROPOSE_CODE)"; exit 1; }
triage_view() { curl -sf "$DAEMON_URL/api/work-defs/$TRIAGE_DEF/triage" | json_field "$1"; }
[ "$(triage_view "d['badge'], len(d['pending'])")" = "proposal 1" ] || { err "DEMO-3's proposal isn't pending"; exit 1; }

curl -sf -X POST "$DAEMON_URL/api/agents/work-items/$DEMO3_ITEM/state" -H "Content-Type: application/json" \
  -d "{\"agentId\":\"$TRIAGER\",\"state\":\"COMPLETE\"}" >/dev/null || { err "Completing DEMO-3's triage failed"; exit 1; }
tracker_has_comment DEMO-3 "ended COMPLETE" || { err "DEMO-3's triage outcome wasn't written back"; exit 1; }
DEMO3_STATUS=$(python3 -c "import json; print([i['status'] for i in json.load(open('$TRACKER_FILE'))['issues'] if i['id']=='DEMO-3'][0])")
[ "$DEMO3_STATUS" = "open" ] || { err "A finished triage closed DEMO-3 ($DEMO3_STATUS)"; exit 1; }

CREATED=$(curl -sf -X POST "$DAEMON_URL/api/work-defs/$TRIAGE_DEF/triage/proposals/p1/accept" | json_field "d['decision']['workDefId']")
[ -n "$CREATED" ] || { err "Accepting DEMO-3's proposal created nothing"; exit 1; }
# The created task names its origin in its frontmatter (originWorkDef), and has never run.
grep -q "originWorkDef: .*$TRIAGE_DEF" "$TEAM_DIR/.my-pizza-team/tasks/$CREATED/workdef.md" \
  || { err "Accepted task $CREATED doesn't link back to DEMO-3"; exit 1; }
CREATED_RUNS=$(curl -sf "$DAEMON_URL/api/work-items" | python3 -c "import sys,json; print(len([i for i in json.load(sys.stdin)['items'] if i['ref']['workDefId']=='$CREATED']))")
[ "$CREATED_RUNS" -eq 0 ] || { err "Accepting a proposal started its work"; exit 1; }
[ "$(triage_view "d['badge'], len(d['pending'])")" = "none 0" ] || { err "DEMO-3 still shows a pending proposal after accepting"; exit 1; }

curl -sf -X POST "$DAEMON_URL/api/work-defs/$TRIAGE_DEF/enqueue" >/dev/null || { err "Triage now on DEMO-3 failed"; exit 1; }
ok "Triage mode: DEMO-3 triaged (prompt + per-source triage persona, propose_work, accept → task $CREATED, not run), left open, re-queued"

# ─── Demo-tracker: settings from the UI (Config → Sources) ───────────
#
# The plugin declares a configSchema and a preview hook (my-pizza-team GUIDE.md
# "Setting up a plugin from the UI"). Drive the same routes the Sources tab uses:
#   1. GET  /api/sources lists demo-tracker with its schema and saved settings;
#   2. POST /api/sources/demo-tracker/preview with a draft pointing at a scratch
#      copy of the tracker (plus E2E-1) shows E2E-1 — and mirrors nothing;
#   3. PUT  /api/sources/demo-tracker/config saves that draft: config.json is
#      rewritten, the plugin re-initialized live, and the next sync mirrors E2E-1;
#   4. switching it off is refused while it has mirrors (409); a disconnect
#      switches it off and archives them, and a sync while it's off pulls nothing;
#   5. restore: the original settings, switch it back on, DEMO-1..3 come back and
#      are re-queued for the worker.

log "Checking plugin settings, preview, toggle and disconnect (demo-tracker)..."
SCRATCH_TRACKER="$DEMO_DIR/tracker/e2e-scratch.json"
python3 - "$TRACKER_FILE" "$SCRATCH_TRACKER" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["issues"].append({"id": "E2E-1", "title": "E2E settings check", "body": "Mirrored only while the e2e points demo-tracker at this file.",
                       "status": "open", "updatedAt": "2024-07-01T00:00:00Z", "comments": []})
json.dump(data, open(sys.argv[2], "w"), indent=2)
PY

source_view() { curl -sf "$DAEMON_URL/api/sources" | python3 -c "
import sys, json
s = [s for s in json.load(sys.stdin)['sources'] if s['id'] == '$TRACKER_SOURCE'][0]
print($1)"; }
[ "$(source_view "s['kind'], s['configScope'], sorted(s.get('configSchema', {}).get('properties', {})) == sorted(['file','directory','intervalSeconds','mode','urlBase']), s['previewable'], s['toggle']")" \
  = "plugin package True True {'feature': 'demo-tracker', 'enabled': True}" ] \
  || { err "GET /api/sources doesn't list demo-tracker with its schema and toggle: $(source_view s)"; exit 1; }
SAVED_OPTIONS=$(source_view "json.dumps(s['options'])")
DRAFT_OPTIONS=$(echo "$SAVED_OPTIONS" | python3 -c "import sys,json; o=json.load(sys.stdin); o['file']='../../tracker/e2e-scratch.json'; print(json.dumps(o))")
ok "GET /api/sources: demo-tracker is a plugin source with a configSchema and its own toggle"

all_defs() { curl -sf "$DAEMON_URL/api/work-sources/$TRACKER_SOURCE/defs?status=all" | python3 -c "import sys,json; print(' '.join(sorted(d['externalId']+':'+d['status'] for d in json.load(sys.stdin)['defs'])))"; }
active_defs() { curl -sf "$DAEMON_URL/api/work-sources/$TRACKER_SOURCE/defs" | python3 -c "import sys,json; print(' '.join(sorted(d['externalId'] for d in json.load(sys.stdin)['defs'])))"; }
# Wait (up to 10s) for the active mirrors to be exactly $1.
wait_active_defs() {
  for i in $(seq 1 20); do
    [ "$(active_defs)" = "$1" ] && return 0
    sleep 0.5
  done
  return 1
}
DEFS_BEFORE=$(all_defs)
PREVIEW=$(curl -s -X POST "$DAEMON_URL/api/sources/$TRACKER_SOURCE/preview" -H "Content-Type: application/json" -d "{\"options\": $DRAFT_OPTIONS}")
[ "$(echo "$PREVIEW" | json_field "d['success'], d['via'], sorted(i['externalId'] for i in d['items'])")" = "True preview ['DEMO-1', 'DEMO-2', 'DEMO-3', 'E2E-1']" ] \
  || { err "Preview with the draft settings didn't show E2E-1: $PREVIEW"; exit 1; }
[ "$(all_defs)" = "$DEFS_BEFORE" ] || { err "Preview changed the mirrors ($DEFS_BEFORE → $(all_defs))"; exit 1; }
BAD_PREVIEW=$(http_code -X POST "$DAEMON_URL/api/sources/$TRACKER_SOURCE/preview" -H "Content-Type: application/json" -d '{"options":{"mode":"sometimes"}}')
[ "$BAD_PREVIEW" = "400" ] || { err "Preview with an invalid mode wasn't refused ($BAD_PREVIEW)"; exit 1; }
ok "Preview: shows what the draft would pull (E2E-1 included), mirrors nothing, refuses invalid settings"

SAVE=$(curl -s -X PUT "$DAEMON_URL/api/sources/$TRACKER_SOURCE/config" -H "Content-Type: application/json" -d "{\"options\": $DRAFT_OPTIONS}")
[ "$(echo "$SAVE" | json_field "d['success'], d['reinit']")" = "True [{'id': '$TRACKER_SOURCE', 'ok': True}]" ] || { err "Saving the settings failed: $SAVE"; exit 1; }
python3 -c "
import json, sys
pkgs = json.load(open('$TEAM_DIR/.my-pizza-team/config.json'))['packages']
sys.exit(0 if any(isinstance(p, dict) and p.get('config', {}).get('file') == '../../tracker/e2e-scratch.json' for p in pkgs) else 1)" \
  || { err "Save didn't write packages[].config.file to config.json"; exit 1; }
# The re-init syncs at once; force one too (a 409 "in-flight" just means that one's running).
curl -s -o /dev/null -X POST "$DAEMON_URL/api/work-sources/$TRACKER_SOURCE/sync"
wait_active_defs "DEMO-1 DEMO-2 DEMO-3 E2E-1" || { err "The sync after the Save doesn't reflect it: $(active_defs)"; exit 1; }
ok "Save: config.json updated, plugin re-initialized without a restart, next sync mirrored E2E-1"

FEATURES_OFF_CODE=$(curl -sf "$DAEMON_URL/api/config" | python3 -c "
import sys, json
b = json.load(sys.stdin)
for k in ('featureUsage', 'featureSources', 'defaultNouns'): b.pop(k, None)
b['features'] = {'$TRACKER_SOURCE': False}
print(json.dumps(b))" | curl -s -o /dev/null -w "%{http_code}" -X PUT "$DAEMON_URL/api/config" -H "Content-Type: application/json" -d @-)
[ "$FEATURES_OFF_CODE" = "409" ] || { err "Switching demo-tracker off with active mirrors wasn't refused ($FEATURES_OFF_CODE)"; exit 1; }
DISCONNECT=$(curl -s -X POST "$DAEMON_URL/api/work-sources/$TRACKER_SOURCE/disconnect")
[ "$(echo "$DISCONNECT" | json_field "d['success'], d['feature'], len(d['archived'])")" = "True $TRACKER_SOURCE 4" ] || { err "Disconnect failed: $DISCONNECT"; exit 1; }
# Its defs route is gated now (403), so read the mirrors' workdef.md files.
STILL_ACTIVE=$(grep -L "^status: archived" "$TEAM_DIR/.my-pizza-team/tasks/$TRACKER_SOURCE~"*/workdef.md || true)
[ -z "$STILL_ACTIVE" ] || { err "Disconnect left active mirrors: $STILL_ACTIVE"; exit 1; }
[ "$(http_code "$DAEMON_URL/api/work-sources/$TRACKER_SOURCE/defs")" = "403" ] || { err "demo-tracker's Work routes aren't gated while it's off"; exit 1; }
[ "$(source_view "s['toggle']['enabled']")" = "False" ] || { err "demo-tracker is still on after the disconnect"; exit 1; }
# While off: a new issue isn't pulled, by a forced sync (refused) or the 10s timer.
python3 - "$SCRATCH_TRACKER" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["issues"].append({"id": "E2E-2", "title": "Must not be pulled while off", "status": "open", "updatedAt": "2024-07-02T00:00:00Z", "comments": []})
json.dump(data, open(sys.argv[1], "w"), indent=2)
PY
# (Its Work routes are gated while it's off, so look at /api/sources and the mirror files.)
LAST_SYNC_AT=$(source_view "(s['sync']['last'] or {}).get('at')")
OFF_SYNC=$(http_code -X POST "$DAEMON_URL/api/work-sources/$TRACKER_SOURCE/sync")
[ "$OFF_SYNC" != "200" ] || { err "A switched-off demo-tracker still synced"; exit 1; }
sleep 12
[ "$(source_view "(s['sync']['last'] or {}).get('at')")" = "$LAST_SYNC_AT" ] || { err "demo-tracker synced while switched off"; exit 1; }
[ ! -e "$TEAM_DIR/.my-pizza-team/tasks/$TRACKER_SOURCE~E2E-2" ] || { err "demo-tracker pulled E2E-2 while switched off"; exit 1; }
ok "Off: switch-off refused while it has mirrors (409); disconnect archived 4 mirrors; no sync while off ($OFF_SYNC)"

# Restore the fixture settings and switch it back on (the Sources tab's checkbox).
RESTORE=$(curl -s -X PUT "$DAEMON_URL/api/sources/$TRACKER_SOURCE/config" -H "Content-Type: application/json" -d "{\"options\": $SAVED_OPTIONS}")
[ "$(echo "$RESTORE" | json_field "d['success']")" = "True" ] || { err "Restoring the settings failed: $RESTORE"; exit 1; }
ON_CODE=$(curl -sf "$DAEMON_URL/api/config" | python3 -c "
import sys, json
b = json.load(sys.stdin)
for k in ('featureUsage', 'featureSources', 'defaultNouns'): b.pop(k, None)
b['features'] = {'$TRACKER_SOURCE': True}
print(json.dumps(b))" | curl -s -o /dev/null -w "%{http_code}" -X PUT "$DAEMON_URL/api/config" -H "Content-Type: application/json" -d @-)
[ "$ON_CODE" = "200" ] || { err "Switching demo-tracker back on failed ($ON_CODE)"; exit 1; }
curl -s -o /dev/null -X POST "$DAEMON_URL/api/work-sources/$TRACKER_SOURCE/sync"
wait_active_defs "DEMO-1 DEMO-2 DEMO-3" || { err "Switching back on didn't restore DEMO-1..3 (active: $(active_defs))"; exit 1; }
for issue in DEMO-1 DEMO-2 DEMO-3; do
  curl -sf -X POST "$DAEMON_URL/api/work-defs/$TRACKER_SOURCE~$issue/enqueue" >/dev/null || { err "Re-queuing $issue failed"; exit 1; }
done
rm -f "$SCRATCH_TRACKER"
ok "Back on: fixture settings restored, DEMO-1..3 back and re-queued (E2E-1 stays archived)"

# ─── Launch Pi Leader ─────────────────────────────────────────────────

log "Launching Pi leader in tmux..."

# Create tmux session with leader window
# Note: if tmux-resurrect/continuum is installed, starting the tmux server
# may trigger session restoration. We add a brief delay to let that settle.
tmux new-session -d -s "$TMUX_SESSION" -n "leader" -c "$TEAM_DIR"
sleep 2

# Verify session was created
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  err "Failed to create tmux session '$TMUX_SESSION'"
  exit 1
fi

tmux send-keys -t "$TMUX_SESSION:leader" \
  "pi --ppt-lead --ppt-daemon=$DAEMON_URL" Enter

ok "Pi leader launched in tmux session '$TMUX_SESSION' window 'leader'"

# Give leader time to connect and register
log "Waiting for leader to connect..."
for i in $(seq 1 20); do
  AGENT_COUNT=$(curl -sf "$DAEMON_URL/api/agents" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('agents',[])))" 2>/dev/null || echo "0")
  if [ "$AGENT_COUNT" -gt 0 ]; then
    break
  fi
  sleep 1
done

if [ "$AGENT_COUNT" -gt 0 ]; then
  ok "Leader connected ($AGENT_COUNT agent(s) registered)"
else
  warn "Leader may not have connected yet (no agents registered after 20s)"
  warn "Check: tmux attach -t $TMUX_SESSION"
  warn "Daemon log: $DAEMON_LOG"
fi

# ─── Spawn Worker Agent ──────────────────────────────────────────────

log "Requesting worker spawn in $PROJECT_DIR..."

# Create a leader directive — the daemon (or, without tmux access, the leader)
# realizes it. There is one leader, so the queue isn't keyed by host.
SPAWN_RES=$(curl -sf -X POST "$DAEMON_URL/api/leader/directives" \
  -H "Content-Type: application/json" \
  -d "{\"action\": \"spawn\", \"params\": {\"cwd\": \"$PROJECT_DIR\", \"reason\": \"e2e-test\"}}")

SPAWN_OK=$(echo "$SPAWN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success', False))" 2>/dev/null || echo "False")

if [ "$SPAWN_OK" != "True" ]; then
  err "Failed to create spawn directive"
  err "Response: $SPAWN_RES"
  exit 1
fi

ok "Spawn directive created — leader will pick it up"

# Wait for the leader to spawn the worker
log "Waiting for worker to appear..."
for i in $(seq 1 30); do
  CURRENT_AGENTS=$(curl -sf "$DAEMON_URL/api/agents" 2>/dev/null | python3 -c "import sys,json; agents=json.load(sys.stdin).get('agents',[]); print(len([a for a in agents if a['id'] != 'leader']))" 2>/dev/null || echo "0")
  if [ "$CURRENT_AGENTS" -gt 0 ]; then
    break
  fi
  sleep 1
done

if [ "$CURRENT_AGENTS" -gt 0 ]; then
  WORKER_NAME=$(curl -sf "$DAEMON_URL/api/agents" 2>/dev/null | python3 -c "import sys,json; agents=json.load(sys.stdin).get('agents',[]); w=[a for a in agents if a['id'] != 'leader']; print(w[0]['name'] if w else 'unknown')" 2>/dev/null || echo "unknown")
  ok "Worker '$WORKER_NAME' spawned by leader"
else
  err "Leader didn't spawn a worker within 30s"
  err "Check: tmux attach -t $TMUX_SESSION"
  err "Daemon log: $DAEMON_LOG"
  exit 1
fi

# ─── The worker's in-flight persona ──────────────────────────────────
#
# Once the worker claims something, GET /api/agents carries the persona its run
# recorded at claim (the UI's ✦ chip): demo-coder for a board task (the
# in_progress state's persona), the tracker's for a tracker item. The worker's
# pace is up to the model, so this waits up to 2 minutes and only warns.

log "Waiting for the worker's in-flight persona (GET /api/agents)..."
worker_persona() { curl -sf "$DAEMON_URL/api/agents" 2>/dev/null | python3 -c "
import sys, json
w = [a for a in json.load(sys.stdin).get('agents', []) if a['id'] != 'leader' and a.get('persona')]
print(f\"{w[0]['name']} is working {w[0]['workItemId']} as '{w[0]['persona']['title']}' ({w[0]['persona']['id']}, via {w[0]['persona']['via']})\" if w else '')" 2>/dev/null || true; }
WORKER_PERSONA=""
for i in $(seq 1 60); do
  WORKER_PERSONA=$(worker_persona)
  [ -n "$WORKER_PERSONA" ] && break
  sleep 2
done
if [ -n "$WORKER_PERSONA" ]; then
  ok "In-flight persona: $WORKER_PERSONA"
else
  warn "The worker hasn't claimed work with a persona yet (check: tmux attach -t $TMUX_SESSION)"
fi

# ─── Status Summary ──────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}✅ E2E environment running!${NC}"
echo ""
echo "  Daemon:    $DAEMON_URL (PID $DAEMON_PID)"
echo "  Daemon log: $DAEMON_LOG"
echo "  UI:        $DAEMON_URL/"
echo "  tmux:      tmux attach -t $TMUX_SESSION"
echo ""
echo "  Leader:    $TMUX_SESSION:leader (in $TEAM_DIR)"
echo "  Worker:    $WORKER_NAME (in $PROJECT_DIR)"
echo ""
echo "  Story:     'Add User Authentication' (3 tasks)"
echo "  Tracker:   $TRACKER_FILE (demo-tracker plugin: DEMO-1, DEMO-2; DEMO-3 triage-mode)"
echo "  Workflow:  todo → in_progress → review → done (in_progress persona: demo-coder)"
echo "  Personas:  $DAEMON_URL/config/personas (team demo-coder; packages mpt-personas-demo, mpt-source-demo-tracker)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Attach to tmux to watch:"
echo "  tmux attach -t $TMUX_SESSION"
echo ""
echo "Monitor via API:"
echo "  curl $DAEMON_URL/api/status | python3 -m json.tool"
echo ""
echo "Stop everything:"
echo "  ./run-e2e.sh --clean"
echo ""

# ─── Wait / Monitor ──────────────────────────────────────────────────

log "Monitoring... (Ctrl+C to stop and clean up)"
echo ""

# Poll daemon status until interrupted
while true; do
  STATUS=$(curl -sf "$DAEMON_URL/api/status" 2>/dev/null || echo "{}")
  TASKS_BY_STATUS=$(echo "$STATUS" | python3 -c "
import sys, json, urllib.request
try:
    d = json.load(sys.stdin)
    by_status = d.get('tasks', {}).get('byStatus', {})
    agents = d.get('members', {})
    parts = [f'{k}:{v}' for k,v in sorted(by_status.items())]
    working = agents.get('working', 0)
    idle = agents.get('idle', 0)
    try:
        issues = json.load(open('$TRACKER_FILE'))['issues']
        tracker = ' '.join(f\"{i['id']}:{i['status']}\" for i in issues)
    except Exception:
        tracker = '?'
    try:
        agents_list = json.load(urllib.request.urlopen('$DAEMON_URL/api/agents', timeout=2)).get('agents', [])
        personas = ', '.join(f\"{a['name']}✦{a['persona']['title']}\" for a in agents_list if a.get('persona'))
    except Exception:
        personas = ''
    print(f'Tasks: {\" | \".join(parts) or \"none\"}  Tracker: {tracker}  Agents: {working} working, {idle} idle' + (f'  Personas: {personas}' if personas else ''))
except:
    print('(waiting for status...)')
" 2>/dev/null || echo "(daemon unreachable)")
  echo -ne "\r  📊 $TASKS_BY_STATUS    \r"
  sleep 3
done
