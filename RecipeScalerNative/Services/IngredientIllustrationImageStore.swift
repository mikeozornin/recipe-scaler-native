import RecipeScalerCore
import SwiftUI
import UIKit

enum IngredientIllustrationImageStore {
    private static let subdirectory = "IngredientIllustrations"
    private static let imageCache = NSCache<NSString, UIImage>()

    static func uiImage(for illustrationId: String) -> UIImage? {
        let trimmed = illustrationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard IngredientIllustrationCatalog.shared.contains(id: trimmed) else { return nil }

        let cacheKey = trimmed as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        guard let url = Bundle.main.url(
            forResource: trimmed,
            withExtension: "jpg",
            subdirectory: subdirectory
        ),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else { return nil }

        imageCache.setObject(image, forKey: cacheKey)
        return image
    }
}