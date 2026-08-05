#!/usr/bin/env bash
#
# run-ui.sh — Bring up the MPT demo UI only (no agents).
#
# Sets up the demo fixtures and starts the MPT daemon from source so you can
# browse the board / tasks / schedule in a browser. Unlike run-e2e.sh, this
# launches NO leader and NO worker — it's purely for viewing the seeded data.
#
# Prerequisites:
#   - `deno` available (for running the daemon from source)
#
# Usage:
#   ./run-ui.sh          # Set up fixtures + start the daemon (Ctrl+C to stop)
#   ./run-ui.sh --clean  # Stop a running daemon and exit
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPT_SOURCE="$SCRIPT_DIR/../my-pizza-team"
DEMO_DIR="$SCRIPT_DIR/demo"
TEAM_DIR="$DEMO_DIR/team/.my-pizza-team"
DAEMON_PORT="${PORT:-7437}"
DAEMON_URL="http://localhost:$DAEMON_PORT"

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
  # Kill whatever is bound to the daemon port (the daemon we started).
  local port_pid
  port_pid=$(lsof -ti :"$DAEMON_PORT" 2>/dev/null || true)
  if [ -n "$port_pid" ]; then
    kill "$port_pid" 2>/dev/null || true
    ok "Daemon stopped (port $DAEMON_PORT)"
  fi
}

if [ "${1:-}" = "--clean" ]; then
  cleanup
  exit 0
fi

# ─── Preflight ────────────────────────────────────────────────────────

if ! command -v deno &>/dev/null; then
  err "deno not found. Install: https://deno.land/#installation"
  exit 1
fi

if [ ! -d "$MPT_SOURCE" ]; then
  err "my-pizza-team source not found at $MPT_SOURCE"
  exit 1
fi

# Refuse to trample an already-running daemon on this port.
if lsof -ti :"$DAEMON_PORT" >/dev/null 2>&1; then
  err "Port $DAEMON_PORT is already in use. Stop it first: ./run-ui.sh --clean"
  exit 1
fi

# ─── Setup Demo ──────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🍕 MPT Demo UI (no agents)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log "Setting up demo fixtures..."
"$SCRIPT_DIR/setup-demo.sh" > /dev/null
ok "Demo fixtures in place ($TEAM_DIR)"

# ─── Start Daemon (foreground) ───────────────────────────────────────

echo ""
ok "Starting daemon — open ${DAEMON_URL}/ in your browser"
echo ""
echo "  Board:     ${DAEMON_URL}/board"
echo "  Tasks:     ${DAEMON_URL}/tasks"
echo "  Schedule:  ${DAEMON_URL}/schedule"
echo ""
echo "  Seeded: 'Add User Authentication' (3 tasks), a paused 'Polish the UI"
echo "  Theme' story, plus Solitary + Scheduled standalone WorkDefs."
echo ""
echo "  Ctrl+C to stop."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run in the foreground so Ctrl+C stops it directly. The UI is served from
# my-pizza-team/ui/dist (resolved relative to the daemon's main module).
cd "$MPT_SOURCE"
exec env TEAM_DIR="$TEAM_DIR" PORT="$DAEMON_PORT" \
  deno run --allow-net --allow-read --allow-write --allow-env --allow-ffi --allow-run \
  daemon/main.ts
