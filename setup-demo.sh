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

# --- Patch config with actual paths ---
DEMO_PROJECT_PATH="$SCRIPT_DIR/demo/project"
TEAM_DIR_PATH="$SCRIPT_DIR/demo/team/.my-pizza-team"

# Seed the recent `directory` capability with the real demo project path so it
# shows up as a spawn/requirement suggestion in the UI.
CONFIG_FILE="$TEAM_DIR_PATH/config.json"
python3 -c "
import json, sys
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)
cfg.setdefault('recentCapabilities', {})['directory'] = ['$DEMO_PROJECT_PATH']
with open('$CONFIG_FILE', 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
"
echo "   ✓ config.json patched with real paths"

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
echo "The demo project is a simple todo API in demo/project/src/index.ts"
echo "Agents will modify it as they work through the tasks."
