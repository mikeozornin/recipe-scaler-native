import Foundation
import RecipeScalerCore

@MainActor
final class NativeExportImportService {
    private let syncService: YjsSyncService

    init(syncService: YjsSyncService) {
        self.syncService = syncService
    }

    // MARK: - Export

    /// Export all recipes to a temp file and return the URL.
    ///
    /// Heavy work (recipe reads, JSON encoding, ZIP packing) is performed off
    /// the MainActor via `Task.detached(priority: .userInitiated)`. Only the
    /// initial snapshot of `collectionEntries` / `folders` is read on the
    /// MainActor, and progress callbacks are routed back to the MainActor.
    func exportAll(
        progress: @escaping @MainActor (_ completed: Int, _ total: Int) -> Void
    ) async throws -> URL {
        // MainActor snapshot — cheap, sync reads of @Published arrays.
        let entries = syncService.collectionEntries.filter { !$0.deleted }
        let folders = syncService.folders

        guard !entries.isEmpty else {
            throw NativeImportError.emptyArchive
        }

        // Build recipeFolderIds mapping (cheap, no I/O).
        var recipeFolderIds: [String: [String]] = [:]
        for entry in entries {
            if !entry.folderIds.isEmpty {
                recipeFolderIds[entry.id] = entry.folderIds
            }
        }

        let exportFolders = folders.map { folder in
            ExportFolder(
                id: folder.id,
                name: folder.name,
                color: folder.color,
                createdAt: folder.createdAt,
                updatedAt: folder.updatedAt
            )
        }

        let total = entries.count
        // Capture the sync service reference so the detached task can hop to
        // the MainActor for each `readRecipeData` call without re-entering
        // this class's actor isolation.
        let syncService = self.syncService

        // Detach heavy work — recipe reads + ZIP packing — to a background executor.
        let fileURL: URL = try await Task.detached(priority: .userInitiated) {
            // Per-recipe: read recipe data + image file URLs (single pass,
            // each recipe released before the next is read).
            var exportRecipes: [ExportRecipe] = []
            exportRecipes.reserveCapacity(total)
            var imageFiles: [NativeRecipeExporter.ImageFile] = []

            for (index, entry) in entries.enumerated() {
                if Task.isCancelled { break }

                let recipeData = try? await syncService.readRecipeData(recipeId: entry.id)

                await MainActor.run {
                    progress(index + 1, total)
                }

                guard let recipeData = recipeData else { continue }

                exportRecipes.append(
                    ExportRecipe(
                        id: recipeData.id,
                        name: recipeData.name,
                        description: recipeData.description,
                        ingredients: recipeData.ingredients.map { ing in
                            // Finding #15: non-numeric amounts ("1/2", "2-3",
                            // "1½", "to taste") must survive the roundtrip.
                            // Numeric values go to `originalAmount`, raw
                            // non-numeric text goes to `amountText`.
                            let numeric = ing.numericValue
                            let rawText = ing.originalAmount.isEmpty
                                ? ing.amount
                                : ing.originalAmount
                            let amountText: String? = (numeric == nil)
                                && ing.hasQuantity
                                && !rawText.isEmpty
                                ? rawText
                                : nil
                            return ExportIngredient(
                                id: ing.id,
                                name: ing.name,
                                originalAmount: numeric,
                                amountText: amountText,
                                unit: ing.unit.isEmpty ? nil : ing.unit,
                                order: ing.order,
                                isSeparator: ing.isSeparator ? true : nil
                            )
                        },
                        color: recipeData.color,
                        servings: recipeData.servings,
                        createdAt: recipeData.createdAt,
                        updatedAt: recipeData.updatedAt,
                        originalRecipeLink: recipeData.originalRecipeLink,
                        originalRecipe: recipeData.originalRecipe,
                        nutrition: recipeData.nutrition.map { n in
                            ExportNutrition(
                                calories: n.calories,
                                protein: n.protein,
                                fat: n.fat,
                                carbs: n.carbs,
                                calculatedAt: nil,
                                nutritionOutdated: n.nutritionOutdated
                            )
                        },
                        imageUrl: recipeData.imageUrl
                    )
                )

                if recipeData.imageUrl != nil {
                    if let fullURL = RecipeImageDiskCache.existingFileURL(
                        recipeId: recipeData.id, variant: .full
                    ),
                       let previewURL = RecipeImageDiskCache.existingFileURL(
                        recipeId: recipeData.id, variant: .preview
                       ) {
                        imageFiles.append(
                            NativeRecipeExporter.ImageFile(
                                recipeId: recipeData.id,
                                fullURL: fullURL,
                                previewURL: previewURL
                            )
                        )
                    }
                }
            }

            // Stream JSON + images into a single ZIP off the MainActor.
            let result = try NativeRecipeExporter.exportStreaming(
                recipes: exportRecipes,
                recipeFolderIds: recipeFolderIds,
                folders: exportFolders,
                imageFiles: imageFiles
            )

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("RecipeScalerExport")
            try FileManager.default.createDirectory(
                at: tempDir,
                withIntermediateDirectories: true
            )
            let fileURL = tempDir.appendingPathComponent(result.filename)
            try result.data.write(to: fileURL)
            return fileURL
        }.value

        return fileURL
    }

    // MARK: - Import

