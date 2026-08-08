# Plan 008: Sync `Package.swift` with the real Xcode target graph

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b72ee4b..HEAD -- Package.swift RecipeScalerNative.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: migration
- **Planned at**: commit `b72ee4b`, 2026-06-13
- **Issue**: (none)

## Why this matters

`Package.swift` describes a single `RecipeScalerNative` target with only three dependencies, while the actual Xcode project has five targets and links `Agentation` (and historically `UniversalGlass`). This means `swift build` / `swift package resolve` do not represent the real build graph and will fail or drift silently. This plan brings `Package.swift` and `Package.resolved` in line with the Xcode project.

## Current state

- `Package.swift` (root) — declares `RecipeScalerNative` target with `SocketIO`, `KeychainAccess`, `GRDB`, and `swift-snapshot-testing` for tests.
- `RecipeScalerNative.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — actual resolved graph including `swift-agentation` and `universalglass`.
- `RecipeScalerNative/RecipeScalerNativeApp.swift:12` imports and uses `Agentation`.

Relevant excerpts today:

```swift
// Package.swift:18-32
dependencies: [
    .package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.1.0"),
    .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
]
```

```swift
// RecipeScalerNative/RecipeScalerNativeApp.swift:12
import Agentation
```

```json
// Package.resolved excerpt
{
  "identity" : "swift-agentation",
  "kind" : "remoteSourceControl",
  "location" : "https://github.com/ertembiyik/swift-agentation.git",
  "state" : {
    "revision" : "401adcb94d9e58a7de7e79cbc00586c4c741897d",
    "version" : "1.0.0"
  }
}
```

Repo conventions:
- The Xcode project is the primary build system; `Package.swift` is secondary but should be consistent.
- Transitive dependencies are resolved by SPM automatically.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Resolve   | `swift package resolve`  | exit 0, `Package.resolved` updated |
| Build SPM | `swift build`            | exit 0 for the targets Package.swift describes |
| Xcode     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' build` | exit 0 |
| Tests     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' test` | all pass |

## Scope

**In scope**:
- `Package.swift`
- `RecipeScalerNative.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

**Out of scope**:
- Converting the project to pure SPM or XcodeGen.
- Adding `RecipeScalerCore`, extensions, or Live Activity targets to `Package.swift` (optional; mention in maintenance notes).
- Upgrading dependency versions.

## Git workflow

- Branch: `advisor/008-sync-package-swift`
- Commit per step, message style: `build(deps): add Agentation to Package.swift` / `build(deps): remove unused UniversalGlass pin`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Add `Agentation` to `Package.swift`

Add the package dependency and link it to the `RecipeScalerNative` target:

```swift
dependencies: [
    .package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.1.0"),
    .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    .package(url: "https://github.com/ertembiyik/swift-agentation.git", from: "1.0.0"),
]
```

```swift
.target(
    name: "RecipeScalerNative",
    dependencies: [
        .product(name: "SocketIO", package: "socket.io-client-swift"),
        .product(name: "KeychainAccess", package: "KeychainAccess"),
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "Agentation", package: "swift-agentation"),
    ],
    // ... existing path/exclude/resources ...
)
```

**Verify**: `swift package resolve` → exit 0.

### Step 2: Remove stale `UniversalGlass` pin

Open `Package.resolved` and remove the `universalglass` pin entry (lines 77-83). Then run `swift package resolve` to regenerate the file.

**Verify**: `swift package resolve` → exit 0; `Package.resolved` no longer contains `universalglass`.

### Step 3: Verify `swift build` succeeds

Run:
```bash
swift build
```

Expected: exit 0. If `swift build` fails because `Package.swift` cannot represent the full project (e.g., resources, bridging headers, multiple targets), that is acceptable as long as the failure is clearly due to project structure, not missing dependencies. Document the failure in a STOP condition and report back.

**Verify**: `swift build` exits 0 or fails only for known structural reasons (not dependency resolution).

### Step 4: Verify Xcode build still works

Run:
```bash
xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' build
```

Expected: exit 0.

**Verify**: `xcodebuild build` → exit 0.

### Step 5: Run tests

Run:
```bash
xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' test
```

Expected: all pass.

**Verify**: `xcodebuild test` → all pass.

## Test plan

- No new unit tests needed.
- Verification is the build/test commands above.

## Done criteria

- [ ] `Package.swift` declares `Agentation` and links it to `RecipeScalerNative`.
- [ ] `Package.resolved` no longer contains `universalglass`.
- [ ] `swift package resolve` exits 0.
- [ ] `xcodebuild build` exits 0.
- [ ] `xcodebuild test` exits 0.
- [ ] `plans/README.md` status row for plan 008 updated to DONE.

## STOP conditions

Stop and report if:
- `Agentation` cannot be resolved or `swift package resolve` fails.
- Removing `UniversalGlass` from `Package.resolved` causes the Xcode project to fail resolution (some target still links it).
- `swift build` fails for reasons unrelated to multi-target/bridging-header limitations.

## Maintenance notes

- A future plan may expand `Package.swift` to include `RecipeScalerCore`, `ShareExtension`, `ActionExtension`, and `TimerLiveActivityExtension` targets so the entire project can build with SPM. That is out of scope here.
- Reviewers should check that the Xcode project's `Package.resolved` stays in sync with `Package.swift` after this change.
