#!/usr/bin/env bash
# Fast local policy gates (no simulator / no xcodebuild).
# Report-only lints stay non-blocking unless *_BLOCK=1 is set by the script itself.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failed=0
run() {
  local name="$1"
  shift
  echo "== $name =="
  if "$@"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name" >&2
    failed=1
  fi
}

run "shell-self-tests-sim-verify" bash scripts/tests/test-sim-verify-lib.sh
run "shell-self-tests-verify-all-lock" bash scripts/tests/test-verify-all-lock.sh
run "verify-plan-state" bash scripts/verify-plan-state.sh
run "verify-plan-policy-template" python3 scripts/verify-plan-policy.py .specify/templates/overrides/plan-template.md
run "test-quarantine" python3 scripts/check-test-quarantine.py scripts/test-quarantine.json
run "e2e-skip-budget" python3 -c "import json; json.load(open('scripts/e2e-skip-budget.json'))"
run "check-md-links" python3 scripts/check-md-links.py AGENTS.md README.md docs/AGENT-WORKFLOW.md docs/agents/ASYNC-LIFECYCLE.md docs/agents/VERIFICATION.md
run "lint-composition-root" bash scripts/lint-composition-root.sh
run "lint-release-api" bash scripts/lint-release-api.sh

if (( failed )); then
  echo "FAILED: one or more policy checks" >&2
  exit 1
fi
echo "All policy checks passed."
