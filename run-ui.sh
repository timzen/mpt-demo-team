#!/usr/bin/env bash
#
# run-ui.sh — Bring up the MPT demo UI only (no agents).
#
# Sets up the demo fixtures and starts the MPT daemon from source so you can
# browse the board / tasks / schedule in a browser. Unlike run-e2e.sh, this
# launches NO leader and NO worker — it's purely for viewing the seeded data.
#
# Prerequisites:
#   - `node` 24+ available (runs the daemon from source; plugins need Node's module hooks)
#
# Usage:
#   ./run-ui.sh            # Set up fixtures + start the daemon (Ctrl+C to stop)
#   ./run-ui.sh --restart  # Stop a running daemon, then set up + start again
#                          # (the plugin rebuild loop: build the plugin, then this)
#   ./run-ui.sh --clean    # Stop a running daemon and exit
#   ./run-ui.sh --legacy   # Same, on the pre-persona team layout (./setup-demo.sh
#                          # --legacy): watch the daemon migrate it on start
#
# Once the daemon is healthy it prints each plugin package's load status, its
# sources and how many personas it ships (GET /api/work-sources) — the
# demo-tracker, the mpt-personas-demo persona package, plus anything in
# plugins.local.json (see ./try-plugin.sh).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPT_SOURCE="$SCRIPT_DIR/../my-pizza-team"
DEMO_DIR="$SCRIPT_DIR/demo"
TEAM_DIR="$DEMO_DIR/team/.my-pizza-team"
DAEMON_PORT="${PORT:-6789}"
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

SETUP_ARGS=()
case "${1:-}" in
  --clean) cleanup; exit 0 ;;
  --legacy) SETUP_ARGS=(--legacy) ;;
  --restart)
    cleanup
    # Wait (up to 10s) for the port to be released before starting again.
    for i in $(seq 1 20); do
      lsof -ti :"$DAEMON_PORT" >/dev/null 2>&1 || break
      sleep 0.5
    done
    ;;
  "") ;;
  -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) err "Unknown option $1 (try --restart, --clean or --legacy)"; exit 1 ;;
esac

# ─── Preflight ────────────────────────────────────────────────────────

if ! command -v node &>/dev/null; then
  err "node not found. Install Node.js 24+: https://nodejs.org/"
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
"$SCRIPT_DIR/setup-demo.sh" ${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"} > /dev/null
ok "Demo fixtures in place ($TEAM_DIR)"

# ─── Start Daemon ─────────────────────────────────────────────────────

# In the background (output still goes to this terminal) so the plugin
# statuses can be printed once it's healthy; Ctrl+C / --clean / --restart
# stop it. The UI is served from my-pizza-team/ui/dist (resolved relative to
# the daemon's main module).
log "Starting daemon on port $DAEMON_PORT..."
(cd "$MPT_SOURCE" && exec env TEAM_DIR="$TEAM_DIR" PORT="$DAEMON_PORT" node daemon/main.ts) &
DAEMON_PID=$!
stop_daemon() { kill "$DAEMON_PID" 2>/dev/null || true; wait "$DAEMON_PID" 2>/dev/null || true; }
trap 'stop_daemon; exit 130' INT TERM

for i in $(seq 1 60); do
  curl -sf "$DAEMON_URL/health" >/dev/null 2>&1 && break
  if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
    err "Daemon exited during startup (see its output above)"
    exit 1
  fi
  sleep 0.5
done
if ! curl -sf "$DAEMON_URL/health" >/dev/null 2>&1; then
  err "Daemon didn't become healthy within 30s"
  stop_daemon
  exit 1
fi

# ─── Plugin statuses ──────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Plugins (GET /api/work-sources)"
echo ""
curl -sf "$DAEMON_URL/api/work-sources" | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
  const { plugins = [], sources = [] } = JSON.parse(s);
  const label = new Map(sources.map((x) => [x.id, x.label]));
  if (!plugins.length) console.log("  (no plugin packages configured)");
  for (const p of plugins) {
    const names = p.sources.map((id) => label.get(id) && label.get(id) !== id ? `${id} ("${label.get(id)}")` : id);
    const personas = (p.personas || []).length;
    if (personas) names.push(`${personas} persona${personas === 1 ? "" : "s"}`);
    const srcs = names.join(", ") || "no sources";
    if (p.state === "loaded") console.log(`  \x1b[0;32m✓\x1b[0m ${p.spec} — ${srcs}`);
    else console.log(`  \x1b[0;31m✗\x1b[0m ${p.spec} — ${p.error}${p.sources.length ? ` (still registered: ${srcs})` : ""}`);
  }
});' || warn "Couldn't read $DAEMON_URL/api/work-sources"

echo ""
ok "Daemon running (PID $DAEMON_PID) — open ${DAEMON_URL}/ in your browser"
echo ""
echo "  Board:     ${DAEMON_URL}/board"
echo "  Tasks:     ${DAEMON_URL}/tasks"
echo "  Schedule:  ${DAEMON_URL}/schedule"
echo ""
echo "  Seeded: 'Add User Authentication' (3 tasks), a pending 'Polish the UI"
echo "  Theme' story, plus Solitary + Scheduled standalone WorkDefs, and the"
echo "  demo-tracker plugin's 3 issues (Work → Demo Tracker; edit"
echo "  $DEMO_DIR/tracker/tracker.json to re-sync). Personas: Config → Personas."
echo ""
echo "  Ctrl+C to stop. After rebuilding a plugin: ./run-ui.sh --restart"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Stay in the foreground until the daemon exits (Ctrl+C here, or --clean /
# --restart from another terminal).
wait "$DAEMON_PID" || true
