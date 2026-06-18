# Plan 005 (v2): Preserve local snapshot on Yjs apply failure

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `rg -n "deleteSnapshot" RecipeScalerNative/Services/YjsSync/DocumentManager.swift`
> If `deleteSnapshot` is no longer present inside `applyUpdateToDoc` (lines ~114-140) or `applyDescriptionEditorUpdate` (lines ~1306-1351), treat it as a STOP condition — the plan has already been applied.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: 2026-06-13 (original), rewritten 2026-06-18 (v2)
- **Original finding**: review-kilo-glm-5.2-recipe-scaler-native.md #16
- **Issue**: (none)

## Why this matters

If a single Yjs update cannot be applied (corrupt wire bytes, schema mismatch, transient FFI error), `DocumentManager` currently **deletes the entire SQLite snapshot** and evicts the in-memory document. That discards all unsynced local edits instead of preserving them for retry or diagnostics. One malformed **remote** `recipe_updated` (or transient yrs error) permanently destroys the offline-first local edits of that recipe.

The fix is to evict only in-memory state (doc, observers, derived caches) but leave the durable SQLite snapshot intact. The next `getOrCreateDoc` call rebuilds the in-memory doc from the preserved snapshot, restoring the unsynced local edits.

## Current state

- `RecipeScalerNative/Services/YjsSync/DocumentManager.swift` — `applyUpdateToDoc` (lines 114-140) and `applyDescriptionEditorUpdate` (lines 1306-1351).

Relevant excerpts today:

```swift
// RecipeScalerNative/Services/YjsSync/DocumentManager.swift:114-140
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
        htmlCache.removeValue(forKey: key)
        plainTextCache.removeValue(forKey: key)
        try? await store.deleteSnapshot(docKey: key)
        throw error
    }

    // State vector changed: any cached HTML is now stale. Drop it so the
    // next read recomputes (and re-caches with the new vector).
    htmlCache.removeValue(forKey: key)
    plainTextCache.removeValue(forKey: key)

    if let state = await doc.encodeStateAsUpdate() {
        try? await store.saveSnapshot(docKey: key, state: state, lastSyncedAt: lastSyncedAt)
    }
}
```

```swift
// RecipeScalerNative/Services/YjsSync/DocumentManager.swift:1306-1351
func applyDescriptionEditorUpdate(
    recipeId: String,
    update: Data,
    forwardToSync: Bool = true
) async throws {
    // ...
    do {
        try await doc.applyLocalUpdate(update)
    } catch {
        Self.logger.warning("applyDescriptionEditorUpdate failed for \(key), deleting corrupted snapshot")
        docs.removeValue(forKey: key)
        observerTokens.removeValue(forKey: key)
        htmlCache.removeValue(forKey: key)
        plainTextCache.removeValue(forKey: key)
        try? await store.deleteSnapshot(docKey: key)
        throw error
    }
    // ...
}
```

Repo conventions:
- `docs` and `observerTokens` are in-memory dictionaries keyed by `docKey`.
- `htmlCache` / `plainTextCache` are in-memory derived caches keyed by `docKey`, invalidated on state-vector change.
- `store.deleteSnapshot` removes the durable SQLite row.
- `store.saveSnapshot` writes the durable SQLite row.
- Errors are logged with `Self.logger.warning(...)`.
- `getOrCreateDoc` rebuilds an in-memory doc from the SQLite snapshot via `YrsDocument(state:)` when the snapshot is present, or creates a fresh empty doc otherwise.
- `YrsDocument.applyUpdate` / `applyLocalUpdate` route through `ytransaction_apply`, which is atomic for malformed input (the doc is not mutated on a bad update). Transient FFI failures (e.g. allocation failures) are the residual risk this plan guards against by also evicting the in-memory doc.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` | exit 0 |
| Tests     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -only-testing:RecipeScalerNativeTests/PreserveSnapshotOnApplyFailureTests` | new 2 tests pass |
| Regression | `xcodebuild ... test -only-testing:RecipeScalerNativeTests/YrsServerMergeTests` | no regressions |
| Grep audit | `rg -n "deleteSnapshot" RecipeScalerNative/Services/YjsSync/DocumentManager.swift` | only legitimate sites remain (`getOrCreateDoc` corrupted-snapshot path; `replaceDocument`/`evictDoc` are not error paths) |

## Scope

**In scope**:
- `RecipeScalerNative/Services/YjsSync/DocumentManager.swift` (two catch blocks).
- `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` (add `PreserveSnapshotOnApplyFailureTests`).

**Out of scope**:
- Changing how callers surface apply errors to the UI (`YjsSyncService` already calls `requestDocumentReload(recipeId:)` on apply failure).
- Adding automatic retry logic for yrs FFI.
- Touching `getOrCreateDoc` corrupted-snapshot path (lines 80-84): there `deleteSnapshot` is correct because the snapshot is provably damaged and unrecoverable.
- Touching `replaceDocument`, `evictDoc`, `evictAll`: these are normal lifecycle operations, not error paths.

## Git workflow

