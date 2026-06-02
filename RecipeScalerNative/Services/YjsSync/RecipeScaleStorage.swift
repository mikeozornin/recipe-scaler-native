import Foundation

/// Per-recipe scale multiplier (web `localStorage` key `recipe-scale:{id}`).
/// Not synced via Yjs — only `recipe.servings` is persisted in the document.
enum RecipeScaleStorage {
    private struct Payload: Codable {
        let scaleFactor: Double
    }

    private static func storageKey(recipeId: String) -> String {
        "recipe-scale:\(recipeId)"
    }

    static func loadScaleFactor(recipeId: String) -> Double {
        let key = storageKey(recipeId: recipeId)
        if let data = UserDefaults.standard.data(forKey: key),
           let payload = try? JSONDecoder().decode(Payload.self, from: data),
           payload.scaleFactor > 0 {
            return payload.scaleFactor
        }
        if let raw = UserDefaults.standard.object(forKey: key) as? Double, raw > 0 {
            saveScaleFactor(recipeId: recipeId, scaleFactor: raw)
            return raw
        }
        if let text = UserDefaults.standard.string(forKey: key),
           let value = Double(text), value > 0 {
            saveScaleFactor(recipeId: recipeId, scaleFactor: value)
            return value
        }
        return 1
    }

    static func saveScaleFactor(recipeId: String, scaleFactor: Double) {
        let normalized = max(scaleFactor, 0.000_1)
        let payload = Payload(scaleFactor: normalized)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(recipeId: recipeId))
    }
}