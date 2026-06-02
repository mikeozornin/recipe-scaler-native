import Foundation

/// Persists recipe nutrition view mode (web `localStorage` key `nutritionViewMode`).
enum NutritionViewModeStorage {
    private static let key = "nutritionViewMode"

    static func load() -> IngredientNutritionViewMode {
        guard let raw = UserDefaults.standard.string(forKey: key) else {
            return .per100g
        }
        return mode(from: raw) ?? .per100g
    }

    static func save(_ mode: IngredientNutritionViewMode) {
        UserDefaults.standard.set(storageValue(for: mode), forKey: key)
    }

    static func mode(from raw: String) -> IngredientNutritionViewMode? {
        switch raw {
        case "dish": return .dish
        case "per100g": return .per100g
        case "perServing": return .perServing
        case "scaled": return .scaled
        default: return nil
        }
    }

    static func storageValue(for mode: IngredientNutritionViewMode) -> String {
        switch mode {
        case .dish: return "dish"
        case .per100g: return "per100g"
        case .perServing: return "perServing"
        case .scaled: return "scaled"
        }
    }
}

/// Global KBJU visibility (web `nutritionEnabled` / Account «Show nutrition»).
enum NutritionSettings {
    static let globalEnabledKey = "showNutritionGlobal"

    static var isGlobalEnabled: Bool {
        (UserDefaults.standard.object(forKey: globalEnabledKey) as? Bool) ?? true
    }
}