- Branch: `advisor/005-preserve-snapshot-on-apply-failure`
- Commit per step, message style: `fix(sync): preserve snapshot on Yjs apply failure`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Remove destructive cleanup from `applyUpdateToDoc`

Change the catch block to log + evict in-memory state + caches but NOT delete the SQLite snapshot.

Target shape:
```swift
do {
    try await doc.applyUpdate(data)
} catch {
    // yrs applyUpdate is atomic for malformed input, but transient FFI errors
    // could leave the in-memory doc in an unpredictable state. Evict it so the
    // next getOrCreateDoc rebuilds from the durable SQLite snapshot, but DO NOT
    // delete the snapshot itself — it may contain unsynced local edits that we
    // cannot reconstruct. See plans/005-preserve-snapshot-on-apply-failure.md
    // and review finding #16.
    Self.logger.warning("applyUpdate failed for \(key), evicting in-memory doc but preserving snapshot: \(error)")
    docs.removeValue(forKey: key)
    observerTokens.removeValue(forKey: key)
    htmlCache.removeValue(forKey: key)
    plainTextCache.removeValue(forKey: key)
    throw error
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 2: Remove destructive cleanup from `applyDescriptionEditorUpdate`

Same change. Note: this path uses `doc.applyLocalUpdate(update)` (not `applyUpdate`); preserve that call.

Target shape:
```swift
do {
    try await doc.applyLocalUpdate(update)
} catch {
    // Same reasoning as applyUpdateToDoc: evict in-memory state, preserve
    // SQLite snapshot. The description editor forwards incremental yjs wire
    // bytes, so a transient applyLocalUpdate failure must not destroy the
    // recipe snapshot. See plans/005-preserve-snapshot-on-apply-failure.md.
    Self.logger.warning("applyDescriptionEditorUpdate failed for \(key), evicting in-memory doc but preserving snapshot: \(error)")
    docs.removeValue(forKey: key)
    observerTokens.removeValue(forKey: key)
    htmlCache.removeValue(forKey: key)
    plainTextCache.removeValue(forKey: key)
    throw error
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 3: Add regression tests

Add a new `PreserveSnapshotOnApplyFailureTests` `XCTestCase` to `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` covering:

1. `testApplyUpdateGarbageDataPreservesSnapshot`:
   - Create a v3 recipe and persist its snapshot via a local edit.
   - Call `applyUpdate(key:data:)` with garbage bytes — must throw.
   - Assert SQLite snapshot still exists and is byte-identical to the pre-update state.
   - Assert `readRecipeData` after recovery still shows the local edit (proving snapshot-based recovery).
2. `testApplyDescriptionEditorUpdateGarbageDataPreservesSnapshot`:
   - Create a v3 recipe.
   - Call `applyDescriptionEditorUpdate(recipeId:update:)` with garbage bytes — must throw.
   - Assert SQLite snapshot still exists and is byte-identical to the pre-update state.

**Verify**: `xcodebuild test -only-testing:RecipeScalerNativeTests/PreserveSnapshotOnApplyFailureTests` → both tests pass.

### Step 4: Verify no snapshot deletion on apply failure

Run:
```bash
rg -n "deleteSnapshot" RecipeScalerNative/Services/YjsSync/DocumentManager.swift
```

Expected: `deleteSnapshot` appears only at the `getOrCreateDoc` corrupted-snapshot recovery path (lines ~80-84). It must NOT appear inside `applyUpdateToDoc` or `applyDescriptionEditorUpdate` catch blocks.

**Verify**: grep output matches the expectation.

## Test plan

- New tests in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`:
  - `testApplyUpdateGarbageDataPreservesSnapshot`
  - `testApplyDescriptionEditorUpdateGarbageDataPreservesSnapshot`
- Existing `YrsServerMergeTests` continue to pass.

## Done criteria

- [ ] `xcodebuild build` exits 0.
- [ ] `xcodebuild test` exits 0; 2 new tests pass.
- [ ] `YrsServerMergeTests` continue to pass.
- [ ] `applyUpdateToDoc` and `applyDescriptionEditorUpdate` no longer call `store.deleteSnapshot` on apply error.
- [ ] `plans/README.md` status row for plan 005 updated to DONE.

## STOP conditions

Stop and report if:
- The catch blocks do not match the excerpts above (renaming, additional lines, different error type).
- Removing the snapshot deletion causes callers to crash because they expected the doc to be evicted AND the snapshot gone.
- `DocumentManager.docs` access for test assertions is impossible without exposing internals beyond what already exists.

## Maintenance notes

- Callers (e.g., `YjsSyncService.applyServerDocumentState`) already catch `DocumentManager.applyUpdate` errors and handle them by requesting a document reload via `requestDocumentReload(recipeId:)`. Preserving the snapshot lets that reload merge against the latest local state instead of starting from empty.
- Reviewers should confirm that legitimate snapshot deletion paths (user switch, tombstone, corrupted-snapshot-at-load) are unchanged.
- The evicted in-memory doc is rebuilt lazily on the next `getOrCreateDoc` call; subsequent server merges will see the preserved local edits and merge them correctly via CRDT semantics.
