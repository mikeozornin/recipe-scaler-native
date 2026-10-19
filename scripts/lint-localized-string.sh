#!/usr/bin/env bash
# i18n policy lint: block new `String(localized:)` in the app target.
# See docs/I18N.md («Смена языка в рантайме»).
#
# The in-app language switch redirects `Bundle.localizedString` to the selected
# `.lproj`, but `String(localized:)` can resolve past it and come out in the
# system language. App code uses `Bundle.currentLocalizedString("key")` instead.
#
# Existing calls are frozen per file in scripts/lint-localized-string.baseline;
# a file fails when it has more calls than its baseline entry. A line that must
# keep the system language (e.g. code that only runs in an extension) can opt
# out with a trailing `// i18n: system-language` comment.
#
# Usage: bash scripts/lint-localized-string.sh            # check
#        bash scripts/lint-localized-string.sh --update   # rewrite the baseline
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCAN_DIR="RecipeScalerNative"
BASELINE="scripts/lint-localized-string.baseline"
PATTERN='String\(localized:'
OPT_OUT='// i18n: system-language'

# "<count> <path>" for every Swift file with calls that are not opted out.
current_counts() {
  rg -n --no-heading --color never -g '*.swift' "$PATTERN" "$SCAN_DIR" </dev/null \
    | grep -vF "$OPT_OUT" \
    | cut -d: -f1 \
    | sort | uniq -c \
    | awk '{print $1, $2}' \
    || true
}

if [[ "${1:-}" == "--update" ]]; then
  {
    echo "# Frozen String(localized:) calls per file. Regenerate: bash scripts/lint-localized-string.sh --update"
    current_counts
  } > "$BASELINE"
  echo "Updated $BASELINE ($(grep -vc '^#' "$BASELINE") files)."
  exit 0
fi

baseline_count() {
  awk -v f="$1" '$2 == f {print $1; found=1} END {if (!found) print 0}' "$BASELINE"
}

violations=()
shrunk=0
while read -r count file; do
  [[ -n "$file" ]] || continue
  allowed="$(baseline_count "$file")"
  if (( count > allowed )); then
    violations+=("$file: $count call(s), baseline $allowed")
    while IFS= read -r line; do
      violations+=("    $line")
    done < <(rg -n --no-heading --color never "$PATTERN" "$file" | grep -vF "$OPT_OUT")
  elif (( count < allowed )); then
    shrunk=1
  fi
done < <(current_counts)

if [[ ${#violations[@]} -eq 0 ]]; then
  echo "PASS: no new String(localized:) in $SCAN_DIR."
  if (( shrunk )); then
    echo "Note: some files now have fewer calls than the baseline; tighten it with --update."
  fi
  exit 0
fi

echo "FAIL: new String(localized:) in the app target:"
printf '  %s\n' "${violations[@]}"
echo
echo "It can skip the in-app language and show the system language. Use"
echo "Bundle.currentLocalizedString(\"key\") (or Text(\"key\") in SwiftUI). If the line"
echo "really needs the system language, end it with '$OPT_OUT'."
exit 1
