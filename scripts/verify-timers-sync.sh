#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

test -f specs/014-timers-sync/BLOCKER.md
rg -q 'MobileTimerPanel' RecipeScalerNative/Views/MobileTimerPanel.swift
rg -q 'TimerSyncService' RecipeScalerNative/Services/TimerSyncService.swift
rg -q 'timer_event' RecipeScalerNative/Services/YjsSync/YjsSyncService.swift
rg -q 'loadActiveTimersFromServer' RecipeScalerNative/Services/TimerSyncService.swift
rg -q 'pauseTimer' RecipeScalerNative/Views/MobileTimerPanel.swift
rg -q 'onTimerTap' RecipeScalerNative/Views/RecipeDescriptionInlineTextView.swift
rg -q 'createAndStartTimer' RecipeScalerNative/Views/RecipeDetailView.swift
rg -q 'func tabRoot' RecipeScalerNative/Views/AppShellView.swift
rg -q 'safeAreaInset\(edge: \.bottom' RecipeScalerNative/Views/AppShellView.swift

source "$ROOT/scripts/sim-verify-lib.sh"
SHOT_DIR="$ROOT/specs/014-timers-sync/screenshots"

sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1

sim_wait_ready 5
SHOT="$(sim_screenshot "$SHOT_DIR" "timers-panel")"
echo "Screenshot: $SHOT"
echo "VERIFIED timers-sync (static + panel screenshot; cross-device SC-001/SC-002 — manual per BLOCKER.md)"