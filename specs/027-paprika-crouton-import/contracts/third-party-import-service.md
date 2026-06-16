# Contract: ThirdPartyRecipeImportService

**Feature**: `027-paprika-crouton-import`  
**Дата**: 2026-06-15  
**Статус**: Draft

Internal API between UI (`ImportRecipeSheet`) and Y.Doc write layer. Lives in `RecipeScalerNative`; parsers in `RecipeScalerCore`.

## Types (RecipeScalerCore)

```swift
public enum ThirdPartyFormat: Sendable { /* see data-model.md */ }

public struct ThirdPartyRecipeDraft: Sendable { /* see data-model.md */ }

public struct ThirdPartyImportResult: Sendable {
    public let importedRecipeIds: [String]
    public let failed: [(fileName: String, error: ThirdPartyImportError)]
    public let photosSkippedOffline: Int
    public let photosFailed: Int
}

public protocol ThirdPartyRecipeParsing: Sendable {
    func parsePaprikaGzipJSON(_ data: Data, fileName: String) throws -> ThirdPartyRecipeDraft
    func parseCroutonJSON(_ data: Data, fileName: String) throws -> ThirdPartyRecipeDraft
}

public enum ThirdPartyFormatDetector {
    public static func detect(url: URL) throws -> ThirdPartyFormat
    public static func enumerateRecipeEntries(
        url: URL,
        format: ThirdPartyFormat
    ) throws -> [ThirdPartyArchiveEntry]
}

public struct ThirdPartyArchiveEntry: Sendable {
    public let fileName: String
    public let data: Data  // raw entry bytes (gzip or json)
}
```

## Service (RecipeScalerNative)

```swift
@MainActor
final class ThirdPartyRecipeImportService {
    init(documentManager: DocumentManager, syncService: YjsSyncService)

    /// Throws before mutating collection if limit exceeded or empty archive.
    func importFile(
        url: URL,
        progress: @escaping (_ completed: Int, _ total: Int) -> Void
    ) async throws -> ThirdPartyImportResult
}
```

### Behavior

1. `detect` → if `.unsupported`, throw `ThirdPartyImportError.unsupportedFormat`.
2. `enumerateRecipeEntries` → if empty, throw `.emptyArchive`.
3. If count > 500, throw `.recipeLimitExceeded`.
4. For each entry:
   - Parse to draft (catch → append to `failed`, continue).
   - `applyImportedRecipe(draft)` on DocumentManager.
   - If `imageData` present && network → upload; else increment skip counters.
   - `progress(index+1, total)`.
   - If `Task.isCancelled`, break loop (return partial result).

### DocumentManager extension

```swift
extension DocumentManager {
    /// Single recipe: create + ingredients + description + metadata in minimal transactions.
    func applyImportedRecipe(_ draft: ThirdPartyRecipeDraft) async throws -> String
}
```

Must set `hasSteps`, `originalRecipe*`, renumber ingredient orders, call `deliverPendingLocalUpdate`.

## UI contract (ImportRecipeSheet)

| Event | Action |
|-------|--------|
| User selects file | `fileImporter` → security-scoped URL |
| Submit | `ThirdPartyRecipeImportService.importFile` |
| 1 imported id | `onImport(ImportRecipesResult(recipeIds: [id]))` + dismiss |
| 2+ ids | `onImport` + summary alert/toast |
| Error before start | red footnote, no dismiss |

New `ImportMode.file` in segmented control (or separate section below text/photo).

## i18n keys (minimum)

| Key | Use |
|-----|-----|
| `import.tab-file` | Segmented label |
| `import.file-hint` | Footer help |
| `import.file-pick` | Button |
| `import.third-party-progress` | `%1$d / %2$d` |
| `import.third-party-summary` | `%1$d imported, %2$d failed` |
| `import.third-party-unsupported` | Wrong format |
| `import.third-party-limit` | >500 recipes |
| `import.third-party-photo-skipped-offline` | Summary note |

## Test contract

Each parser test:

- Input: fixture file path
- Assert: `draft.name`, `ingredients.count`, `descriptionBlocks` list item count
- Optional: snapshot hash of serialized draft (stable fields only)

Roundtrip test (integration):

- Import draft → `applyImportedRecipe` → `RecipeReader.read` → compare name + ingredient count + HTML contains step text.

## Non-goals

- No Socket.IO changes
- No new REST endpoints
- No Telegram / RS v1.3 zip (020)
