# Plan 005: Preserve local snapshot on Yjs apply failure

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b72ee4b..HEAD -- RecipeScalerNative/Services/YjsSync/DocumentManager.swift RecipeScalerNativeTests/`
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

If a single Yjs update cannot be applied (corrupt wire bytes, schema mismatch, transient FFI error), `DocumentManager` currently deletes the entire SQLite snapshot and evicts the in-memory document. That discards all unsynced local edits instead of preserving them for retry or diagnostics. This plan stops the destructive cleanup on apply failure.

## Current state

- `RecipeScalerNative/Services/YjsSync/DocumentManager.swift` — `applyUpdateToDoc` and `applyDescriptionEditorUpdate`.

Relevant excerpts today:

```swift
// RecipeScalerNative/Services/YjsSync/DocumentManager.swift:106-125
private func applyUpdateToDoc(
    doc: YrsDocument,
    key: String,
    data: Data,
    lastSyncedAt: String?
) async throws {
    do {
        try await doc.applyUpdate(data)
    } catch {
        Self.logger.warning("applyUpdate failed for \(key), deleting corrupted snapshot")
        docs.removeValue(forKey: key)
        observerTokens.removeValue(forKey: key)
        try? await store.deleteSnapshot(docKey: key)
        throw error
    }

    if let state = await doc.encodeStateAsUpdate() {
        try? await store.saveSnapshot(docKey: key, state: state, lastSyncedAt: lastSyncedAt)
    }
}
```

```swift
// RecipeScalerNative/Services/YjsSync/DocumentManager.swift:952-959
func applyDescriptionEditorUpdate(...) async throws {
    // ...
    do {
        try await doc.applyUpdate(data)
    } catch {
        Self.logger.warning("applyDescriptionEditorUpdate failed for \(key), deleting corrupted snapshot")
        docs.removeValueValue(forKey: key)
        observerTokens.removeValue(forKey: key)
        try? await store.deleteSnapshot(docKey: key)
        throw error
    }
}
```

Repo conventions:
- `docs` and `observerTokens` are in-memory dictionaries keyed by `docKey`.
- `store.deleteSnapshot` removes the durable SQLite row.
- Errors are logged with `Self.logger.warning(...)`.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` | exit 0 |
| Tests     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test` | all pass, including new tests |

## Scope

**In scope**:
- `RecipeScalerNative/Services/YjsSync/DocumentManager.swift`
- `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` (add tests)

**Out of scope**:
- Changing how callers surface apply errors to the UI.
- Adding automatic retry logic.

## Git workflow

- Branch: `advisor/005-preserve-snapshot-on-apply-failure`
- Commit per step, message style: `fix(sync): preserve snapshot on Yjs apply failure`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Remove destructive cleanup from `applyUpdateToDoc`

Change the catch block to log and re-throw without deleting the snapshot or evicting the doc.

Target shape:
```swift
private func applyUpdateToDoc(
    doc: YrsDocument,
    key: String,
    data: Data,
    lastSyncedAt: String?
) async throws {
    do {
        try await doc.applyUpdate(data)
    } catch {
        Self.logger.warning("applyUpdate failed for \(key), preserving snapshot: \(error.localizedDescription)")
        throw error
    }

    if let state = await doc.encodeStateAsUpdate() {
        try? await store.saveSnapshot(docKey: key, state: state, lastSyncedAt: lastSyncedAt)
    }
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 2: Remove destructive cleanup from `applyDescriptionEditorUpdate`

Apply the same change. Note: there may be a typo `removeValueValue` in the current code; correct it to `removeValue` only if you are removing those lines. Since we are removing the lines entirely, the typo is gone.

Target shape:
```swift
do {
    try await doc.applyUpdate(data)
} catch {
    Self.logger.warning("applyDescriptionEditorUpdate failed for \(key), preserving snapshot: \(error.localizedDescription)")
    throw error
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 3: Add regression tests

Add a test in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`:
1. Create a recipe and persist its snapshot.
2. Call `applyUpdate(key:data:lastSyncedAt:)` with invalid/garbage `Data`.
3. Assert the call throws.
4. Load the snapshot from `YDocStore` and assert it still exists and equals the pre-update state.
5. Assert the doc remains in `DocumentManager.docs` (if accessible via `@testable`).

**Verify**: `xcodebuild test` → new test passes.

### Step 4: Verify no snapshot deletion on apply failure

Run:
```bash
grep -n "deleteSnapshot" RecipeScalerNative/Services/YjsSync/DocumentManager.swift
```
Expected: only legitimate deletion paths remain (e.g., `evictDoc` or account logout). The apply-failure catch blocks should no longer call `deleteSnapshot`.

**Verify**: grep output does not show deletion inside `applyUpdateToDoc` or `applyDescriptionEditorUpdate` catch blocks.

## Test plan

- New test in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`:
  - `testApplyUpdateFailurePreservesSnapshot`
- Existing `YrsServerMergeTests` continue to pass.

## Done criteria

- [ ] `xcodebuild build` exits 0.
- [ ] `xcodebuild test` exits 0; new test passes.
- [ ] `applyUpdateToDoc` and `applyDescriptionEditorUpdate` no longer delete snapshots or evict docs on apply error.
- [ ] `plans/README.md` status row for plan 005 updated to DONE.

## STOP conditions

Stop and report if:
- The catch blocks do not match the excerpts.
- Removing the snapshot deletion causes callers to crash because they expected the doc to be evicted.
- `DocumentManager.docs` is not accessible for test assertions.

## Maintenance notes

- Callers (e.g., `YjsSyncService.applyServerDocumentState`) already catch `DocumentManager.applyUpdate` errors and handle them by requesting a document reload. Preserving the snapshot lets that reload merge against the latest local state instead of starting from empty.
- Reviewers should confirm that legitimate snapshot deletion paths (user switch, tombstone) are unchanged.
