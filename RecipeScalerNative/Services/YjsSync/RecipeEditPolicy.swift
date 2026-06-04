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
    // TEMPORARY: native v3 editing off while ingredients edit grid is in flux.
    // Set to `true` to restore pencil / edit mode / Y.Doc writes on v3.
    static let nativeEditingEnabled = false

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