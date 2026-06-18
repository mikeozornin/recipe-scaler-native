import Foundation

// MARK: - Ingredient

/// Codable ingredient matching the export JSON shape (v1.0–v1.4).
/// Subset of `IngredientData` — only fields present in the export format.
///
/// Numeric amounts go to `originalAmount: Double?`. Non-numeric quantities
/// (`"1/2"`, `"2-3"`, `"to taste"`, …) go to optional `amountText: String?`.
/// Web v1.4 accepts `amountText` via `additionalProperties: true` on recipe
/// objects; older readers ignore unknown fields.
public struct NativeIngredient: Codable, Sendable, Equatable {
    public var id: String?
    public var name: String
    public var originalAmount: Double?
    public var amountText: String?
    public var unit: String?
    public var order: Int?
    public var isSeparator: Bool?

    public init(
        id: String? = nil,
        name: String,
        originalAmount: Double? = nil,
        amountText: String? = nil,
        unit: String? = nil,
        order: Int? = nil,
        isSeparator: Bool? = nil
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

// MARK: - Nutrition

/// Codable nutrition matching the export JSON shape (v1.2+).
public struct NativeNutrition: Codable, Sendable, Equatable {
    public var calories: Double?
    public var protein: Double?
    public var fat: Double?
    public var carbs: Double?
    public var calculatedAt: String?
    public var nutritionOutdated: Bool?
    public var totalWeight: Double?

    public init(
        calories: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        carbs: Double? = nil,
        calculatedAt: String? = nil,
        nutritionOutdated: Bool? = nil,
        totalWeight: Double? = nil
    ) {
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.calculatedAt = calculatedAt
        self.nutritionOutdated = nutritionOutdated
        self.totalWeight = totalWeight
    }
}

// MARK: - Recipe

/// Codable recipe matching the export JSON shape (v1.0–v1.4).
/// Mirrors `RecipeData` fields that appear in the export format.
public struct NativeRecipe: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String?
    public var ingredients: [NativeIngredient]
    public var color: String?
    public var servings: Double?
    public var createdAt: String?
    public var updatedAt: String?
    public var originalRecipeLink: String?
    public var originalRecipe: String?
    public var nutrition: NativeNutrition?
    public var folderIds: [String]?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        ingredients: [NativeIngredient] = [],
        color: String? = nil,
        servings: Double? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        originalRecipeLink: String? = nil,
        originalRecipe: String? = nil,
        nutrition: NativeNutrition? = nil,
        folderIds: [String]? = nil
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
        self.folderIds = folderIds
    }
}

// MARK: - Folder

/// Codable folder matching the export JSON shape (v1.4+).
public struct NativeFolder: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var color: String?
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: String,
        name: String,
        color: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Image manifest entry

/// Image file paths in ZIP manifest (v1.1+).
public struct NativeImageEntry: Codable, Sendable, Equatable {
    public var full: String
    public var preview: String

    public init(full: String, preview: String) {
        self.full = full
        self.preview = preview
    }
}

// MARK: - Metadata

/// Export file metadata (v1.0–v1.4).
public struct NativeExportMetadata: Codable, Sendable, Equatable {
    public var version: String
    public var exportDate: String
    public var type: String?
    public var count: Int?

    public init(version: String, exportDate: String, type: String? = nil, count: Int? = nil) {
        self.version = version
        self.exportDate = exportDate
        self.type = type
        self.count = count
    }
}

// MARK: - Full export payload

/// Top-level export JSON structure (v1.0–v1.4).
public struct NativeExportPayload: Codable, Sendable, Equatable {
    public var metadata: NativeExportMetadata
    public var recipes: [NativeRecipe]
    public var folders: [NativeFolder]?
    public var imageFiles: [String: NativeImageEntry]?

    public init(
        metadata: NativeExportMetadata,
        recipes: [NativeRecipe],
        folders: [NativeFolder]? = nil,
        imageFiles: [String: NativeImageEntry]? = nil
    ) {
        self.metadata = metadata
        self.recipes = recipes
        self.folders = folders
        self.imageFiles = imageFiles
    }
}

// MARK: - Import result

/// Result of importing a Recipe Scaler export file.
public struct NativeImportResult: Sendable {
    public var importedCount: Int
    public var importedRecipeIds: [String]
    public var foldersImported: Int
    public var imagesUploaded: Int
    public var errors: [String]
    public var warnings: [String]
    public var wasStopped: Bool

    public init(
        importedCount: Int = 0,
        importedRecipeIds: [String] = [],
        foldersImported: Int = 0,
        imagesUploaded: Int = 0,
        errors: [String] = [],
        warnings: [String] = [],
        wasStopped: Bool = false
    ) {
        self.importedCount = importedCount
        self.importedRecipeIds = importedRecipeIds
        self.foldersImported = foldersImported
        self.imagesUploaded = imagesUploaded
        self.errors = errors
        self.warnings = warnings
        self.wasStopped = wasStopped
    }

    public var success: Bool {
        errors.isEmpty || importedCount > 0
    }
}

// MARK: - Import error

public enum NativeImportError: Error, Sendable, LocalizedError {
    case fileAccessFailed
    case invalidFormat
    case missingRecipesJson
    case invalidJSON(String)
    case validationFailed([String])
    case emptyArchive
    case recipeLimitExceeded(Int)
    case corruptRecipe(String)
    case corruptFolder(String)
    case writeFailed(String)
    /// Single entry exceeds the per-entry decompressed byte cap.
    case entrySizeLimitExceeded(entryPath: String)
    /// Aggregate extracted bytes exceed the archive cap.
    case archiveSizeLimitExceeded
    /// Pre-flight JSON byte-size check failed.
    case jsonSizeLimitExceeded

    public var errorDescription: String? {
        switch self {
        case .fileAccessFailed:
            return "Cannot access the selected file."
        case .invalidFormat:
            return "The file is not a Recipe Scaler export."
        case .missingRecipesJson:
            return "recipes.json not found in ZIP archive."
        case .invalidJSON(let detail):
            return "Invalid JSON: \(detail)"
        case .validationFailed(let errors):
            return errors.joined(separator: "; ")
        case .emptyArchive:
            return "The archive contains no recipes."
        case .recipeLimitExceeded(let limit):
            return "Too many recipes (max \(limit))."
        case .corruptRecipe(let name):
            return "Failed to import recipe: \(name)"
        case .corruptFolder(let name):
            return "Failed to import folder: \(name)"
        case .writeFailed(let detail):
            return "Failed to write to Y.Doc: \(detail)"
        case .entrySizeLimitExceeded(let entryPath):
            return "Entry too large: \(entryPath)"
        case .archiveSizeLimitExceeded:
            return "Archive total size exceeds the limit."
        case .jsonSizeLimitExceeded:
            return "JSON payload exceeds the size limit."
        }
    }
}

// MARK: - Validation result

public struct NativeValidationResult: Sendable {
    public var structuralErrors: [String]
    public var recipeErrors: [(index: Int, errors: [String])]
    public var folderErrors: [(index: Int, errors: [String])]

    public init(
        structuralErrors: [String] = [],
        recipeErrors: [(index: Int, errors: [String])] = [],
        folderErrors: [(index: Int, errors: [String])] = []
    ) {
        self.structuralErrors = structuralErrors
        self.recipeErrors = recipeErrors
        self.folderErrors = folderErrors
    }

    public var isValid: Bool {
        structuralErrors.isEmpty
    }
}
