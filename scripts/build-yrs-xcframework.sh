#!/usr/bin/env bash
#
# build-yrs-xcframework.sh
# Builds yrs (y-crdt) C FFI library as an XCFramework for iOS.
#
# Prerequisites:
#   - Rust toolchain: rustup install stable
#   - iOS targets: rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
#   - Xcode 16.0+ with command line tools
#
# Usage:
#   ./scripts/build-yrs-xcframework.sh [Y_CRDT_DIR] [OUTPUT_DIR]
#
# Arguments:
#   Y_CRDT_DIR  - Path to y-crdt checkout (default: /tmp/y-crdt)
#   OUTPUT_DIR  - Where to place YrsXCFramework.xcframework (default: ./Frameworks)
#
# Examples:
#   ./scripts/build-yrs-xcframework.sh
#   ./scripts/build-yrs-xcframework.sh ~/repos/y-crdt ./Frameworks
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

Y_CRDT_DIR="${1:-/tmp/y-crdt}"
OUTPUT_DIR="${2:-$REPO_ROOT/Frameworks}"

YFFI_CRATE="yffi"
LIB_NAME="libyrs.a"
FRAMEWORK_NAME="YrsXCFramework.xcframework"
HEADER_NAME="libyrs.h"
# Pinned y-crdt release — bump deliberately; rebuild XCFramework + commit VERSION.txt.
Y_CRDT_REF="v0.26.0"

# iOS targets
DEVICE_TARGET="aarch64-apple-ios"
SIM_ARM64_TARGET="aarch64-apple-ios-sim"
SIM_X86_TARGET="x86_64-apple-ios"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Check prerequisites ─────────────────────────────────────────────────────

info "Checking prerequisites..."

command -v rustup >/dev/null 2>&1 || error "rustup not found. Install from https://rustup.rs/"
command -v cargo >/dev/null 2>&1 || error "cargo not found."
command -v xcodebuild >/dev/null 2>&1 || error "xcodebuild not found. Install Xcode."
command -v lipo >/dev/null 2>&1 || error "lipo not found. Install Xcode command line tools."

for target in "$DEVICE_TARGET" "$SIM_ARM64_TARGET" "$SIM_X86_TARGET"; do
    if ! rustup target list --installed | grep -q "$target"; then
        error "Rust target '$target' not installed. Run: rustup target add $target"
    fi
done

info "Prerequisites OK."

# ─── Clone or update y-crdt ──────────────────────────────────────────────────

if [ -d "$Y_CRDT_DIR/.git" ]; then
    current_ref="$(git -C "$Y_CRDT_DIR" describe --tags --exact-match 2>/dev/null || git -C "$Y_CRDT_DIR" rev-parse HEAD)"
    if [ "$current_ref" != "$Y_CRDT_REF" ]; then
        warn "Existing checkout at $current_ref, but Y_CRDT_REF=$Y_CRDT_REF — re-cloning"
        rm -rf "$Y_CRDT_DIR"
    fi
fi

if [ ! -d "$Y_CRDT_DIR" ]; then
    info "Cloning y-crdt ($Y_CRDT_REF) to $Y_CRDT_DIR..."
    git clone --depth 1 --branch "$Y_CRDT_REF" https://github.com/y-crdt/y-crdt.git "$Y_CRDT_DIR"
else
    info "Using existing y-crdt at $Y_CRDT_DIR"
fi

Y_CRDT_COMMIT="$(git -C "$Y_CRDT_DIR" rev-parse HEAD)"
info "y-crdt pinned to $Y_CRDT_REF ($Y_CRDT_COMMIT)"

HEADER_SOURCE="$Y_CRDT_DIR/tests-ffi/include/$HEADER_NAME"
if [ ! -f "$HEADER_SOURCE" ]; then
    error "Header file not found at $HEADER_SOURCE. Ensure y-crdt checkout is valid."
fi

# ─── Build for each target ───────────────────────────────────────────────────

BUILD_DIR="$Y_CRDT_DIR/target"
HEADER_DIR="$BUILD_DIR/xcframework-headers"

mkdir -p "$HEADER_DIR"
cp "$HEADER_SOURCE" "$HEADER_DIR/"

