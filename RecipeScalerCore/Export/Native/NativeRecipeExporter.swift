import Foundation
import ZIPFoundation

/// Export recipes, folders, and images into the Recipe Scaler v1.4 format.
///
/// Produces either a standalone JSON file (no images) or a ZIP archive
/// (with `recipes.json` at the root and `images/<recipeId>/full.webp` +
/// `images/<recipeId>/preview.webp` inside).
///
/// This type lives in `RecipeScalerCore` so it can be reused from
/// tests, Share Extensions, and the main app target.
public enum NativeRecipeExporter {

    /// Result of an export operation.
    public struct ExportResult: Sendable {
        /// Serialized file data (JSON or ZIP).
        public let data: Data
        /// `true` when the output is a ZIP containing images.
        public let hasImages: Bool
        /// Suggested filename, e.g. `recipe-scaler-2026-06-16T12-00-00Z.zip`.
        public let filename: String
    }

    /// Export a collection of recipes into v1.4 format.
    ///
    /// - Parameters:
    ///   - recipes: Per-recipe data coming from the Y.Doc layer.
    ///   - recipeFolderIds: Mapping `recipeId → [folderId]`.
    ///   - folders: All user folders (collections).
    ///   - imageData: Optional mapping `recipeId → (full: Data, preview: Data)`.
    ///     Only recipes with both full and preview images are included.
    ///
    /// - Returns: An `ExportResult` ready to be written to a temporary file
    ///   and presented via a system share sheet.
    public static func export(
        recipes: [ExportRecipe],
        recipeFolderIds: [String: [String]],
        folders: [ExportFolder],
        imageData: [String: (full: Data, preview: Data)] = [:]
    ) throws -> ExportResult {
        // Build image manifest
        let imageManifest: [String: NativeImageEntry] = imageData.reduce(
            into: [:]
        ) { dict, entry in
            let (recipeId, images) = entry
            let full = "images/\(recipeId)/full.webp"
            let preview = "images/\(recipeId)/preview.webp"
            dict[recipeId] = NativeImageEntry(full: full, preview: preview)
        }

        let hasImages = !imageManifest.isEmpty
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        // Build payload
        var payload = NativeExportPayload(
            metadata: NativeExportMetadata(
                version: "1.4",
                exportDate: ISO8601DateFormatter().string(from: Date()),
                type: "recipes-v1.4",
                count: recipes.count
            ),
            recipes: recipes.map { recipe in
                var native = NativeRecipe(
                    id: recipe.id,
                    name: recipe.name,
                    description: recipe.description,
                    ingredients: recipe.ingredients.map { ing in
                        NativeIngredient(
                            id: ing.id,
                            name: ing.name,
                            originalAmount: ing.originalAmount,
                            unit: ing.unit,
                            order: ing.order,
                            isSeparator: ing.isSeparator
                        )
                    },
                    color: recipe.color,
                    servings: recipe.servings.map(Double.init),
                    createdAt: recipe.createdAt,
                    updatedAt: recipe.updatedAt,
                    originalRecipeLink: recipe.originalRecipeLink,
                    originalRecipe: recipe.originalRecipe,
                    nutrition: recipe.nutrition.map { n in
                        NativeNutrition(
                            calories: n.calories,
                            protein: n.protein,
                            fat: n.fat,
                            carbs: n.carbs,
                            calculatedAt: n.calculatedAt,
                            nutritionOutdated: n.nutritionOutdated
                        )
                    }
                )
                if let fids = recipeFolderIds[recipe.id], !fids.isEmpty {
                    native.folderIds = fids
                }
                return native
            },
            folders: folders.isEmpty ? nil : folders.map { folder in
                NativeFolder(
                    id: folder.id,
                    name: folder.name,
                    color: folder.color,
                    createdAt: folder.createdAt,
                    updatedAt: folder.updatedAt
                )
            },
            imageFiles: imageManifest.isEmpty ? nil : imageManifest
        )

        // Normalize line terminators (same as web exporter)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(payload)
        let jsonString = normalizeLineTerminators(
            String(data: encoded, encoding: .utf8) ?? ""
        )

        guard let jsonData = jsonString.data(using: String.Encoding.utf8) else {
            throw NativeImportError.writeFailed("Failed to encode JSON")
        }

        if hasImages {
            // ZIP path
            let zipData = try createZip(
                recipesJson: jsonData,
                imageData: imageData
            )
            return ExportResult(
                data: zipData,
                hasImages: true,
                filename: "recipe-scaler-\(timestamp).zip"
            )
        } else {
            // JSON path
            return ExportResult(
                data: jsonData,
                hasImages: false,
                filename: "recipe-scaler-\(timestamp).json"
            )
        }
    }

