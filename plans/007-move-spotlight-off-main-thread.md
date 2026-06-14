# Plan 007: Move Spotlight indexing off the main thread

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b72ee4b..HEAD -- RecipeScalerNative/Services/SpotlightIndexer.swift RecipeScalerNativeTests/`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `b72ee4b`, 2026-06-13
- **Issue**: (none)

## Why this matters

`SpotlightIndexer` is `@MainActor` and performs HTML parsing, ingredient snippet construction, and image file I/O (`Data(contentsOf:)`) synchronously for every dirty recipe. On a large collection this blocks the UI thread. This plan moves the expensive work to a background task and keeps only the final `CSSearchableIndex.indexSearchableItems` call on the main actor (CoreSpotlight APIs are main-actor in Swift 6).

## Current state

- `RecipeScalerNative/Services/SpotlightIndexer.swift` — current implementation.

Relevant excerpts today:

```swift
// RecipeScalerNative/Services/SpotlightIndexer.swift:17-18
@MainActor
final class SpotlightIndexer: ObservableObject {
```

```swift
// RecipeScalerNative/Services/SpotlightIndexer.swift:99-101
for entry in dirty {
    await indexOne(entry: entry)
}
```

```swift
// RecipeScalerNative/Services/SpotlightIndexer.swift:104-157
private func indexOne(entry: CollectionEntry) async {
    guard var recipe = await syncService.peekRecipeData(recipeId: entry.id) else { return }
    recipe = RecipeCollectionMerge.merged(recipe, with: entry)
    // ... build preview, parse HTML, read image data ...
    try? await CSSearchableIndex.default().indexSearchableItems([item])
}
```

Repo conventions:
- `syncService.peekRecipeData` is already async and actor-isolated.
- `CSSearchableIndex` APIs are main-actor in current SDK.
- Logging uses `OSLog`.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` | exit 0 |
| Tests     | `xcodebuild -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test` | all pass, including new tests |

## Scope

**In scope**:
- `RecipeScalerNative/Services/SpotlightIndexer.swift`
- `RecipeScalerNativeTests/RecipeScalerNativeTests.swift` or new `SpotlightIndexerTests.swift`

**Out of scope**:
- Changing the indexed content or action identifiers.
- Replacing `NSAttributedString` HTML parsing.
- Background fetch / indexing scheduling.

## Git workflow

- Branch: `advisor/007-move-spotlight-off-main-thread`
- Commit per step, message style: `perf(spotlight): move indexing work off main thread`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Add a background task wrapper in `reindex`

Run the dirty-entry loop inside `Task.detached` (or a custom global actor) so HTML parsing and file I/O happen off-main. Keep the final `indexSearchableItems` call on the main actor.

Target shape:
```swift
private func reindex(entries: [CollectionEntry]) async {
    guard !entries.isEmpty else {
        await clearAll()
        return
    }

    let live = entries.filter { !$0.deleted }
    let liveIds = Set(live.map { $0.id })

    // Stale deletion can stay on main actor; it is fast.
    let stale = Set(indexedFingerprints.keys).subtracting(liveIds)
    if !stale.isEmpty {
        do {
            try await CSSearchableIndex.default()
                .deleteSearchableItems(withIdentifiers: Array(stale))
        } catch {
            logger.warning("delete stale failed: \(error.localizedDescription)")
        }
        for id in stale {
            indexedFingerprints.removeValue(forKey: id)
        }
    }

    let dirty = live.filter { indexedFingerprints[$0.id] != indexFingerprint(for: $0) }
    guard !dirty.isEmpty else { return }

    logger.info("Reindexing \(dirty.count) recipe(s)")

    // Build attribute sets off-main.
    let items = await Task.detached(priority: .utility) { [weak self] in
        guard let self else { return [CSSearchableItem]() }
        var result: [CSSearchableItem] = []
        for entry in dirty {
            if let item = await self.buildItem(for: entry) {
                result.append(item)
            }
        }
        return result
    }.value

    // Indexing API must be main-actor.
    do {
        try await CSSearchableIndex.default().indexSearchableItems(items)
        for entry in dirty {
            indexedFingerprints[entry.id] = indexFingerprint(for: entry)
        }
    } catch {
        logger.warning("Index batch failed: \(error.localizedDescription)")
    }
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 2: Extract `buildItem(for:)` helper

Move the per-recipe work from `indexOne` into a new helper that returns `CSSearchableItem?`. This helper does not need to be `@MainActor` if it only touches `syncService.peekRecipeData`, `RecipeCollectionMerge`, string helpers, and file I/O.

However, `syncService` is `@MainActor`. Calling `await syncService.peekRecipeData` from a detached task will hop to the main actor for that call, which partly defeats the purpose. To avoid that, pre-fetch the recipe data on the main actor before entering the detached task.

Refined target shape:
```swift
private func reindex(entries: [CollectionEntry]) async {
    // ... stale cleanup ...

    let dirty = live.filter { indexedFingerprints[$0.id] != indexFingerprint(for: $0) }
    guard !dirty.isEmpty else { return }

    // Pre-fetch recipe data on main actor (syncService is main-actor).
    var recipeData: [String: RecipeData] = [:]
    for entry in dirty {
        if let recipe = await syncService.peekRecipeData(recipeId: entry.id) {
            recipeData[entry.id] = RecipeCollectionMerge.merged(recipe, with: entry)
        }
    }

    let items = await Task.detached(priority: .utility) { [weak self] in
        guard let self else { return [CSSearchableItem]() }
        var result: [CSSearchableItem] = []
        for entry in dirty {
            guard let recipe = recipeData[entry.id] else { continue }
            if let item = self.buildItem(entry: entry, recipe: recipe) {
                result.append(item)
            }
        }
        return result
    }.value

    // ... index items on main actor ...
}
```

`buildItem(entry:recipe:)` should be a nonisolated or static method that performs HTML parsing and file I/O without touching main-actor state.

**Verify**: `xcodebuild build` → exit 0.

### Step 3: Cache plain-text descriptions

Add an `NSCache<String, String>` for `plainText(fromHTML:)` results keyed by a fingerprint of the description HTML. This avoids re-parsing the same description on every collection change.

Target shape:
```swift
private static let plainTextCache = NSCache<NSString, NSString>()

private static func plainText(fromHTML html: String?) -> String? {
    guard let html, !html.isEmpty else { return nil }
    let key = html as NSString
    if let cached = plainTextCache.object(forKey: key) { return cached as String }
    let result = // existing parsing logic
    if let result {
        plainTextCache.setObject(result as NSString, forKey: key)
    }
    return result
}
```

**Verify**: `xcodebuild build` → exit 0.

### Step 4: Add cancellation support

Store a reference to the detached task and cancel it when `stop()` or `clearAll()` is called, so a large reindex does not outlive the user session.

```swift
private var reindexTask: Task<Void, Never>?

private func reindex(entries: [CollectionEntry]) async {
    reindexTask?.cancel()
    reindexTask = Task { ... }
    await reindexTask?.value
}
```

Inside the detached task, check `Task.isCancelled` between recipes.

**Verify**: `xcodebuild build` → exit 0.

### Step 5: Add tests

Add a new file `RecipeScalerNativeTests/SpotlightIndexerTests.swift`:
- `testPlainTextCacheReturnsSameResult` — call `plainText(fromHTML:)` twice with the same HTML; assert same result.
- `testBuildItemRunsWithoutMainActorDependencies` — if `buildItem` is internal, call it directly from a non-main context.
- Snapshot/behavior tests are optional because CoreSpotlight is hard to mock.

**Verify**: `xcodebuild test` → new tests pass.

## Test plan

- New file `RecipeScalerNativeTests/SpotlightIndexerTests.swift`:
  - `testPlainTextCache`
  - `testBuildItemOffMain`
- Existing tests continue to pass.

## Done criteria

- [ ] `xcodebuild build` exits 0.
- [ ] `xcodebuild test` exits 0; new tests pass.
- [ ] `SpotlightIndexer` no longer performs HTML parsing or `Data(contentsOf:)` on the main actor.
- [ ] Cancellation is handled during reindex.
- [ ] `plans/README.md` status row for plan 007 updated to DONE.

## STOP conditions

Stop and report if:
- `CSSearchableIndex` APIs are no longer main-actor in the current SDK (Swift 5.9/iOS 17) and the build fails.
- `syncService.peekRecipeData` cannot be called before the detached task.
- The refactored code changes indexed content or action identifiers.

## Maintenance notes

- Future work: batch `indexSearchableItems` calls into larger chunks for very large collections.
- Reviewers should verify that the `addToShopping` action identifier is preserved and that the indexed fingerprint logic still skips unchanged recipes.
