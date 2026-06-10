import Foundation

enum RecipeEditError: Error, LocalizedError {
    case legacyFormatReadOnly
    case documentNotLoaded
    case invalidServings

    var errorDescription: String? {
        switch self {
        case .legacyFormatReadOnly:
            return String(localized: "edit.error.legacyReadOnly")
        case .documentNotLoaded:
            return String(localized: "edit.error.documentNotLoaded")
        case .invalidServings:
            return String(localized: "edit.error.invalidServings")
        }
    }
}

enum RecipeEditPolicy {
    /// Master switch for native v3 field/ingredient editing (v1/v2 stay read-only via `supportsEditFormat`).
    static let nativeEditingEnabled = true

    /// v3 format supports editing when `nativeEditingEnabled` is on (not v1/v2).
    static func supportsEditFormat(version: String?) -> Bool {
        RecipeData.RecipeVersion.detect(version) == .v3
    }

    static func canEdit(version: String?) -> Bool {
        nativeEditingEnabled && supportsEditFormat(version: version)
    }

    static func canEdit(recipe: RecipeData) -> Bool {
        canEdit(version: recipe.version)
    }
}