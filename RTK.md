# RTK - Rust Token Killer (Codex CLI)

**Usage**: Token-optimized CLI proxy for shell commands.

## Rule

Always prefix shell commands with `rtk`.

Examples:

```bash
rtk git status
rtk git diff
rtk find . -name "*.swift"
rtk grep "DocumentManager" RecipeScalerNative/
rtk read RecipeScalerNative/Config.swift

# Xcode — user-global filter in ~/Library/Application Support/rtk/filters.toml
# Do not pipe to `rtk grep` (ignores stdin); use `rtk xcodebuild` alone or `rtk pipe -f grep`.
rtk xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=<UDID>' build
rtk xcodebuild -scheme RecipeScalerNative \
  -destination 'platform=iOS Simulator,id=<UDID>' test
```

## Meta Commands

```bash
rtk gain            # Token savings analytics
rtk gain --history  # Recent command savings history
rtk proxy <cmd>     # Run raw command without filtering
```

## Verification

```bash
rtk --version
rtk gain
which rtk
```
