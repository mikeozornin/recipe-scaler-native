#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/015-assistant/screenshots"

rg -q 'AssistantSheet' RecipeScalerNative/Views/AssistantSheet.swift

sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1 -ShowAssistant=1

sim_wait_ready 8
SHOT="$(sim_screenshot "$SHOT_DIR" "assistant")"
echo "Screenshot: $SHOT"
echo "VERIFIED assistant"