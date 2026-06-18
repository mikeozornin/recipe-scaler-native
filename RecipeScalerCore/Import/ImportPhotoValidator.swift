//
//  ImportPhotoValidator.swift
//  RecipeScalerCore
//

import Foundation
import UniformTypeIdentifiers

public struct ImportPhotoItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let data: Data
    public let fileName: String
    public let utType: UTType?

    /// Primary init — explicit id (for tests / reconstruction).
    public init(id: UUID = UUID(), data: Data, fileName: String, utType: UTType?) {
        self.id = id
        self.data = data
        self.fileName = fileName
        self.utType = utType
    }

    /// Convenience init mirroring the former Native helper — defaults
    /// `fileName` to `"image.jpg"` and infers `utType` from the extension.
    public init(data: Data, fileName: String = "image.jpg", utType: UTType? = nil) {
        self.id = UUID()
        self.data = data
        self.fileName = fileName
        self.utType = utType ?? UTType(filenameExtension: (fileName as NSString).pathExtension) ?? .jpeg
    }

    public var byteCount: Int { data.count }

    // Equatable — compare by data + fileName only (id and UTType excluded).
    public static func == (lhs: ImportPhotoItem, rhs: ImportPhotoItem) -> Bool {
        lhs.data == rhs.data && lhs.fileName == rhs.fileName
    }
}

public enum ImportPhotoValidator {

    public static let maxImages = 8
    /// Same as web `MAX_IMPORT_RECIPES`.
    public static let maxRecipes = 25
    /// Unified 25 MB image cap. Mirrors `ThirdPartyImportLimits.maxImageBytes`
    /// (decimal MB, matches web `MAX_IMPORT_IMAGE_SIZE_BYTES`).
    public static let maxImageBytes = ThirdPartyImportLimits.maxImageBytes

    public static let supportedUTTypes: [UTType] = [.jpeg, .png, .webP, .heic]

    public enum ValidationError: LocalizedError {
        case empty
        case tooMany(count: Int)
        case tooLarge(name: String?, size: Int)
        case unsupportedType(name: String?)

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "import.error-photos-empty"
            case .tooMany(let count):
                return "import.error-too-many-photos:\(count)"
            case .tooLarge(let name, let size):
                return "import.error-photo-too-large:\(name ?? "?"):\(size)"
            case .unsupportedType(let name):
                return "import.error-photo-invalid-type:\(name ?? "?")"
            }
        }
    }

    /// Returns `nil` when valid, otherwise the first encountered `ValidationError`.
    public static func validate(items: [ImportPhotoItem]) -> ValidationError? {
        guard !items.isEmpty else { return .empty }
        guard items.count <= maxImages else { return .tooMany(count: items.count) }
        for item in items {
            if item.data.count > maxImageBytes {
                return .tooLarge(name: item.fileName, size: item.data.count)
            }
            if let ut = item.utType {
                let isSupported = supportedUTTypes.contains { ut.conforms(to: $0) }
                if !isSupported {
                    return .unsupportedType(name: item.fileName)
                }
            }
        }
        return nil
    }
}
