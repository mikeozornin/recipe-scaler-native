# Plan 004: Make `sync_confirmed` delete only the rows it acknowledges

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b72ee4b..HEAD -- RecipeScalerNative/Services/YjsSync/YjsSyncService.swift RecipeScalerNative/Services/YjsSync/OfflineWriteQueue.swift RecipeScalerNative/Services/Storage/YDocStore.swift RecipeScalerNativeTests/`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S/M
- **Risk**: MED
- **Depends on**: 003
- **Category**: bug
- **Planned at**: commit `b72ee4b`, 2026-06-13
- **Issue**: (none)

## Why this matters

When the server sends `sync_confirmed`, `handleSyncConfirmed` deletes **every** offline queue row matching the recipe ID. If the user made additional offline edits after the outbound `sync_request` was assembled but before the confirmation arrived, those newer rows are also deleted and never synced. This plan tracks which queue rows were included in each request and deletes only those rows on confirmation.

## Current state

- `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` — `handleSyncConfirmed` and `drainOfflineQueue`.
- `RecipeScalerNative/Services/YjsSync/OfflineWriteQueue.swift` — queue wrapper.
- `RecipeScalerNative/Services/Storage/YDocStore.swift` — GRDB queue CRUD.

Relevant excerpts today:

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1471-1478
private func handleSyncConfirmed(recipeId: String, lastSyncedAt: String?) async {
    // ... mark synced ...

    guard recipeId != "collection", recipeId != ShoppingListConstants.offlineRecipeId else { return }
    if let queue = try? await offlineQueue.fetchAll() {
        for entry in queue where entry.recipeId == recipeId {
            if let id = entry.id {
                try? await offlineQueue.deleteEntry(id: id)
            }
        }
    }
}
```

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1509-1519
await emitSyncRequest(...)
for entry in docEntries {
    if let id = entry.id {
        try? await offlineQueue.deleteEntry(id: id)
    }
}
```

After plan 003, the deletion in `drainOfflineQueue` is gated on `emitSyncRequest` returning `true`. This plan adds tracking of which entry IDs were included in the emitted request.

Repo conventions:
- `OfflineSyncEntry` has an `id: Int64?` primary key.
- `YjsSyncService` is `@MainActor`; mutable request-tracking state can live on the actor.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` | exit 0 |
| Tests     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test` | all pass, including new tests |

## Scope

**In scope**:
- `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift`
- `RecipeScalerNative/Services/YjsSync/OfflineWriteQueue.swift` (if helper needed)
- `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` (add tests)

**Out of scope**:
- Changing the server protocol.
- Adding persistent request IDs to `OfflineSyncEntry` schema.

## Git workflow

- Branch: `advisor/004-sync-confirmed-precise-queue-cleanup`
- Commit per step, message style: `fix(sync): track emitted queue row IDs and clean only those on sync_confirmed`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Add in-flight request tracking state

Add a private actor-isolated property to `YjsSyncService`:

```swift
/// recipeId → set of offline queue entry IDs included in the currently in-flight sync_request.
private var pendingSyncRequestEntryIds: [String: Set<Int64>] = [:]
```

**Verify**: `xcodebuild build` → exit 0.

### Step 2: Record entry IDs before emission in `drainOfflineQueue`

When `emitSyncRequest` returns `true`, store the entry IDs under the recipe ID. When it returns `false`, do not store them (and do not delete the rows — plan 003 already handles that).

Target shape inside `drainOfflineQueue`:
```swift
let emitted = await emitSyncRequest(...)
if emitted {
    let ids = Set(docEntries.compactMap(\.id))
    pendingSyncRequestEntryIds[recipeId, default: []].formUnion(ids)
    for entry in docEntries {
        if let id = entry.id {
            try? await offlineQueue.deleteEntry(id: id)
        }
    }
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 3: Make `handleSyncConfirmed` delete only tracked IDs

Change `handleSyncConfirmed` to delete only the intersection of the tracked IDs and the current queue rows for that recipe. Clear the tracked set after processing.

Target shape:
```swift
guard recipeId != "collection", recipeId != ShoppingListConstants.offlineRecipeId else { return }
let pendingIds = pendingSyncRequestEntryIds.removeValue(forKey: recipeId) ?? []
if pendingIds.isEmpty {
    // Fallback for backward compatibility: if no tracking data, do nothing.
    // The rows were already deleted by drainOfflineQueue on successful emit.
    return
}
if let queue = try? await offlineQueue.fetchAll() {
    for entry in queue where entry.recipeId == recipeId,
                            let id = entry.id,
                            pendingIds.contains(id) {
        try? await offlineQueue.deleteEntry(id: id)
    }
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 4: Clear tracking on disconnect / user change

In `stop()` and `setUserId(nil)` paths, clear `pendingSyncRequestEntryIds` so stale tracking does not leak across sessions.

Find `func stop()` or `func setUserId(_ userId: String?)` and add:
```swift
pendingSyncRequestEntryIds.removeAll()
```

**Verify**: `xcodebuild build` → exit 0.

### Step 5: Add regression tests

Add a test in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`:
1. Enqueue two updates for a recipe offline.
2. Simulate drain + successful emit (track the entry IDs).
3. Enqueue a third update before `sync_confirmed` arrives.
4. Call `handleSyncConfirmed`.
5. Assert the queue still contains the third update but not the first two.

If `handleSyncConfirmed` is private, expose it for tests via a package-visible helper or extract the cleanup into a separate internal method.

**Verify**: `xcodebuild test` → new test passes.

## Test plan

- New test in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`:
  - `testSyncConfirmedDeletesOnlyRowsFromCurrentRequest`
- Existing offline/merge tests continue to pass.

## Done criteria

- [ ] `xcodebuild build` exits 0.
- [ ] `xcodebuild test` exits 0; new test passes.
- [ ] `handleSyncConfirmed` no longer deletes all rows for a recipe ID indiscriminately.
- [ ] `pendingSyncRequestEntryIds` is cleared on session teardown / user change.
- [ ] `plans/README.md` status row for plan 004 updated to DONE.

## STOP conditions

Stop and report if:
- `OfflineSyncEntry.id` is not `Int64?`.
- `emitSyncRequest` in plan 003 was not changed to return `Bool`.
- `handleSyncConfirmed` body does not match the excerpt.

## Maintenance notes

- This in-memory tracking is sufficient because `sync_confirmed` arrives in the same app session as the emitted request. If the app is killed between emit and confirmation, the offline rows were already deleted by `drainOfflineQueue` (plan 003), so no leak occurs.
- If a future plan persists request IDs in the queue table, this in-memory map can be removed.
