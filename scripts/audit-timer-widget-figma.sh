#!/usr/bin/env bash
# TimerWidget layout audit — delegates to generic layout-audit runner.
# Kept for backward compatibility; prefer: bash scripts/audit-ui-layout.sh specs/030-timer-widget

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/scripts/audit-ui-layout.sh" specs/030-timer-widget
