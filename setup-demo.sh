#!/usr/bin/env bash
#
# setup-demo.sh — Copies the demo fixtures into place for running MPT.
#
# Creates:
#   ./demo/project/          — The demo todo API code (agents work here)
#   ./demo/team/.my-pizza-team/  — The team directory (MPT daemon reads this)
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
echo "   ✓ story + WorkDef directories pointed at the demo project"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Demo ready! Use these paths with MPT:"
echo ""
echo "   Team dir:     $TEAM_DIR_PATH"
echo "   Project dir:  $DEMO_PROJECT_PATH"
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
echo "Plus a paused story (\"Polish the UI Theme\") and two standalone WorkDefs:"
echo "   • Solitary:  Audit project dependencies   (Tasks page → Run)"
echo "   • Scheduled: Nightly test run @ 2am        (Schedule page → Run now)"
echo ""
echo "The demo project is a simple todo API in demo/project/src/index.ts"
echo "Agents will modify it as they work through the tasks."
