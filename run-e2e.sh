#!/usr/bin/env bash
#
# run-e2e.sh — End-to-end test run for MPT.
#
# Sets up the demo, starts the daemon, launches a Pi leader,
# and spawns a worker agent to execute tasks.
#
# Prerequisites:
#   - `pi` installed globally (npm i -g @earendil-works/pi-coding-agent)
#   - `pi-pizza-team` extension installed (pi install /path/to/pi-pizza-team)
#   - `deno` available (for running the daemon from source)
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
DAEMON_PORT=7437
DAEMON_URL="http://localhost:$DAEMON_PORT"
TMUX_SESSION="mpt-e2e"
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

if ! command -v deno &>/dev/null; then
  err "deno not found. Install: https://deno.land/#installation"
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

# ─── Setup Demo ──────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🍕 MPT End-to-End Test Run"
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
  "cd $TEAM_DIR && pi" Enter

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

log "Spawning worker agent in $PROJECT_DIR..."

# Request a spawn via the daemon API
SPAWN_RES=$(curl -sf -X POST "$DAEMON_URL/api/spawn-requests" \
  -H "Content-Type: application/json" \
  -d "{\"hostId\": \"local\", \"cwd\": \"$PROJECT_DIR\", \"reason\": \"e2e-test\"}")

SPAWN_OK=$(echo "$SPAWN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success', False))" 2>/dev/null || echo "False")

if [ "$SPAWN_OK" = "True" ]; then
  ok "Spawn request created via API"
  # The leader polls for spawn requests and executes them.
  # If leader isn't connected, fall back to direct spawn.
  sleep 3
  # Check if a new agent appeared
  NEW_AGENT_COUNT=$(curl -sf "$DAEMON_URL/api/agents" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('agents',[])))" 2>/dev/null || echo "0")
  if [ "$NEW_AGENT_COUNT" -le "${AGENT_COUNT:-0}" ]; then
    warn "Leader didn't pick up spawn request, spawning directly..."
    tmux new-window -n "worker" -t "$TMUX_SESSION" -c "$PROJECT_DIR"
    tmux send-keys -t "$TMUX_SESSION:worker" \
      "cd $PROJECT_DIR && pi --ppt-worker --ppt-daemon=$DAEMON_URL --ppt-name=ripley" Enter
    ok "Worker spawned directly in tmux"
  else
    ok "Leader spawned the worker"
  fi
else
  # Fallback: spawn directly via tmux
  warn "API spawn request failed, spawning directly via tmux..."
  tmux new-window -n "worker" -t "$TMUX_SESSION" -c "$PROJECT_DIR"
  tmux send-keys -t "$TMUX_SESSION:worker" \
    "cd $PROJECT_DIR && pi --ppt-worker --ppt-daemon=$DAEMON_URL --ppt-name=ripley" Enter
  ok "Worker spawned directly in tmux"
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
echo "  Worker:    spawning in $PROJECT_DIR"
echo ""
echo "  Story:     'Add User Authentication' (3 tasks)"
echo "  Workflow:  todo → in_progress → review → done"
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
