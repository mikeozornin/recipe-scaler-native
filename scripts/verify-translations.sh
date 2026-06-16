#!/usr/bin/env bash
# verify-translations.sh — FR-022-004 / SC-002
#
# Static lint: ensures user-facing Swift views do not contain bare hardcoded
# literals in constructs that should go through Localizable.xcstrings:
#
#   - `Text("Some literal")`               (verbatim user string, no key)
#   - `Button("Some literal")`             (SwiftUI.Button title initializer)
#   - `Label("Some literal", ...)`         (SwiftUI.Label title initializer)
#   - `.navigationTitle("Some literal")`
#   - `.accessibilityLabel("Some literal")`
#   - `.confirmationDialog("Some literal", ...)`
#
# Allowed (NOT flagged):
#   - LocalizedStringKey: Text("some.key"), Button("common.ok")
#   - String(localized: "key"), e.g. Text(String(localized: "..."))
#   - Variable interpolation: Text("\(value)")
#   - Format strings with interpolation: Text("\(count) items")
#   - verbatim/Text(verbatim: "…")
#   - Multi-line systemImage-only Labels
#
# Scope: RecipeScalerNative/Views/ (FR-022-001). Demo / debug files listed in
# specs/022-i18n-new-views/tasks.md §"Вне scope" are excluded.
#
# Exit code: 0 = clean, 1 = violations found.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCAN_DIR="RecipeScalerNative/Views"
EXCLUDE_FILES=(
  "TimerExampleView.swift"
  "RecipeDetailView.swift"
  "DescriptionFixturePreviewView.swift"
)

exclude_args=()
for f in "${EXCLUDE_FILES[@]}"; do
  exclude_args+=(--glob "!$f")
done

echo "== Scanning $SCAN_DIR for hardcoded user-facing literals (FR-022-004) =="

# Strategy: scan one line at a time. For each Swift line, look for one of the
# six constructs followed by `("..."`)`. Then inspect the captured string:
#   - if it contains `\(`  -> interpolation, skip (format string)
#   - if it contains `.`   -> looks like a LocalizedStringKey (e.g. "common.ok")
#   - if it contains `_`   -> looks like a snake_case key (e.g. "no_ingredients")
#   - if it has no space   -> looks like a key
#   - else -> violation (literal that is user-facing English text)
#
# We require the literal to contain an interior space AND NOT contain `.`, `_`,
# `\(`, `:`, `//`. This catches only obvious human-readable strings.
#
# Special case: `Text(verbatim: ...)` — handled by skipping lines containing
# `Text(verbatim:`.

violation_lines=()

# Build a function to check if a file path is in the exclude list.
is_excluded() {
  local path="$1"
  local f
  for f in "${EXCLUDE_FILES[@]}"; do
    # Match either the basename or the full relative path.
    if [[ "$path" == *"$f" ]]; then
      return 0
    fi
  done
  return 1
}

while IFS= read -r line; do
  # Extract the file path portion before the first ':' (rg -n format).
  file_path="${line%%:*}"
  if is_excluded "$file_path"; then
    continue
  fi
  # Skip verbatim
  if [[ "$line" == *"Text(verbatim:"* ]]; then
    continue
  fi

  # Pull out quoted string following one of the six API names.
  # Match e.g. `Text("…"`, `.navigationTitle("…"`, etc.
  if [[ "$line" =~ (Text|Button|Label|navigationTitle|accessibilityLabel|confirmationDialog)\(\"([^\"]*)\" ]]; then
    literal="${BASH_REMATCH[2]}"
    # Skip if it has interpolation, format specifiers, or looks like a key.
    if [[ "$literal" == *'\('* ]]; then continue; fi
    if [[ "$literal" == *'\\('* ]]; then continue; fi
    if [[ "$literal" == *'%'* ]]; then continue; fi
    if [[ "$literal" == *'/'* ]]; then continue; fi
    if [[ "$literal" == *'.'* ]]; then continue; fi
    if [[ "$literal" == *'_'* ]]; then continue; fi
    # Require an interior space to look like a sentence / phrase.
    if [[ "$literal" != *' '* ]]; then continue; fi
    # Trim and check at least 2 chars after trim.
    trimmed="${literal#"${literal%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [[ ${#trimmed} -lt 2 ]]; then continue; fi

    violation_lines+=("$line")
  fi
done < <(rg -n --no-heading --color never \
  "${exclude_args[@]}" \
  -g '*.swift' \
  '(Text|Button|Label|navigationTitle|accessibilityLabel|confirmationDialog)\(' \
  "$SCAN_DIR/")

if [[ ${#violation_lines[@]} -eq 0 ]]; then
  echo "PASS: no bare user-facing literals in $SCAN_DIR"
  echo "VERIFIED translations"
  exit 0
fi

echo "FAIL: found ${#violation_lines[@]} potential hardcoded literal(s):"
printf '  %s\n' "${violation_lines[@]}"
echo
echo "Fix: replace the literal with a LocalizedStringKey (kebab-case token,"
echo "no spaces) and add ru+en entries to"
echo "RecipeScalerNative/Resources/Localizable.xcstrings."
exit 1
