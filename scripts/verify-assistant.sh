#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/015-assistant/screenshots"
LOG_FILE="$ROOT/.verify-assistant.ndjson"

# Sanity: the view + accessibility id must exist in source.
rg -q 'struct AssistantSheet' RecipeScalerNative/Views/AssistantSheet.swift
rg -q 'AccessibilityIdentifiers.assistantSheet' RecipeScalerNative/Views/AssistantSheet.swift
rg -q 'showAssistant' RecipeScalerNative/Views/AppShellView.swift

sim_build >/dev/null
sim_prepare
sim_install

# `sim_launch` unsets SIMCTL_CHILD_AGENT_DEBUG_LOG, but we need both env vars to be
# present in the launched process so AgentSyncDebugLog writes the NDJSON trace.
# Mirror the pattern from scripts/debug-recipe-detail.sh.
rm -f "$LOG_FILE"
xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
if [[ -n "$container" ]]; then
  rm -f \
    "$container/Library/Application Support/debug-session.ndjson" \
    "$container/Library/Caches/debug-session.ndjson" \
    "$container/Library/Caches/$BUNDLE_ID/debug-session.ndjson" 2>/dev/null || true
fi
export SIMCTL_CHILD_AGENT_DEBUG_LOG="$LOG_FILE"
export SIMCTL_CHILD_AGENT_DEBUG_LOG_ENABLED="1"
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" -SkipSplash=1 -ShowAssistant=1 >/dev/null

sleep 10
SHOT="$(sim_screenshot "$SHOT_DIR" "assistant")"
echo "Screenshot: $SHOT"

# Pull the on-device NDJSON into $LOG_FILE if simctl didn't write it directly there.
if [[ ! -s "$LOG_FILE" ]]; then
  if [[ -n "${container:-}" ]]; then
    for candidate in \
      "$container/Library/Application Support/debug-session.ndjson" \
      "$container/Library/Caches/debug-session.ndjson" \
      "$container/Library/Caches/$BUNDLE_ID/debug-session.ndjson"; do
      if [[ -f "$candidate" ]]; then
        cp "$candidate" "$LOG_FILE"
        break
      fi
    done
  fi
fi

if [[ ! -s "$LOG_FILE" ]]; then
  echo "FAIL: debug-session.ndjson missing or empty at $LOG_FILE"
  echo "  (check that AGENT_DEBUG_LOG_ENABLED was propagated and AssistantSheet.onAppear ran)"
  exit 1
fi

if ! rg -q 'assistant_sheet_appeared' "$LOG_FILE"; then
  echo "FAIL: AssistantSheet did not appear (no 'assistant_sheet_appeared' in debug-session.ndjson)"
  echo "---- last log lines ----"
  tail -20 "$LOG_FILE" || true
  exit 1
fi

echo "VERIFIED assistant (sheet opened)"
