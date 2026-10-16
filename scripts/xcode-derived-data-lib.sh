#!/usr/bin/env bash
# Find the Xcode DerivedData folders built from one checkout (main copy or a worktree).
# Xcode keeps one DerivedData folder per project path and records that path as
# WorkspacePath in the folder's info.plist.
#
# Source: source "$(dirname "${BASH_SOURCE[0]}")/xcode-derived-data-lib.sh"
# Usage:  xcode_derived_data_of <checkout-root> [derived-data-root]
#         prints matching folders NUL-separated; read with `while IFS= read -r -d '' dir`.

# The "/" suffix keeps .../checkout from matching .../checkout-other.
xcode_derived_data_of() {
  local checkout="${1%/}" root="${2:-$HOME/Library/Developer/Xcode/DerivedData}"
  local dir path
  for dir in "$root"/*/; do
    dir="${dir%/}"
    [[ -d "$dir" ]] || continue
    path="$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$dir/info.plist" 2>/dev/null)" || continue
    [[ "$path" == "$checkout/"* ]] && printf '%s\0' "$dir"
  done
  return 0
}
