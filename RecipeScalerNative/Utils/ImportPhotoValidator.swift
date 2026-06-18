//
//  ImportPhotoValidator.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore
import UniformTypeIdentifiers

/// Mirrors `recipe-scaler-web/recipe-scaler/src/utils/import-photo.ts` and shared limits
/// from `recipe-scaler-web/shared/constants/import.ts`.
enum ImportPhotoValidator {

    static let maxImages = 8
    /// Unified 25 MB image cap. Mirrors `ThirdPartyImportLimits.maxImageBytes`
    /// (decimal MB, matches web `MAX_IMPORT_IMAGE_SIZE_BYTES`).
    static let maxImageBytes = ThirdPartyImportLimits.maxImageBytes

    static let supportedUTTypes: [UTType] = [.jpeg, .png, .webP, .heic]

    enum ValidationError: LocalizedError {
        case empty
        case tooMany
        case tooLarge
        case invalidType

        var localizationKey: String {
            switch self {
            case .empty: return "import.error-photos-empty"
            case .tooMany: return "import.error-too-many-photos"
            case .tooLarge: return "import.error-photo-too-large"
            case .invalidType: return "import.error-photo-invalid-type"
            }
        }

        var errorDescription: String? {
            switch self {
            case .tooMany:
                return Bundle.appPluralizedString(
                    key: "import.error-too-many-photos",
                    count: ImportPhotoValidator.maxImages
                )
            default:
                return Bundle.currentLocalizedString(localizationKey)
            }
        }
    }

    /// Validate count, size, and type of the picked photos.
    /// PhotosPicker already enforces count + type, but we keep this as a defence-in-depth
    /// (e.g. against drag-and-drop or programmatic selection in the future).
    static func validate(items: [ImportPhotoItem]) -> ValidationError? {
        if items.isEmpty { return .empty }
        if items.count > maxImages { return .tooMany }

        for item in items {
            if item.byteCount > maxImageBytes { return .tooLarge }
            if !isSupported(item) { return .invalidType }
        }

        return nil
    }

    private static func isSupported(_ item: ImportPhotoItem) -> Bool {
        // UTType-conformance check covers the MIME / UTI cases the web filters on:
        // image/jpeg, image/png, image/webp, image/heic, image/heif.
        if let utType = item.utType {
            for supported in supportedUTTypes where utType.conforms(to: supported) {
                return true
            }
        }
        return false
    }
}

struct ImportPhotoItem: Identifiable {
    let id = UUID()
    let data: Data
    let fileName: String
    let utType: UTType?

    var byteCount: Int { data.count }

    init(data: Data, fileName: String = "image.jpg", utType: UTType? = nil) {
        self.data = data
        self.fileName = fileName
        self.utType = utType ?? UTType(filenameExtension: (fileName as NSString).pathExtension) ?? .jpeg
    }
}
