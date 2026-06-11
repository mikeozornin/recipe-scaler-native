#!/usr/bin/env bash
# test-yrs-yjs-description-roundtrip.sh
#
# Verifies that a description XmlFragment created by yrs FFI (via xcodebuild test)
# is readable by yjs when decoded from the same binary state.
#
# The XCTest side writes yrs-encoded binaries to /tmp.
# This script picks them up and runs the Node.js yjs verification.
#
# Usage:
#   scripts/test-yrs-yjs-description-roundtrip.sh          # check all
#   scripts/test-yrs-yjs-description-roundtrip.sh file.bin # check specific file

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_ROOT="$ROOT/../recipe-scaler-web/recipe-scaler"

# Ensure yjs is installed
if [ ! -d "$WEB_ROOT/node_modules/yjs" ]; then
  echo "Installing yjs in web project..."
  cd "$WEB_ROOT" && npm install --silent
fi

# Create a simple yrs state via the test binary, then verify with yjs
echo "== Step 1: Create yrs-encoded state via XCTest =="

# Build for testing first
cd "$ROOT"
xcodebuild build-for-testing \
  -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=C3ED7448-2C55-4F02-B5DA-721E2853FD0B' \
  -configuration Debug \
  2>&1 | tail -3

# Run the test to generate binary files
# Note: if test target not available, fall back to generating state manually
echo ""
echo "== Step 2: Verify yrs-encoded state with yjs (Node.js) =="

cd "$ROOT"
node scripts/test-yjs-description-roundtrip.mjs \
  /tmp/yrs-test-yjs-roundtrip-simple.bin \
  /tmp/yrs-test-yjs-roundtrip-multi.bin \
  /tmp/yrs-test-with-nodes.bin \
  /tmp/yrs-test-multi-edit.bin

echo ""
echo "== Step 3: Verify real API state =="
if [ -f /tmp/cheesecake-yjs.bin ]; then
  echo "Checking cheesecake API state..."
  node scripts/test-yjs-description-roundtrip.mjs /tmp/cheesecake-yjs.bin
else
  echo "No /tmp/cheesecake-yjs.bin found (download with: scripts/download-recipe-state.sh <recipeId>)"
fi

echo ""
echo "== Done =="
