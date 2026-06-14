# Plan 003: Delete offline queue rows only after confirmed emission

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b72ee4b..HEAD -- RecipeScalerNative/Services/YjsSync/YjsSyncService.swift RecipeScalerNativeTests/`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 001, 002
- **Category**: bug
- **Planned at**: commit `b72ee4b`, 2026-06-13
- **Issue**: (none)

## Why this matters

`drainOfflineQueue` calls `emitSyncRequest(...)` and then immediately deletes every queued row for the document. But `emitSyncRequest` silently returns if the socket disconnects between the `canSendLiveSync()` check and the actual emission. A network blip can therefore wipe queued updates without sending them, causing silent data loss on reconnect.

## Current state

- `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` — contains `emitSyncRequest` and `drainOfflineQueue`.

Relevant excerpts today:

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1414-1444
private func emitSyncRequest(
    recipeId: String,
    update: Data,
    docKey: String,
    documentKind: String? = nil
) async {
    guard socket?.status == .connected, isSocketAuthenticated else { return }
    let lastSyncedAt = try? await store.loadSnapshot(docKey: docKey)?.lastSyncedAt
    var payload: [String: Any] = [
        "yjsUpdate": YjsPayloadBytes.array(from: update),
    ]
    let isShoppingList = documentKind == ShoppingListConstants.documentKind
    if recipeId != "collection", !isShoppingList {
        payload["recipeId"] = recipeId
    }
    if let documentKind {
        payload["documentKind"] = documentKind
    }
    if let lastSyncedAt {
        payload["lastSyncedAt"] = lastSyncedAt
    }
    socket?.emit("sync_request", payload)
    let target: String
    if documentKind == ShoppingListConstants.documentKind {
        target = "shoppingList"
    } else {
        target = recipeId == "collection" ? "collection" : recipeId
    }
    logger.info("Emitted sync_request for \(target) (\(update.count) bytes)")
}
```

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1509-1519
await emitSyncRequest(
    recipeId: recipeId,
    update: pushData,
    docKey: docKey,
    documentKind: documentKind
)
for entry in docEntries {
    if let id = entry.id {
        try? await offlineQueue.deleteEntry(id: id)
    }
}
```

Repo conventions:
- `emitSyncRequest` is `private` and `async`.
- Callers in `applyServerDocumentState` and `applyDescriptionSyncState` also call it but do not delete queue rows locally (they rely on `sync_confirmed`).

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` | exit 0 |
| Tests     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test` | all pass, including new tests |

## Scope

**In scope**:
- `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` (`emitSyncRequest`, `drainOfflineQueue`)
- `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` (add tests)

**Out of scope**:
- `sync_confirmed` cleanup logic (plan 004).
- Socket.IO reconnection logic.

## Git workflow

- Branch: `advisor/003-delete-queue-rows-after-confirmed-emission`
- Commit per step, message style: `fix(sync): only delete offline rows when sync_request actually emitted`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Make `emitSyncRequest` return a `Bool`

Change the signature to return `Bool` and return `true` only when the socket is connected and authenticated and the emit is attempted. Return `false` in the early-exit guard.

Target shape:
```swift
@discardableResult
private func emitSyncRequest(
    recipeId: String,
    update: Data,
    docKey: String,
    documentKind: String? = nil
) async -> Bool {
    guard socket?.status == .connected, isSocketAuthenticated else { return false }
    let lastSyncedAt = try? await store.loadSnapshot(docKey: docKey)?.lastSyncedAt
    // ... existing payload assembly ...
    socket?.emit("sync_request", payload)
    logger.info("Emitted sync_request for \(target) (\(update.count) bytes)")
    return true
}
```

Use `@discardableResult` so callers that do not need the result (e.g., `applyServerDocumentState` when pushing local state to an empty server) do not produce warnings.

**Verify**: `xcodebuild build` → exit 0.

### Step 2: Gate queue deletion on the returned Bool

In `drainOfflineQueue`, capture the result and only delete entries when it is `true`.

Target shape:
```swift
let emitted = await emitSyncRequest(
    recipeId: recipeId,
    update: pushData,
    docKey: docKey,
    documentKind: documentKind
)
if emitted {
    for entry in docEntries {
        if let id = entry.id {
            try? await offlineQueue.deleteEntry(id: id)
        }
    }
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 3: Add regression tests

Add a test in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` that:
1. Enqueues offline updates while the socket is disconnected.
2. Calls `drainOfflineQueue` (or the public path that triggers it) while the socket remains disconnected.
3. Asserts the queue still contains the updates.

Because `YjsSyncService` is a singleton and hard to inject, consider extracting a testable helper:

```swift
// Internal test helper (add to YjsSyncService.swift or a new file)
func drainOfflineQueueForTests() async {
    await drainOfflineQueue()
}
```

Alternatively, test the behavior indirectly by checking `writeSyncStates` and `offlineQueue.fetchAll()` after simulating reconnect failure.

If direct testing is blocked by singleton design, add a unit test for the helper function logic by extracting a small `OfflineQueueDrainer` type. That is larger scope; stop and report if you reach this point without a clean way to test.

**Verify**: `xcodebuild test` → new test passes.

### Step 4: Verify no unconditional deletion after emit

Run:
```bash
grep -n "offlineQueue.deleteEntry" RecipeScalerNative/Services/YjsSync/YjsSyncService.swift
```
Confirm deletion only happens inside the `if emitted { ... }` block.

**Verify**: grep shows the expected location.

## Test plan

- New test in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`:
  - `testDrainOfflineQueuePreservesRowsWhenSocketDisconnected`
- Existing offline tests continue to pass.

## Done criteria

- [ ] `xcodebuild build` exits 0.
- [ ] `xcodebuild test` exits 0; new test passes.
- [ ] `emitSyncRequest` returns `Bool` and returns `false` on early-exit.
- [ ] `drainOfflineQueue` deletes rows only when `emitSyncRequest` returns `true`.
- [ ] `plans/README.md` status row for plan 003 updated to DONE.

## STOP conditions

Stop and report if:
- `emitSyncRequest` signature or body does not match the excerpt.
- `drainOfflineQueue` does not have a `pushData` guard (`pushData.count > 2`) before emission.
- Adding `@discardableResult` causes unexpected compiler warnings elsewhere.

## Maintenance notes

- Plan 004 will build on this by tracking exactly which rows belong to each emitted request, so `sync_confirmed` can clean up precisely.
- Reviewers should verify that the `@discardableResult` annotation is appropriate for all existing callers.