# Create module.modulemap for Swift interop
cat > "$HEADER_DIR/module.modulemap" << 'MODULEMAP'
module YrsC {
    header "libyrs.h"
    export *
}
MODULEMAP

info "Building for $DEVICE_TARGET (iOS device)..."
cargo build -p "$YFFI_CRATE" --release --target "$DEVICE_TARGET" --target-dir "$BUILD_DIR" --manifest-path "$Y_CRDT_DIR/Cargo.toml"

info "Building for $SIM_ARM64_TARGET (iOS simulator - Apple Silicon)..."
cargo build -p "$YFFI_CRATE" --release --target "$SIM_ARM64_TARGET" --target-dir "$BUILD_DIR" --manifest-path "$Y_CRDT_DIR/Cargo.toml"

info "Building for $SIM_X86_TARGET (iOS simulator - Intel)..."
cargo build -p "$YFFI_CRATE" --release --target "$SIM_X86_TARGET" --target-dir "$BUILD_DIR" --manifest-path "$Y_CRDT_DIR/Cargo.toml"

# ─── Create universal simulator library ──────────────────────────────────────

SIM_UNIVERSAL_DIR="$BUILD_DIR/apple-ios-simulator/release"
mkdir -p "$SIM_UNIVERSAL_DIR"

info "Creating universal simulator library (arm64 + x86_64)..."
lipo -create \
    "$BUILD_DIR/$SIM_ARM64_TARGET/release/$LIB_NAME" \
    "$BUILD_DIR/$SIM_X86_TARGET/release/$LIB_NAME" \
    -output "$SIM_UNIVERSAL_DIR/$LIB_NAME"

# ─── Create XCFramework ──────────────────────────────────────────────────────

XCFRAMEWORK_PATH="$OUTPUT_DIR/$FRAMEWORK_NAME"

# Remove old framework if exists
rm -rf "$XCFRAMEWORK_PATH"
mkdir -p "$OUTPUT_DIR"

info "Creating XCFramework at $XCFRAMEWORK_PATH..."
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/$DEVICE_TARGET/release/$LIB_NAME" \
    -headers "$HEADER_DIR" \
    -library "$SIM_UNIVERSAL_DIR/$LIB_NAME" \
    -headers "$HEADER_DIR" \
    -output "$XCFRAMEWORK_PATH"

# ─── Verify ──────────────────────────────────────────────────────────────────

info "Verifying XCFramework..."

if [ -d "$XCFRAMEWORK_PATH" ]; then
    SLICES=$(find "$XCFRAMEWORK_PATH" -name "$LIB_NAME" -exec lipo -info {} \; 2>/dev/null || true)
    info "XCFramework created successfully!"
    echo ""
    echo "Library slices:"
    echo "$SLICES"
    echo ""

    YFFI_VERSION="$(grep -m1 '^version = ' "$Y_CRDT_DIR/yffi/Cargo.toml" | sed 's/^version = "\(.*\)"/\1/')"
    YRS_VERSION="$(grep -m1 '^version = ' "$Y_CRDT_DIR/yrs/Cargo.toml" 2>/dev/null | sed 's/^version = "\(.*\)"/\1/' || echo "unknown")"
    VERSION_FILE="$XCFRAMEWORK_PATH/VERSION.txt"
    cat > "$VERSION_FILE" <<EOF
tag: $Y_CRDT_REF
commit: $Y_CRDT_COMMIT
built-at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
yffi-version: $YFFI_VERSION
yrs-version: $YRS_VERSION

# Rust merge/diff helpers are linked into libyrs.a (verify: nm libyrs.a | rg merge_updates_v1)
# but are not exported through yffi C ABI (libyrs.h). Native Y.mergeUpdates parity requires a
# yffi shim — see review finding #6 (WKWebView merge on main thread).
EOF
    info "Wrote $VERSION_FILE"

    info "Output: $XCFRAMEWORK_PATH"
    echo ""
    info "Next steps:"
    echo "  1. Add $XCFRAMEWORK_PATH to Xcode project"
    echo "  2. Set 'Embed & Sign' in target settings"
    echo "  3. Import as: import YrsC"
    echo "  4. Commit Frameworks/YrsXCFramework.xcframework + VERSION.txt after rebuild"
else
    error "Failed to create XCFramework at $XCFRAMEWORK_PATH"
fi
