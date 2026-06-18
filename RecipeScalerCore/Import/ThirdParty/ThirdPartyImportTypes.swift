//
//  ThirdPartyImportTypes.swift
//  RecipeScalerCore
//

import Foundation

public enum ThirdPartyFormat: String, Sendable, Equatable {
    case paprikaArchive
    case paprikaSingle
    case croutonArchive
    case croutonSingle
    case unsupported
}

public enum ThirdPartyImportError: Error, Equatable, Sendable {
    case unsupportedFormat
    case emptyArchive
    case recipeLimitExceeded(limit: Int)
    case corruptEntry(fileName: String)
    case invalidJSON(fileName: String)
    case gzipFailed(fileName: String)
    /// Single entry exceeds `maxDecompressedEntryBytes` (decompression-bomb guard).
    case entrySizeLimitExceeded(fileName: String)
    /// Aggregate extracted bytes for an archive exceed `maxDecompressedArchiveBytes`.
    case archiveSizeLimitExceeded(fileName: String)
    /// Pre-flight JSON byte-size check failed (`maxRecipeJSONBytes`).
    case jsonSizeLimitExceeded(fileName: String)
}

public struct ThirdPartyArchiveEntry: Sendable, Equatable {
    public let fileName: String
    public let data: Data

    public init(fileName: String, data: Data) {
        self.fileName = fileName
        self.data = data
    }
}

public struct IngredientDraft: Sendable, Equatable {
    public let name: String
    public let amount: String
    public let unit: String
    public let order: Int

    public init(name: String, amount: String, unit: String = "", order: Int) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.order = order
    }
}

public enum DescriptionBlock: Sendable, Equatable {
    case paragraph(String)
    case heading(level: Int, String)
    case orderedListItem(String)
    /// Synthesized metadata signals — carry the raw value; the consumer
    /// (Native layer) is responsible for rendering a localized label.
    /// These cases intentionally hold no user-facing text.
    case prepTime(String)
    case cookTime(String)
    case durationMinutes(Int)
    case difficulty(String)
}

public struct ThirdPartyRecipeDraft: Sendable, Equatable {
    public var name: String
    public var servings: Int
    public var ingredients: [IngredientDraft]
    public var descriptionBlocks: [DescriptionBlock]
    public var originalRecipe: String?
    public var originalRecipeLink: String?
    public var imageData: Data?
    public var categoryLabels: [String]
    public var sourceFileName: String
    public var sourceFormat: ThirdPartyFormat

    public init(
        name: String,
        servings: Int,
        ingredients: [IngredientDraft],
        descriptionBlocks: [DescriptionBlock],
        originalRecipe: String? = nil,
        originalRecipeLink: String? = nil,
        imageData: Data? = nil,
        categoryLabels: [String] = [],
        sourceFileName: String,
        sourceFormat: ThirdPartyFormat
    ) {
        self.name = name
        self.servings = max(1, servings)
        self.ingredients = ingredients
        self.descriptionBlocks = descriptionBlocks
        self.originalRecipe = originalRecipe
        self.originalRecipeLink = originalRecipeLink
        self.imageData = imageData
        self.categoryLabels = categoryLabels
        self.sourceFileName = sourceFileName
        self.sourceFormat = sourceFormat
    }
}

public struct ThirdPartyImportResult: Sendable {
    public let importedRecipeIds: [String]
    public let failed: [(fileName: String, error: ThirdPartyImportError)]
    public let photosSkippedOffline: Int
    public let photosFailed: Int

    public init(
        importedRecipeIds: [String],
        failed: [(fileName: String, error: ThirdPartyImportError)],
        photosSkippedOffline: Int = 0,
        photosFailed: Int = 0
    ) {
        self.importedRecipeIds = importedRecipeIds
        self.failed = failed
        self.photosSkippedOffline = photosSkippedOffline
        self.photosFailed = photosFailed
    }
}

public enum ThirdPartyImportLimits {
    public static let maxRecipesPerImport = 500

    /// Unified 25 MB image cap — decimal MB, matches web
    /// `MAX_IMPORT_IMAGE_SIZE_BYTES`. Fixes review #63 (divergent constants).
    public static let maxImageBytes = 25_000_000

    /// Maximum decompressed bytes for a single archive entry (.paprikarecipe/.crumb).
    public static let maxDecompressedEntryBytes = 50 * 1_000_000

    /// Maximum aggregate decompressed bytes for a single archive (running total).
    public static let maxDecompressedArchiveBytes = 500 * 1_000_000

    /// Maximum decompressed bytes for a single Paprika gzip JSON.
    public static let maxGzipJSONBytes = 16 * 1_000_000

    /// Maximum JSON byte size before `JSONSerialization` pre-flight (defense-in-depth vs CPU-bombs).
    public static let maxRecipeJSONBytes = 16 * 1_000_000
}
