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
    static func canEdit(version: String?) -> Bool {
        RecipeData.RecipeVersion.detect(version) == .v3
    }

    static func canEdit(recipe: RecipeData) -> Bool {
        canEdit(version: recipe.version)
    }
}