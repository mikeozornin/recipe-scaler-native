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
# Xcode (when building from CLI):
# xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16' build
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
