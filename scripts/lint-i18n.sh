#!/usr/bin/env bash
# lint-i18n.sh
#
# Static lint for hardcoded user-facing strings. Extends verify-translations.sh
# with broader directory coverage, more SwiftUI constructs, and a check that
# each detected literal is actually absent from Localizable.xcstrings.
#
# Why this exists: ~200 i18n-related user corrections in a 30-day window. Most
# came from views shipping English literals that never reached the strings
# catalog. The existing verify-translations.sh only scans Views/ and skips
# several SwiftUI entry points; closing that gap is cheaper than fixing the
# resulting user-visible bug after release.
#
# Scope:
#   - RecipeScalerNative/Views/
#   - RecipeScalerNative/LiveActivity/
#   - RecipeScalerNative/ContentView.swift, RecipeScalerNativeApp.swift
#   - RecipeScalerNativeWatch/ (if present)
#
# Constructs flagged:
#   Text("…")                Button("…")             Label("…", …)
#   .navigationTitle("…")    .navigationSubtitle("…")
#   .accessibilityLabel("…") .accessibilityHint("…") .accessibilityValue("…")
#   .confirmationDialog("…", …)  .alert("…", …)
#   .help("…")               .prompt("…")            .overlayText("…")
#   Menu("…")                Section("…")
#
# Allowed (NOT flagged):
#   - LocalizedStringKey: Text("common.ok"), Button("recipes.title.edit")
#       detected by: presence of `.` or snake_case or kebab-case
#   - String(localized: "…")
#   - Interpolation: Text("\(count) items")
#   - Text(verbatim: "…")
#   - Single-word literals without spaces (assume token)
#   - Numbers / punctuation-only
#
# Two-pass scan:
#   1) regex per Swift line (catches the construct shape)
#   2) key cross-check against Localizable.xcstrings — only flag if the literal
#      is neither a plausible key (has `.` / `_` / `-`) nor a known xcstrings
#      value. This keeps the signal-to-noise ratio useful: we report *probable*
#      English sentences shipped to users, not every quoted identifier.
#
# Exit codes: 0 = clean, 1 = violations found.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCAN_DIRS=(
  "RecipeScalerNative/Views"
  "RecipeScalerNative/LiveActivity"
)
EXTRA_FILES=(
  "RecipeScalerNative/ContentView.swift"
  "RecipeScalerNative/RecipeScalerNativeApp.swift"
)
[[ -d "RecipeScalerNativeWatch" ]] && SCAN_DIRS+=("RecipeScalerNativeWatch")

# Demo / fixture views that intentionally carry non-localized literals.
EXCLUDE_FILES=(
  "TimerExampleView.swift"
  "RecipeDetailView.swift"
  "DescriptionFixturePreviewView.swift"
)

XCSTRINGS="RecipeScalerNative/Resources/Localizable.xcstrings"

if [[ ! -f "$XCSTRINGS" ]]; then
  echo "FAIL: $XCSTRINGS not found" >&2
  exit 1
fi

exclude_args=()
for f in "${EXCLUDE_FILES[@]}"; do
  exclude_args+=(--glob "!$f")
done

echo "== i18n lint: hardcoded UI literals =="
echo "   scan: ${SCAN_DIRS[*]} + ${EXTRA_FILES[*]}"

is_excluded() {
  local path="$1" f
  for f in "${EXCLUDE_FILES[@]}"; do
    [[ "$path" == *"$f" ]] && return 0
  done
  return 1
}

# Heuristic: looks like a localization key rather than a sentence.
# Keys in this project: kebab-case (foo.bar), snake_case (foo_bar),
# dotted (account.profile.title). A literal with a space and none of these
# characters is almost certainly a sentence.
looks_like_key() {
  local s="$1"
  [[ -z "$s" ]] && return 1
  # Interpolation / format / url — skip.
  [[ "$s" == *'\('* ]] && return 0
  [[ "$s" == *'\\('* ]] && return 0
  [[ "$s" == *'%'* ]] && return 0
  [[ "$s" == *'/'* ]] && return 0
  # Keys contain `.`, `_`, or `-`.
  [[ "$s" == *.* ]] && return 0
  [[ "$s" == *_* ]] && return 0
  [[ "$s" == *-* ]] && return 0
  # No interior space → assume token.
  [[ "$s" != *' '* ]] && return 0
  return 1  # not a key → probably a sentence
}

# Build a list of values present in Localizable.xcstrings so we can recognise
# a literal that is the *value* of an existing key (still allowed). Plist
# values are JSON strings, so use python to extract them safely.
extract_xcstrings_values() {
  python3 - "$XCSTRINGS" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
out = []
for _key, entry in (data.get("strings") or {}).items():
    for _lang, loc in (entry.get("localizations") or {}).items():
        v = (loc.get("stringUnit") or {}).get("value")
        if v:
            out.append(v)
print("\n".join(out))
PY
}

XCVALUES_TMP="$(mktemp)"
trap 'rm -f "$XCVALUES_TMP"' EXIT
extract_xcstrings_values > "$XCVALUES_TMP" || true

# Construct pattern for the constructs we flag.
# Match `(Name|Name2|…)\("…"` where the literal is a normal quoted string.
CONSTRUCTS_RE='(Text|Button|Label|navigationTitle|navigationSubtitle|accessibilityLabel|accessibilityHint|accessibilityValue|confirmationDialog|alert|help|prompt|overlayText|Menu|Section)\("([^"]*)"'

violation_lines=()

scan_file() {
  local file="$1"
  is_excluded "$file" && return 0
  [[ "$file" == *"Text(verbatim:"* ]] && return 0

  # Read line by line. rg -n gives file:line:content.
  while IFS= read -r raw; do
    # raw is `path:lineno:content`
    local content="${raw#*:*:}"
    content="${content#*:*:}"  # strip path and lineno
    [[ "$content" == *"Text(verbatim:"* ]] && continue

    if [[ "$raw" =~ $CONSTRUCTS_RE ]]; then
      local literal="${BASH_REMATCH[2]}"
      if ! looks_like_key "$literal"; then
        # Not a key. Is it an existing xcstrings value? Then it is allowed
        # (probably the developer wrote the value directly under a known key).
        if grep -Fxq -- "$literal" "$XCVALUES_TMP" 2>/dev/null; then
          continue
        fi
        violation_lines+=("$raw")
      fi
    fi
  done < <(rg -n --no-heading --color never -g '*.swift' "$file" 2>/dev/null || true)
}

# Walk directories.
for dir in "${SCAN_DIRS[@]}"; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r -d '' f; do
    scan_file "$f"
  done < <(find "$dir" -name '*.swift' -print0)
done

# Walk extra individual files.
for f in "${EXTRA_FILES[@]}"; do
  [[ -f "$f" ]] && scan_file "$f"
done

if [[ ${#violation_lines[@]} -eq 0 ]]; then
  echo "PASS: no bare user-facing literals outside xcstrings values."
  echo "VERIFIED lint-i18n"
  exit 0
fi

echo "FAIL: ${#violation_lines[@]} potential hardcoded literal(s):"
printf '  %s\n' "${violation_lines[@]}"
echo
echo "Fix: replace each literal with a LocalizedStringKey (kebab-case / dotted"
echo "token without spaces) and add ru + en entries to"
echo "$XCSTRINGS."
echo
echo "If the literal is a real xcstrings *value* (sentence shipped under a key),"
echo "the script already whitelists it — so a violation here means the sentence"
echo "is NOT in the catalog."
exit 1