    // MARK: - Private

    private static func createZip(
        recipesJson: Data,
        imageData: [String: (full: Data, preview: Data)]
    ) throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let zipURL = tempDir.appendingPathComponent("export.zip")

        let archive = try Archive(url: zipURL, accessMode: .create)

        // Add recipes.json
        try archive.addEntry(
            with: "recipes.json",
            type: .file,
            uncompressedSize: UInt32(recipesJson.count),
            compressionMethod: .deflate
        ) { position, size in
            recipesJson.subdata(in: position..<position + size)
        }

        // Add image files
        for (recipeId, images) in imageData {
            let fullPath = "images/\(recipeId)/full.webp"
            let previewPath = "images/\(recipeId)/preview.webp"

            try archive.addEntry(
                with: fullPath,
                type: .file,
                uncompressedSize: UInt32(images.full.count),
                compressionMethod: .deflate
            ) { position, size in
                images.full.subdata(in: position..<position + size)
            }

            try archive.addEntry(
                with: previewPath,
                type: .file,
                uncompressedSize: UInt32(images.preview.count),
                compressionMethod: .deflate
            ) { position, size in
                images.preview.subdata(in: position..<position + size)
            }
        }

        return try Data(contentsOf: zipURL)
    }

    /// Normalize Unicode line terminators to plain newlines (matches web exporter).
    private static func normalizeLineTerminators(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }
}

// MARK: - Export input types

/// Lightweight recipe input for the exporter.
/// Decouples the exporter from Y.Doc-specific types.
public struct ExportRecipe: Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let ingredients: [ExportIngredient]
    public let color: String
    public let servings: Int?
    public let createdAt: String?
    public let updatedAt: String?
    public let originalRecipeLink: String?
    public let originalRecipe: String?
    public let nutrition: ExportNutrition?
    public let imageUrl: String?

    public init(
        id: String,
        name: String,
        description: String?,
        ingredients: [ExportIngredient],
        color: String,
        servings: Int?,
        createdAt: String?,
        updatedAt: String?,
        originalRecipeLink: String?,
        originalRecipe: String?,
        nutrition: ExportNutrition?,
        imageUrl: String?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.ingredients = ingredients
        self.color = color
        self.servings = servings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originalRecipeLink = originalRecipeLink
        self.originalRecipe = originalRecipe
        self.nutrition = nutrition
        self.imageUrl = imageUrl
    }
}

public struct ExportIngredient: Sendable {
    public let id: String
    public let name: String
    public let originalAmount: Double?
    public let unit: String?
    public let order: Int?
    public let isSeparator: Bool?

    public init(
        id: String,
        name: String,
        originalAmount: Double?,
        unit: String?,
        order: Int?,
        isSeparator: Bool?
    ) {
        self.id = id
        self.name = name
        self.originalAmount = originalAmount
        self.unit = unit
        self.order = order
        self.isSeparator = isSeparator
    }
}

public struct ExportNutrition: Sendable {
    public let calories: Double?
    public let protein: Double?
    public let fat: Double?
    public let carbs: Double?
    public let calculatedAt: String?
    public let nutritionOutdated: Bool?

    public init(
        calories: Double?,
        protein: Double?,
        fat: Double?,
        carbs: Double?,
        calculatedAt: String?,
        nutritionOutdated: Bool?
    ) {
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.calculatedAt = calculatedAt
        self.nutritionOutdated = nutritionOutdated
    }
}

public struct ExportFolder: Sendable {
    public let id: String
    public let name: String
    public let color: String?
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        id: String,
        name: String,
        color: String?,
        createdAt: String?,
        updatedAt: String?
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
