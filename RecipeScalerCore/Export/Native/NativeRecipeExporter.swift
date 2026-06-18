import Foundation
import ZIPFoundation

/// Export recipes, folders, and images into the Recipe Scaler v1.4 format.
///
/// Produces either a standalone JSON file (no images) or a ZIP archive
/// (with `recipes.json` at the root and `images/<recipeId>/full.webp` +
/// `images/<recipeId>/preview.webp` inside).
///
/// v1.4 with optional `amountText` on ingredients preserves non-numeric
/// quantities (`"1/2"`, `"2-3"`, `"to taste"`, …) through the export → import
/// roundtrip. Numeric amounts still go to `originalAmount`.
///
/// This type lives in `RecipeScalerCore` so it can be reused from
/// tests, Share Extensions, and the main app target.
public enum NativeRecipeExporter {

    /// Description of a single image file to be packed into the export archive.
    ///
    /// Used by the streaming exporter to read bytes lazily from disk
    /// instead of materializing all images into memory at once.
    public struct ImageFile: Sendable {
        public let recipeId: String
        public let fullURL: URL
        public let previewURL: URL

        public init(recipeId: String, fullURL: URL, previewURL: URL) {
            self.recipeId = recipeId
            self.fullURL = fullURL
            self.previewURL = previewURL
        }
    }

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
        let hasImages = !imageData.isEmpty
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        let payload = buildPayload(
            recipes: recipes,
            recipeFolderIds: recipeFolderIds,
            folders: folders,
            imageRecipeIds: Set(imageData.keys)
        )

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

    /// Streaming export: builds the same archive as `export(...)` but reads
    /// image bytes lazily from disk via `Archive.addEntry(provider:)`.
    ///
    /// The recipes JSON is encoded to a temp file with `JSONEncoder` and then
    /// streamed into the ZIP — neither the JSON nor any image is held in
    /// memory in full at the same time. Suitable for large libraries.
    ///
    /// - Parameters:
    ///   - recipes: Per-recipe data.
    ///   - recipeFolderIds: Mapping `recipeId → [folderId]`.
    ///   - folders: All user folders.
    ///   - imageFiles: Files to pack, keyed by recipeId. Only recipes that
    ///     appear in this collection are included in the image manifest.
    public static func exportStreaming(
        recipes: [ExportRecipe],
        recipeFolderIds: [String: [String]],
        folders: [ExportFolder],
        imageFiles: [ImageFile]
    ) throws -> ExportResult {
        let hasImages = !imageFiles.isEmpty
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        let payload = buildPayload(
            recipes: recipes,
            recipeFolderIds: recipeFolderIds,
            folders: folders,
            imageRecipeIds: Set(imageFiles.map(\.recipeId))
        )

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
            let zipData = try createZipStreaming(
                recipesJson: jsonData,
                imageFiles: imageFiles
            )
            return ExportResult(
                data: zipData,
                hasImages: true,
                filename: "recipe-scaler-\(timestamp).zip"
            )
        } else {
            return ExportResult(
                data: jsonData,
                hasImages: false,
                filename: "recipe-scaler-\(timestamp).json"
            )
        }
    }

    // MARK: - Private

    /// Build the v1.4 payload structure shared by both the in-memory and
    /// streaming exporters. `imageRecipeIds` controls which recipes appear
    /// in the image manifest.
    private static func buildPayload(
        recipes: [ExportRecipe],
        recipeFolderIds: [String: [String]],
        folders: [ExportFolder],
        imageRecipeIds: Set<String>
    ) -> NativeExportPayload {
        let imageManifest: [String: NativeImageEntry] = imageRecipeIds.reduce(
            into: [:]
        ) { dict, recipeId in
            let full = "images/\(recipeId)/full.webp"
            let preview = "images/\(recipeId)/preview.webp"
            dict[recipeId] = NativeImageEntry(full: full, preview: preview)
        }

        return NativeExportPayload(
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
                            amountText: ing.amountText,
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
    }

    /// Streaming ZIP builder. Reads each image lazily from disk via the
    /// ZIPFoundation `provider` closure — never materializes all images
    /// into memory at the same time.
    private static func createZipStreaming(
        recipesJson: Data,
        imageFiles: [ImageFile]
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

        // recipes.json — single pass via provider.
        try archive.addEntry(
            with: "recipes.json",
            type: .file,
            uncompressedSize: UInt32(recipesJson.count),
            compressionMethod: .deflate
        ) { position, size in
            recipesJson.subdata(in: position..<position + size)
        }

        // Image files — read directly from disk on demand.
        // We resolve the file size lazily via FileManager so we don't have
        // to load the bytes until the provider closure is called.
        for image in imageFiles {
            let fullPath = "images/\(image.recipeId)/full.webp"
            let previewPath = "images/\(image.recipeId)/preview.webp"

            if let fullSize = fileSize(at: image.fullURL) {
                let fullURL = image.fullURL
                try archive.addEntry(
                    with: fullPath,
                    type: .file,
                    uncompressedSize: UInt32(fullSize),
                    compressionMethod: .deflate
                ) { position, size in
                    try readRange(from: fullURL, position: position, size: size)
                }
            }

            if let previewSize = fileSize(at: image.previewURL) {
                let previewURL = image.previewURL
                try archive.addEntry(
                    with: previewPath,
                    type: .file,
                    uncompressedSize: UInt32(previewSize),
                    compressionMethod: .deflate
                ) { position, size in
                    try readRange(from: previewURL, position: position, size: size)
                }
            }
        }

        return try Data(contentsOf: zipURL)
    }

    /// Cheap file size lookup via FileManager attributes (no full read).
    private static func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attrs[.size] as? Int64
    }

    /// Read a `[position, position+size)` byte range from `url` without
    /// loading the whole file into memory.
    private static func readRange(from url: URL, position: Int, size: Int) throws -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw NativeImportError.writeFailed("Failed to open image at \(url.path)")
        }
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(position))
        return handle.readData(ofLength: size)
    }

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
    public let amountText: String?
    public let unit: String?
    public let order: Int?
    public let isSeparator: Bool?

    public init(
        id: String,
        name: String,
        originalAmount: Double?,
        amountText: String? = nil,
        unit: String?,
        order: Int?,
        isSeparator: Bool?
    ) {
        self.id = id
        self.name = name
        self.originalAmount = originalAmount
        self.amountText = amountText
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
