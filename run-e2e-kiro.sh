#!/usr/bin/env bash
#
# run-e2e-kiro.sh — End-to-end test run using Kiro CLI + MCP server.
#
# Same demo as run-e2e.sh but uses kiro-cli and mpt-mcp-server instead
# of Pi with the pi-pizza-team extension.
#
# Prerequisites:
#   - `kiro-cli` installed (https://kiro.dev)
#   - `deno` available (for running the daemon from source)
#   - `node` available (for the MCP server and runner)
#   - `tmux` available (for observing agents)
#
# Usage:
#   ./run-e2e-kiro.sh          # Run the full E2E flow
#   ./run-e2e-kiro.sh --clean  # Clean up any running processes and exit
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPT_SOURCE="$SCRIPT_DIR/../my-pizza-team"
MCP_SERVER="$SCRIPT_DIR/../mpt-mcp-server"
DEMO_DIR="$SCRIPT_DIR/demo"
TEAM_DIR="$DEMO_DIR/team"
PROJECT_DIR="$DEMO_DIR/project"
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

if ! command -v kiro-cli &>/dev/null; then
  err "kiro-cli not found. Install from https://kiro.dev"
  exit 1
fi

if ! command -v deno &>/dev/null; then
  err "deno not found. Install: https://deno.land/#installation"
  exit 1
fi

if ! command -v node &>/dev/null; then
  err "node not found."
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

if [ ! -d "$MCP_SERVER" ]; then
  err "mpt-mcp-server not found at $MCP_SERVER"
  exit 1
fi

ok "All dependencies found (kiro-cli, deno, node, tmux)"

# ─── Setup Demo ──────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🍕 MPT End-to-End Test Run (Kiro + MCP Server)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log "Setting up demo fixtures..."
"$SCRIPT_DIR/setup-demo.sh" > /dev/null
ok "Demo fixtures in place"

# ─── Start Daemon ────────────────────────────────────────────────────

log "Starting MPT daemon on port $DAEMON_PORT..."

# Run daemon from source in background, capture output to log
DAEMON_LOG="$DEMO_DIR/daemon.log"
cd "$MPT_SOURCE"
TEAM_DIR="$TEAM_DIR/.my-pizza-team" PORT=$DAEMON_PORT \
  deno run --allow-net --allow-read --allow-write --allow-env --allow-ffi --allow-run \
  daemon/main.ts > "$DAEMON_LOG" 2>&1 &
DAEMON_PID=$!
cd "$SCRIPT_DIR"

# Wait for daemon to be ready
for i in $(seq 1 30); do
  if curl -sf "$DAEMON_URL/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 $DAEMON_PID 2>/dev/null; then
    err "Daemon process exited unexpectedly"
    err "Check: $DAEMON_LOG"
    exit 1
  fi
  sleep 0.5
done

if ! curl -sf "$DAEMON_URL/health" >/dev/null 2>&1; then
  err "Daemon failed to start within 15 seconds"
  exit 1
fi

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

# ─── Launch Kiro Runner in tmux ───────────────────────────────────────

log "Requesting agent name from daemon..."

# Get a proper name from the daemon via a spawn directive (kiro executes the
# spawn itself, so we immediately mark the directive done).
HOST_ID=$(hostname)
SPAWN_RES=$(curl -sf -X POST "$DAEMON_URL/api/hosts/$HOST_ID/leader/directives" \
  -H "Content-Type: application/json" \
  -d "{\"action\": \"spawn\", \"params\": {\"cwd\": \"$PROJECT_DIR\", \"reason\": \"e2e-kiro\"}}")

WORKER_NAME=$(echo "$SPAWN_RES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('directive',{}).get('params',{}).get('name','kiro-worker'))" 2>/dev/null || echo "kiro-worker")

# Mark the directive done (we're handling the spawn ourselves)
DIR_ID=$(echo "$SPAWN_RES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('directive',{}).get('id',''))" 2>/dev/null || echo "")
if [ -n "$DIR_ID" ]; then
  curl -sf -X PUT "$DAEMON_URL/api/hosts/$HOST_ID/leader/directives/$DIR_ID" \
    -H "Content-Type: application/json" -d '{"status": "done"}' >/dev/null 2>&1 || true
fi

ok "Agent name: $WORKER_NAME"

log "Launching Kiro runner in tmux..."

# Create tmux session with the runner/leader window
tmux new-session -d -s "$TMUX_SESSION" -n "runner" -c "$PROJECT_DIR"
sleep 2

# Verify session was created
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  err "Failed to create tmux session '$TMUX_SESSION'"
  exit 1
fi

# Launch the Kiro runner (orchestrator: polls, claims, releases)
# It spawns kiro-cli in a separate tmux window named '$WORKER_NAME' for each task
tmux send-keys -t "$TMUX_SESSION:runner" \
  "MPT_DAEMON_URL=$DAEMON_URL MPT_AGENT_ID=$WORKER_NAME MPT_WORK_DIR=$PROJECT_DIR MPT_TMUX_SESSION=$TMUX_SESSION node $MCP_SERVER/src/runners/kiro/runner.mjs" Enter

ok "Runner launched in '$TMUX_SESSION:runner' (agent tasks appear as '$WORKER_NAME' window)"

# ─── Status Summary ──────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}✅ E2E environment running! (Kiro + MCP)${NC}"
echo ""
echo "  Daemon:      $DAEMON_URL (PID $DAEMON_PID)"
echo "  Daemon log:  $DAEMON_LOG"
echo "  MCP server:  $MCP_SERVER/src/index.mjs"
echo "  UI:          $DAEMON_URL/"
echo "  tmux:        tmux attach -t $TMUX_SESSION"
echo ""
echo "  Runner:      $TMUX_SESSION:runner (orchestrator)"
echo "  Agent:       $TMUX_SESSION:$WORKER_NAME (kiro-cli, visible per task)"
echo ""
echo "  Story:       'Add User Authentication' (3 tasks)"
echo "  Workflow:    todo → in_progress → review → done"
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
echo "  ./run-e2e-kiro.sh --clean"
echo ""

# ─── Wait / Monitor ──────────────────────────────────────────────────

log "Monitoring... (Ctrl+C to stop and clean up)"
echo ""

# Poll daemon status until interrupted
while true; do
  STATUS=$(curl -sf "$DAEMON_URL/api/status" 2>/dev/null || echo "{}")
  TASKS_BY_STATUS=$(echo "$STATUS" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    by_status = d.get('tasks', {}).get('byStatus', {})
    agents = d.get('members', {})
    parts = [f'{k}:{v}' for k,v in sorted(by_status.items())]
    working = agents.get('working', 0)
    idle = agents.get('idle', 0)
    print(f'Tasks: {\" | \".join(parts) or \"none\"}  Agents: {working} working, {idle} idle')
except:
    print('(waiting for status...)')
" 2>/dev/null || echo "(daemon unreachable)")
  echo -ne "\r  📊 $TASKS_BY_STATUS    \r"
  sleep 3
done
