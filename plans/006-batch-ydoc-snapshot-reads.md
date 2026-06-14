# Plan 006: Batch Y.Doc snapshot reads from SQLite

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b72ee4b..HEAD -- RecipeScalerNative/Services/Storage/YDocStore.swift RecipeScalerNative/Services/YjsSync/YjsSyncService.swift RecipeScalerNativeTests/`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `b72ee4b`, 2026-06-13
- **Issue**: (none)

## Why this matters

Collection refresh and cache-status checks currently issue one SQLite read per recipe in a serial loop. For large libraries this is O(N) actor round-trips and delays the recipe list. This plan adds batch read methods to `YDocStore` and converts the three hot loops in `YjsSyncService` to use them.

## Current state

- `RecipeScalerNative/Services/Storage/YDocStore.swift` — only single-key reads (`loadSnapshot`, `loadYjsWireSnapshot`).
- `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` — three per-recipe loops.

Relevant excerpts today:

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1749-1759
private func recipeIdsMissingLocalSnapshots(recipeIds: [String]) async -> [String] {
    var missing: [String] = []
    for recipeId in recipeIds where isRecipeDocument(recipeId: recipeId) {
        let docKey = docKeyFor(recipeId: recipeId)
        let hasLocal = (try? await store.loadSnapshot(docKey: docKey)) != nil
        if !hasLocal { missing.append(recipeId) }
    }
    return missing
}
```

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1862-1889
private func refreshRecipeDocumentCacheStatus(...) async {
    // ...
    for entry in entries where isRecipeDocument(recipeId: entry.id) {
        let docKey = docKeyFor(recipeId: entry.id)
        let local = (try? await store.loadSnapshot(docKey: docKey))?.state
        // ... compare local vs server ...
    }
}
```

```swift
// RecipeScalerNative/Services/YjsSync/YjsSyncService.swift:1350-1355
private func refreshWireSnapshotsForRecipes(recipeIds: [String]) async {
    for recipeId in recipeIds where isRecipeDocument(recipeId: recipeId) {
        guard await hasUnsyncedLocalChanges(recipeId: recipeId) else { continue }
        await refreshWireSnapshotForRecipe(recipeId: recipeId)
    }
}
```

`refreshWireSnapshotForRecipe` internally calls `store.loadYjsWireSnapshot` and `store.loadSnapshot` per recipe.

Repo conventions:
- `YDocStore` is an actor; add new methods as actor-isolated `func`.
- GRDB fetch patterns: use `filter(keys:)` or `filter(Column("docKey").in(docKeys))`.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` | exit 0 |
| Tests     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test` | all pass, including new tests |

## Scope

**In scope**:
- `RecipeScalerNative/Services/Storage/YDocStore.swift`
- `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift`
- `RecipeScalerNativeTests/YjsOfflineSyncTests.swift` (add tests)

**Out of scope**:
- Batch writes or batch deletions.
- Changing the `YDocSnapshot`/`YjsWireSnapshot` schema.
- Other callers of `YDocStore`.

## Git workflow

- Branch: `advisor/006-batch-ydoc-snapshot-reads`
- Commit per step, message style: `perf(sync): batch snapshot reads in YDocStore` / `perf(sync): use batch snapshot reads in cache status`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Add batch read methods to `YDocStore`

Add the following methods to `YDocStore`:

```swift
/// Load snapshots for multiple doc keys in a single database read.
func loadSnapshots(docKeys: [String]) throws -> [String: YDocSnapshot] {
    try dbQueue.read { db in
        let rows = try YDocSnapshot.fetchAll(db, keys: docKeys)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.docKey, $0) })
    }
}

/// Return only the doc keys that have a snapshot.
func existingSnapshotKeys(docKeys: [String]) throws -> Set<String> {
    try dbQueue.read { db in
        let keys = try String.fetchAll(
            db,
            sql: "SELECT docKey FROM ydoc_snapshots WHERE docKey IN \(docKeys.map { "'\($0)'" }.joined(separator: ","))"
        )
        return Set(keys)
    }
}
```

Use GRDB's `filter(keys:)` API if available instead of raw SQL to avoid SQL-injection risk. For example:
```swift
let rows = try YDocSnapshot.filter(keys: docKeys).fetchAll(db)
```

Also add batch wire-snapshot read:
```swift
func loadYjsWireSnapshots(docKeys: [String]) throws -> [String: YjsWireSnapshot] {
    try dbQueue.read { db in
        let rows = try YjsWireSnapshot.filter(keys: docKeys).fetchAll(db)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.docKey, $0) })
    }
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 2: Convert `recipeIdsMissingLocalSnapshots` to batch read

