#!/usr/bin/env bash
# Fixture self-test for scripts/verify-ipad-layout.sh (spec 081): the pixel
# comparison must fail on changed, missing or resized screenshots and pass only
# on identical ones (or changes inside the recorded unstable mask).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# The pixel tool is cached under the default output root; the mask case below relies on it.
unset IPAD_VERIFY_OUT
SCRIPT="$REPO_ROOT/scripts/verify-ipad-layout.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Writes an RGB PNG: base color, optional rectangle "x,y,w,h,r,g,b".
png() {
  python3 - "$@" <<'PY'
import struct
import sys
import zlib

path, width, height, base = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
rect = sys.argv[5] if len(sys.argv) > 5 else None
base_rgb = tuple(int(v) for v in base.split(","))
rx = ry = rw = rh = 0
rect_rgb = base_rgb
if rect:
    rx, ry, rw, rh, *rgb = (int(v) for v in rect.split(","))
    rect_rgb = tuple(rgb)
rows = []
for y in range(height):
    row = bytearray(b"\x00")
    for x in range(width):
        inside = rect and rx <= x < rx + rw and ry <= y < ry + rh
        row += bytes(rect_rgb if inside else base_rgb)
    rows.append(bytes(row))


def chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


with open(path, "wb") as handle:
    handle.write(b"\x89PNG\r\n\x1a\n")
    handle.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
    handle.write(chunk(b"IDAT", zlib.compress(b"".join(rows))))
    handle.write(chunk(b"IEND", b""))
PY
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# expect <exit-code> <needle> <case-name> -- command...
expect() {
  local want="$1" needle="$2" name="$3"
  shift 4
  local out status=0
  out="$("$@" 2>&1)" || status=$?
  if [[ "$status" != "$want" ]]; then
    printf '%s\n' "$out" >&2
    fail "$name: exit $status, expected $want"
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    printf '%s\n' "$out" >&2
    fail "$name: output lacks '$needle'"
  fi
  echo "PASS: $name"
}

new_case() {
  local dir="$TMP_DIR/$1"
  mkdir -p "$dir/baseline/masks" "$dir/current"
  png "$dir/baseline/recipes-list.png" 40 80 "240,240,240"
  png "$dir/baseline/shopping-az.png" 40 80 "255,255,255" "5,5,10,10,0,128,0"
  cp "$dir/baseline/recipes-list.png" "$dir/current/recipes-list.png"
  cp "$dir/baseline/shopping-az.png" "$dir/current/shopping-az.png"
  printf '%s\n' "$dir"
}

compare() {
  bash "$SCRIPT" --compare-dirs "$1/baseline" "$1/current"
}

dir="$(new_case identical)"
expect 0 "VERIFIED" "identical screenshots pass" -- compare "$dir"

dir="$(new_case one-pixel)"
png "$dir/current/shopping-az.png" 40 80 "255,255,255" "5,5,10,10,0,128,1"
expect 1 "FAILED" "one changed channel fails with zero tolerance" -- \
  env IPAD_VERIFY_CHANNEL_TOLERANCE=0 bash "$SCRIPT" --compare-dirs "$dir/baseline" "$dir/current"
[[ -f "$dir/current/diff/shopping-az.diff.png" ]] || fail "diff image not written"
echo "PASS: diff image written"
expect 0 "VERIFIED" "default channel tolerance ignores a ±1 glass dither" -- compare "$dir"

dir="$(new_case three-levels)"
png "$dir/current/shopping-az.png" 40 80 "255,255,255" "5,5,10,10,0,131,0"
expect 1 "FAILED" "a 3-level channel change fails with the default tolerance" -- compare "$dir"

dir="$(new_case masked)"
png "$dir/current/recipes-list.png" 40 80 "240,240,240" "0,60,40,10,10,10,10"
png "$dir/baseline/masks/recipes-list.mask.png" 40 80 "0,0,0" "0,58,40,14,255,255,255"
expect 0 "VERIFIED" "change inside the unstable mask passes" -- compare "$dir"

dir="$(new_case outside-mask)"
png "$dir/current/recipes-list.png" 40 80 "240,240,240" "0,0,1,1,0,0,0"
png "$dir/baseline/masks/recipes-list.mask.png" 40 80 "0,0,0" "0,58,40,14,255,255,255"
expect 1 "FAILED" "change outside the unstable mask fails" -- compare "$dir"

dir="$(new_case missing)"
rm "$dir/current/shopping-az.png"
expect 1 "current screenshot missing" "missing current screenshot fails" -- compare "$dir"

dir="$(new_case resized)"
png "$dir/current/recipes-list.png" 80 40 "240,240,240"
expect 1 "size-mismatch" "rotated / resized screenshot fails" -- compare "$dir"

dir="$TMP_DIR/empty"
mkdir -p "$dir/baseline" "$dir/current"
expect 1 "no baseline screenshots" "empty baseline fails closed" -- compare "$dir"

dir="$(new_case tolerance)"
png "$dir/current/recipes-list.png" 40 80 "240,240,240" "0,0,1,1,0,0,0"
expect 0 "VERIFIED" "IPAD_VERIFY_MAX_DIFF_PIXELS=1 allows one pixel" -- \
  env IPAD_VERIFY_MAX_DIFF_PIXELS=1 bash "$SCRIPT" --compare-dirs "$dir/baseline" "$dir/current"

expect 64 "Unknown argument" "unknown argument is rejected" -- bash "$SCRIPT" --bogus

# Baseline masks: an L-shaped unstable region (two strips touching at a corner)
# is filled to its 20x20 bounding box with IPAD_VERIFY_MASK_BOXES=1.
PIXELS_BIN="$REPO_ROOT/tmp/ipad-verify/.tools/ipad-verify-pixels-$(shasum -a 256 "$REPO_ROOT/scripts/ipad-verify-pixels.swift" | cut -c1-16)"
[[ -x "$PIXELS_BIN" ]] || fail "pixel tool not compiled at $PIXELS_BIN"
dir="$TMP_DIR/mask"
mkdir -p "$dir"
png "$dir/ref.png" 40 40 "255,255,255"
png "$dir/a.png" 40 40 "255,255,255" "10,10,20,1,0,0,0"
png "$dir/b.png" 40 40 "255,255,255" "10,10,1,20,0,0,0"
expect 0 "masked=39 " "mask without boxes keeps the L shape" -- \
  env IPAD_VERIFY_MASK_BOXES=0 "$PIXELS_BIN" mask "$dir/plain.png" 0 "$dir/ref.png" "$dir/a.png" "$dir/b.png"
expect 0 "masked=400 " "mask with boxes fills the bounding box" -- \
  env IPAD_VERIFY_MASK_BOXES=1 "$PIXELS_BIN" mask "$dir/boxed.png" 0 "$dir/ref.png" "$dir/a.png" "$dir/b.png"

echo "All verify-ipad-layout self-tests passed."
