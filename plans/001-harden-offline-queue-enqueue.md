# Plan 001: Harden offline queue enqueue against silent failures

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b72ee4b..HEAD -- RecipeScalerNative/Services/YjsSync/YjsSyncService.swift RecipeScalerNative/Services/YjsSync/OfflineWriteQueue.swift RecipeScalerNativeTests/`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `b72ee4b`, 2026-06-13
- **Issue**: (none)

## Why this matters

When the app is offline, local Yjs updates are enqueued in SQLite so they can be drained when connectivity returns. Today, `sendDebouncedUpdate` and `handleLocalShoppingUpdate` call `offlineQueue.enqueue(...)` with `try?`, so any disk error (locked DB, full disk, migration mismatch) silently drops the update. The UI shows "Queued", but the edit never makes it to the server. This plan makes enqueue failures explicit and recoverable.

## Current state

- `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` — orchestrates sync; contains the enqueue call sites.
- `RecipeScalerNative/Services/YjsSync/OfflineWriteQueue.swift` — thin actor wrapper around `YDocStore`.

Relevant excerpts today:

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1377-1391
private func sendDebouncedUpdate(recipeId: String, update: Data) async {
    guard let userId else { return }
    let docKey = docKeyFor(recipeId: recipeId)

    if canSendLiveSync() {
        writeSyncStates[recipeId] = .syncing
        await emitSyncRequest(recipeId: recipeId, update: update, docKey: docKey)
        await documentManager.persistSnapshot(docKey: docKey)
    } else {
        writeSyncStates[recipeId] = .queued
        try? await offlineQueue.enqueue(docKey: docKey, recipeId: recipeId, yjsUpdate: update)
        await documentManager.persistSnapshot(docKey: docKey)
    }
}
```

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1394-1411
private func handleLocalShoppingUpdate(update: Data) async {
    guard let userId else { return }
    let docKey = Self.shoppingDocKey(userId: userId)
    if socket?.status == .connected, isSocketAuthenticated {
        await emitSyncRequest(...)
    } else {
        try? await offlineQueue.enqueue(docKey: docKey, recipeId: ShoppingListConstants.offlineRecipeId, yjsUpdate: update)
        logger.info("Queued offline shopping update (\(update.count) bytes)")
    }
}
```

```swift
// RecipeScalerNative/Services/YjsSync/OfflineWriteQueue.swift:11-13
func enqueue(docKey: String, recipeId: String, yjsUpdate: Data) async throws {
    try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: yjsUpdate)
}
```

Repo conventions:
- Error handling uses `logger.error(...)` / `logger.warning(...)` from `OSLog`.
- `WriteSyncState` is an enum exposed via `@Published var writeSyncStates: [String: WriteSyncState]`.
- The existing state values are `.idle`, `.pendingLocal`, `.queued`, `.syncing`, `.synced`, `.error(String)`.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' build` | exit 0, no errors |
| Tests     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5' test` | all pass, including new tests |

## Scope

**In scope**:
- `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift`
- `RecipeScalerNative/Services/YjsSync/OfflineWriteQueue.swift`
- `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` (add tests)

**Out of scope**:
- Changes to `emitSyncRequest` or queue drain logic (handled in plans 002-004).
- UI error presentation sheets/alerts.
- Retry scheduling policy.

## Git workflow

- Branch: `advisor/001-harden-offline-queue-enqueue`
- Commit per step, message style: `fix(sync): propagate offline enqueue errors` / `test(sync): enqueue failure does not lose update`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Propagate enqueue errors in `sendDebouncedUpdate`

Change the offline branch of `sendDebouncedUpdate` to use `try await` and catch failures. On failure:
- Keep `writeSyncStates[recipeId]` in an error state (e.g., `.error("offline_queue_failed")`) or at least `.queued`.
- Do **not** call `persistSnapshot` if the update was not durably queued (it already lives in the in-memory Y.Doc; persisting is fine, but the log message "Queued offline update..." must not fire on failure).
- Log the error with `#if DEBUG` or at `logger.error` level.

Target shape:
```swift
} else {
    writeSyncStates[recipeId] = .queued
    do {
        try await offlineQueue.enqueue(docKey: docKey, recipeId: recipeId, yjsUpdate: update)
        await documentManager.persistSnapshot(docKey: docKey)
        logger.info("Queued offline update for \(recipeId) (\(update.count) bytes)")
    } catch {
        writeSyncStates[recipeId] = .error("offline_queue_failed")
        logger.error("Failed to enqueue offline update for \(recipeId): \(error.localizedDescription)")
    }
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 2: Propagate enqueue errors in `handleLocalShoppingUpdate`

Apply the same pattern to the shopping-list offline branch. Do not log "Queued offline shopping update" on failure.

**Verify**: `xcodebuild build` → exit 0.

### Step 3: Add regression tests

In `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`, add a test that simulates an enqueue failure and asserts the update is not marked as successfully queued.

Because `OfflineWriteQueue` is an actor backed by `YDocStore`, the simplest approach is to inject a failing store. Since `YjsSyncService` currently does not support dependency injection, create a minimal test that exercises `OfflineWriteQueue` directly:

```swift
final class OfflineWriteQueueEnqueueTests: XCTestCase {
    func testEnqueueFailureIsThrown() async {
        // Failing store: enqueueOfflineUpdate always throws.
        actor FailingYDocStore {
            func enqueueOfflineUpdate(docKey: String, recipeId: String, yjsUpdate: Data) throws {
                throw NSError(domain: "test", code: 1)
            }
        }
        // Alternatively, use a real DatabaseQueue with a read-only path / corrupted state
        // to force GRDB to throw, then assert the error propagates.
    }
}
```

A more practical test using real GRDB:
1. Create a `DatabaseQueue`.
2. Do **not** run `YrsDatabase.migrateForTests`, so the `offline_sync_queue` table does not exist.
3. Create `YDocStore(dbQueue: queue)` and `OfflineWriteQueue(store: store)`.
4. Call `offlineQueue.enqueue(...)` and assert it throws.
5. Call `offlineQueue.fetchAll()` and assert it returns empty.

**Verify**: `xcodebuild test` → new test passes.

### Step 4: Verify no remaining `try? await offlineQueue.enqueue`

Run:
```bash
grep -RIn "try? await offlineQueue.enqueue" RecipeScalerNative/
```
Expected: no matches.

**Verify**: grep returns empty.

## Test plan

- New test in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`:
  - `testEnqueueFailureThrowsAndLeavesQueueEmpty` — missing table forces GRDB to throw; error propagates.
- Existing tests in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` continue to pass.

## Done criteria

- [ ] `xcodebuild build` exits 0.
- [ ] `xcodebuild test` exits 0; new enqueue-failure test passes.
- [ ] No `try? await offlineQueue.enqueue` remains in `RecipeScalerNative/`.
- [ ] `plans/README.md` status row for plan 001 updated to DONE.

## STOP conditions

Stop and report if:
- The code at `YjsSyncService.swift:1377-1391` or `:1394-1411` does not match the excerpts.
- `WriteSyncState` enum does not contain `.queued` / `.error(String)`.
- `OfflineWriteQueue.enqueue` signature changed (no longer throws).

## Maintenance notes

- This plan does not add a retry policy. A future plan may add `attemptCount` increments and delayed retries in `OfflineWriteQueue`/`YDocStore`.
- Reviewers should check that the online branch (`canSendLiveSync()`) is unchanged and that failures still fall back to the offline branch correctly.