    /// Import recipes from a Recipe Scaler export file.
    func importFile(
        url: URL,
        isOnline: Bool,
        shouldStop: @escaping () -> Bool = { Task.isCancelled },
        progress: @escaping (_ completed: Int, _ total: Int) -> Void
    ) async throws -> NativeImportResult {
        let parsed: NativeRecipeImporter.ParsedImport
        do {
            parsed = try NativeRecipeImporter.parse(url: url)
        } catch let error as NativeImportError {
            throw error
        } catch {
            throw NativeImportError.invalidJSON(error.localizedDescription)
        }

        let recipes = parsed.recipes
        guard !recipes.isEmpty else {
            throw NativeImportError.emptyArchive
        }

        // Check limits
        if recipes.count > ThirdPartyImportLimits.maxRecipesPerImport {
            throw NativeImportError.recipeLimitExceeded(ThirdPartyImportLimits.maxRecipesPerImport)
        }

        var importedCount = 0
        var foldersImported = 0
        var imagesUploaded = 0
        var photosSkippedOffline = 0
        var errors: [String] = []
        var warnings: [String] = []
        let total = recipes.count

        // 1. Import folders, building old-id → new-id mapping
        let folderIdMapping = await importFolders(
            folders: parsed.folders,
            errors: &errors
        )
        foldersImported = folderIdMapping.count

        let imageMap = Dictionary(
            grouping: parsed.imageEntries,
            by: \.recipeId
        )

        // 2. Import recipes (+ inline image upload when online)
        var recipeMappings: [String: String] = [:]
        var importedRecipeIds: [String] = []

        for (index, recipe) in recipes.enumerated() {
            if shouldStop() { break }

            do {
                let newId = try await syncService.applyNativeRecipe(recipe)
                recipeMappings[recipe.id] = newId
                importedRecipeIds.append(newId)
                importedCount += 1

                let entries = imageMap[recipe.id] ?? []
                if !entries.isEmpty {
                    if !isOnline {
                        photosSkippedOffline += 1
                    } else {
                        await uploadRecipeImageIfNeeded(
                            exportRecipeId: recipe.id,
                            newRecipeId: newId,
                            recipeName: recipe.name,
                            entries: entries,
                            imagesUploaded: &imagesUploaded,
                            warnings: &warnings
                        )
                    }
                }
            } catch {
                errors.append(NativeImportMessageLocalizer.recipeFailed(name: recipe.name, error: error))
            }

            progress(index + 1, total)
        }

        if photosSkippedOffline > 0 {
            warnings.append(NativeImportMessageLocalizer.imagesOffline(count: photosSkippedOffline))
        }

        let wasStopped = shouldStop()

        // 3. Assign recipes to folders using remapped IDs
        if !wasStopped {
            for recipe in recipes {
                if shouldStop() { break }
                guard let folderIds = recipe.folderIds, !folderIds.isEmpty else { continue }
                guard let newRecipeId = recipeMappings[recipe.id] else { continue }

                let remapped = folderIds.compactMap { folderIdMapping[$0] }
                if !remapped.isEmpty {
                    try? await syncService.setRecipeFolders(
                        recipeId: newRecipeId,
                        folderIds: remapped
                    )
                }
            }
        }

        return NativeImportResult(
            importedCount: importedCount,
            importedRecipeIds: importedRecipeIds,
            foldersImported: foldersImported,
            imagesUploaded: imagesUploaded,
            errors: errors,
            warnings: warnings,
            wasStopped: wasStopped || shouldStop()
        )
    }

    // MARK: - Detection

    /// Check if a file looks like a Recipe Scaler native export.
    static func isNativeFormat(url: URL) -> Bool {
        // Quick heuristic: check file extension and try to detect version
        let ext = url.pathExtension.lowercased()
        guard ext == "json" || ext == "zip" || ext == "data" else { return false }
        return (try? NativeFormatDetector.detect(url: url)) != nil
    }

    // MARK: - Private

    private func importFolders(
        folders: [NativeFolder],
        errors: inout [String]
    ) async -> [String: String] {
        var mapping: [String: String] = [:]

        for folder in folders {
            if Task.isCancelled { break }
            let trimmed = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errors.append(NativeImportMessageLocalizer.folderEmptySkipped())
                continue
            }

            do {
                // Use resolveOrCreateFolderId for case-insensitive dedup
                // We need to get the new folder ID. Since createFolder returns the ID
                // and resolveOrCreateFolderId is on the DocumentManager,
                // we'll create the folder and track the mapping.
                let newId = try await syncService.createFolder(
                    name: trimmed,
                    color: folder.color
                )
                mapping[folder.id] = newId
            } catch {
                errors.append(NativeImportMessageLocalizer.folderFailed(name: trimmed, error: error))
            }
        }

        return mapping
    }

    private func uploadRecipeImageIfNeeded(
        exportRecipeId: String,
        newRecipeId: String,
        recipeName: String,
        entries: [NativeRecipeImporter.ImageEntry],
        imagesUploaded: inout Int,
        warnings: inout [String]
    ) async {
        switch NativeImportImagePicker.selection(from: entries) {
        case .none:
            return
        case .tooLarge:
            warnings.append(NativeImportMessageLocalizer.imageTooLarge(name: recipeName))
        case .ready(let imageData):
            do {
                try await syncService.uploadImportedRecipeImage(
                    recipeId: newRecipeId,
                    imageData: imageData
                )
                imagesUploaded += 1
            } catch {
                AppLog.notice(
                    .sync,
                    "native_import_image_upload_failed",
                    data: [
                        "recipeId": newRecipeId,
                        "exportRecipeId": exportRecipeId,
                        "error": String(describing: error),
                    ]
                )
                warnings.append(NativeImportMessageLocalizer.imageFailed(name: recipeName))
            }
        }
    }
}