Target shape:
```swift
private func recipeIdsMissingLocalSnapshots(recipeIds: [String]) async -> [String] {
    let candidateRecipeIds = recipeIds.filter { isRecipeDocument(recipeId: $0) }
    let docKeys = candidateRecipeIds.map { docKeyFor(recipeId: $0) }
    guard !docKeys.isEmpty else { return [] }
    let existing = (try? await store.existingSnapshotKeys(docKeys: docKeys)) ?? []
    return candidateRecipeIds.enumerated()
        .compactMap { index, recipeId in existing.contains(docKeys[index]) ? nil : recipeId }
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 3: Convert `refreshRecipeDocumentCacheStatus` to batch read

Load all snapshots upfront, then iterate in memory:

```swift
let docKeys = entries.filter { isRecipeDocument(recipeId: $0.id) }.map { docKeyFor(recipeId: $0.id) }
let snapshots = (try? await store.loadSnapshots(docKeys: docKeys)) ?? [:]
for entry in entries where isRecipeDocument(recipeId: entry.id) {
    let docKey = docKeyFor(recipeId: entry.id)
    let local = snapshots[docKey]?.state
    // ... existing comparison logic ...
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 4: Convert `refreshWireSnapshotsForRecipes` to batch read

Inside `refreshWireSnapshotsForRecipes`, load both wire and regular snapshots in batch before looping. Alternatively, batch the per-recipe helper calls. The simplest win is to pass preloaded bootstrap maps into `refreshWireSnapshotForRecipe`.

If the helper signature change is too invasive, at least batch the reads at the top of `refreshWireSnapshotsForRecipes`:

```swift
let docKeys = recipeIds.filter { isRecipeDocument(recipeId: $0) }.map { docKeyFor(recipeId: $0) }
let wireSnapshots = (try? await store.loadYjsWireSnapshots(docKeys: docKeys)) ?? [:]
let snapshots = (try? await store.loadSnapshots(docKeys: docKeys)) ?? [:]
for recipeId in recipeIds where isRecipeDocument(recipeId: recipeId) {
    guard await hasUnsyncedLocalChanges(recipeId: recipeId) else { continue }
    await refreshWireSnapshotForRecipe(
        recipeId: recipeId,
        wireSnapshot: wireSnapshots[docKeyFor(recipeId: recipeId)],
        snapshot: snapshots[docKeyFor(recipeId: recipeId)]
    )
}
```

Then update `refreshWireSnapshotForRecipe` to accept optional preloaded snapshots instead of loading them.

**Verify**: `xcodebuild build` → exit 0.

### Step 5: Add tests for batch methods

Add tests in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`:
- `testLoadSnapshotsBatch` — save snapshots for A and B, load both, assert correct mapping.
- `testExistingSnapshotKeys` — save A, ask for A and B, assert result is `{A}`.
- `testLoadYjsWireSnapshotsBatch` — same for wire snapshots.

**Verify**: `xcodebuild test` → new tests pass.

## Test plan

- New tests in `RecipeScalerNativeTests/YjsOfflineSyncTests.swift`:
  - `testLoadSnapshotsBatch`
  - `testExistingSnapshotKeys`
  - `testLoadYjsWireSnapshotsBatch`
- Existing Yjs/offline tests continue to pass.

## Done criteria

- [ ] `xcodebuild build` exits 0.
- [ ] `xcodebuild test` exits 0; new batch tests pass.
- [ ] `recipeIdsMissingLocalSnapshots`, `refreshRecipeDocumentCacheStatus`, and `refreshWireSnapshotsForRecipes` no longer call per-recipe `loadSnapshot`/`loadYjsWireSnapshot` inside loops.
- [ ] `plans/README.md` status row for plan 006 updated to DONE.

## STOP conditions

Stop and report if:
- `YDocStore` actor isolation prevents adding the new methods.
- GRDB `filter(keys:)` is unavailable for the record types; use raw SQL with parameterized queries instead.
- Batch conversion changes observable behavior (e.g., cache status reporting).

## Maintenance notes

- Future batch write optimizations should reuse the same pattern.
- Reviewers should verify that the batch reads preserve nil-handling semantics (missing snapshot = nil).
