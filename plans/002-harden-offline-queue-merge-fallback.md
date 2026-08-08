# Plan 002: Harden offline queue merge fallback

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b72ee4b..HEAD -- RecipeScalerNative/Services/YjsSync/YjsSyncService.swift RecipeScalerNativeTests/`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 001
- **Category**: bug
- **Planned at**: commit `b72ee4b`, 2026-06-13
- **Issue**: (none)

## Why this matters

When the offline queue is drained, multiple queued Yjs updates for a recipe are merged into a single `sync_request`. If the native merge helper fails, the current code falls back to sending only the last queued update (`parts.last` for recipes, `queueEntries.last?.yjsUpdate` for collection/shopping). Earlier edits in the same offline window are silently dropped. This plan removes the unsafe fallback so the queue entries stay put and are retried later.

## Current state

- `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` — contains `resolveYjsPushPayload` and `resolveNonRecipePushPayload`.

Relevant excerpts today:

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1543-1576
private func resolveYjsPushPayload(
    recipeId: String,
    docKey: String,
    queueEntries: [OfflineSyncEntry]
) async -> Data? {
    let parts = queueEntries.map(\.yjsUpdate).filter { $0.count > 2 }
    let wireBootstrap = try? await store.loadYjsWireSnapshot(docKey: docKey)?.state
    let yrsBootstrap = try? await store.loadSnapshot(docKey: docKey)?.state
    let bootstrap = wireBootstrap ?? yrsBootstrap

    if !parts.isEmpty, let bootstrap {
        if let full = try? await YjsMergeHelper.shared.encodeFullState(
            bootstrap: bootstrap,
            updates: parts
        ), full.count > 2 {
            return full
        }
        if parts.count == 1 { return parts[0] }
        if let merged = try? await YjsMergeHelper.shared.mergeUpdates(parts) { return merged }
        return parts.last   // <-- unsafe fallback
    }

    if let wire = wireBootstrap, wire.count > 2, isLocalAheadOfServer(recipeId: recipeId) {
        return wire
    }

    if isLocalAheadOfServer(recipeId: recipeId),
       let bootstrap,
       let full = try? await YjsMergeHelper.shared.encodeFullState(bootstrap: bootstrap, updates: []),
       full.count > 2 {
        return full
    }
    return nil
}
```

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1578-1590
private func resolveNonRecipePushPayload(
    docKey: String,
    queueEntries: [OfflineSyncEntry]
) async -> Data? {
    if queueEntries.count == 1 {
        return queueEntries[0].yjsUpdate
    }
    if let doc = await documentManager.getDoc(key: docKey),
       let snapshot = await doc.encodeStateAsUpdate() {
        return snapshot
    }
    return queueEntries.last?.yjsUpdate   // <-- unsafe fallback
}
```

Repo conventions:
- Returning `nil` from these helpers is already handled by `drainOfflineQueue`: it `continue`s the loop and leaves queue rows intact.
- `YjsMergeHelper` is a `@MainActor` singleton; do not change its API in this plan.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' build` | exit 0 |
| Tests     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' test` | all pass, including new tests |

## Scope

**In scope**:
- `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` (`resolveYjsPushPayload`, `resolveNonRecipePushPayload`)
- `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` (add tests)

**Out of scope**:
- `YjsMergeHelper` internals.
- General queue drain cleanup (plan 003).
- Retry/backoff policy.

## Git workflow

- Branch: `advisor/002-harden-offline-queue-merge-fallback`
- Commit per step, message style: `fix(sync): do not fall back to last queued update on merge failure`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Remove `parts.last` fallback in `resolveYjsPushPayload`

In the `if !parts.isEmpty, let bootstrap` branch, after the `mergeUpdates` attempt fails, return `nil` instead of `parts.last`.

Target shape:
```swift
if !parts.isEmpty, let bootstrap {
    if let full = try? await YjsMergeHelper.shared.encodeFullState(
        bootstrap: bootstrap,
        updates: parts
    ), full.count > 2 {
        return full
    }
    if parts.count == 1 { return parts[0] }
    if let merged = try? await YjsMergeHelper.shared.mergeUpdates(parts) { return merged }
    return nil
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 2: Remove `queueEntries.last` fallback in `resolveNonRecipePushPayload`

Change the final `return queueEntries.last?.yjsUpdate` to `return nil`.

Target shape:
```swift
private func resolveNonRecipePushPayload(
    docKey: String,
    queueEntries: [OfflineSyncEntry]
) async -> Data? {
    if queueEntries.count == 1 {
        return queueEntries[0].yjsUpdate
    }
    if let doc = await documentManager.getDoc(key: docKey),
       let snapshot = await doc.encodeStateAsUpdate() {
        return snapshot
    }
    return nil
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 3: Add regression tests

Add tests in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` that verify the fallback returns `nil` and leaves the queue intact.

Because `resolveYjsPushPayload` and `resolveNonRecipePushPayload` are private, expose them for testing via `@testable import RecipeScalerNative` (they are already visible to tests because `@testable` exposes `internal` members).

Test cases:
1. `testResolveYjsPushPayloadReturnsNilWhenMergeFails` — create multiple fake queue entries, inject a failing `YjsMergeHelper` (or use malformed data), call `resolveYjsPushPayload`, assert `nil`. Verify `offlineQueue.fetchAll()` still contains all entries.
2. `testResolveNonRecipePushPayloadReturnsNilWhenDocUnavailable` — create multiple non-recipe queue entries with no in-memory doc, assert `nil`, assert queue intact.

If testing private helpers directly is awkward, test through `YjsSyncService` by mocking its dependencies. However, because `YjsSyncService` is a singleton without injection, the simpler path is:
- Create a small helper test class that mirrors the private function logic, or
- Use `Runtime` introspection only as a last resort.

Recommended approach: add package-visible (`internal`) helper methods or extract the resolution logic into a separate `OfflineQueuePayloadResolver` struct that can be unit-tested. If you choose extraction, keep it minimal and inside the same file to limit blast radius.

**Verify**: `xcodebuild test` → new tests pass.

### Step 4: Verify no unsafe `.last` fallbacks remain

Run:
```bash
grep -n "return parts.last" RecipeScalerNative/Services/YjsSync/YjsSyncService.swift
grep -n "return queueEntries.last" RecipeScalerNative/Services/YjsSync/YjsSyncService.swift
```
Expected: no matches.

**Verify**: both greps return empty.

## Test plan

- New tests in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`:
  - `testResolveYjsPushPayloadReturnsNilOnMergeFailure`
  - `testResolveNonRecipePushPayloadReturnsNilWithoutDoc`
- Existing `YjsMergeHelperTests` must still pass.

## Done criteria

- [ ] `xcodebuild build` exits 0.
- [ ] `xcodebuild test` exits 0; new fallback tests pass.
- [ ] No `parts.last` or `queueEntries.last` fallback remains in the two payload resolvers.
- [ ] `plans/README.md` status row for plan 002 updated to DONE.

## STOP conditions

Stop and report if:
- The resolver functions do not match the excerpts.
- `drainOfflineQueue` does not already skip deletion when `pushData` is `nil`.
- Removing the fallback causes a compiler error because the return type changed.

## Maintenance notes

- If a future plan adds a native `YrsDocument.mergeUpdates` path, the fallback to `nil` remains correct: the queue stays until the merge succeeds.
- Reviewers should confirm that the single-part fast paths (`parts.count == 1`, `queueEntries.count == 1`) are preserved.
