//
//  Recipe.swift
//  RecipeScalerNative
//
//

import Foundation
import SwiftData

@Model
final class Recipe {
    @Attribute(.unique) var id: String
    var name: String
    var recipeDescription: String?
    var originalRecipeLink: String?
    var color: String?
    var scaleFactor: Double
    var originalRecipe: String?
    var imageUrl: String?
    var detailHtml: String?
    var detailScaleFactor: Double?
    var detailEtag: String?
    var detailLastModified: String?
    var detailFetchedAt: Date?
    var imageLocalPath: String?
    var imagePreviewLocalPath: String?
    var imageEtag: String?
    var imagePreviewEtag: String?
    var imageLastModified: String?
    var imagePreviewLastModified: String?
    var createdAt: Date
    var updatedAt: Date
    var userId: String?
    var isPublic: Bool

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe)
    var ingredients: [Ingredient]

    // Computed
    var hasSteps: Bool {
        // Will be determined from description content
        !(recipeDescription?.isEmpty ?? true)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        recipeDescription: String? = nil,
        originalRecipeLink: String? = nil,
        color: String? = nil,
        scaleFactor: Double = 1.0,
        originalRecipe: String? = nil,
        imageUrl: String? = nil,
        detailHtml: String? = nil,
        detailScaleFactor: Double? = 1.0,
        detailEtag: String? = nil,
        detailLastModified: String? = nil,
        detailFetchedAt: Date? = nil,
        imageLocalPath: String? = nil,
        imagePreviewLocalPath: String? = nil,
        imageEtag: String? = nil,
        imagePreviewEtag: String? = nil,
        imageLastModified: String? = nil,
        imagePreviewLastModified: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        userId: String? = nil,
        isPublic: Bool = false,
        ingredients: [Ingredient] = []
    ) {
        self.id = id
        self.name = name
        self.recipeDescription = recipeDescription
        self.originalRecipeLink = originalRecipeLink
        self.color = color
        self.scaleFactor = scaleFactor
        self.originalRecipe = originalRecipe
        self.imageUrl = imageUrl
        self.detailHtml = detailHtml
        self.detailScaleFactor = detailScaleFactor
        self.detailEtag = detailEtag
        self.detailLastModified = detailLastModified
        self.detailFetchedAt = detailFetchedAt
        self.imageLocalPath = imageLocalPath
        self.imagePreviewLocalPath = imagePreviewLocalPath
        self.imageEtag = imageEtag
        self.imagePreviewEtag = imagePreviewEtag
        self.imageLastModified = imageLastModified
        self.imagePreviewLastModified = imagePreviewLastModified
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.isPublic = isPublic
        self.ingredients = ingredients
    }
}

// MARK: - Codable for API
extension Recipe {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case recipeDescription = "description"
        case originalRecipeLink = "original_recipe_link"
        case color
        case scaleFactor = "scale_factor"
        case originalRecipe = "original_recipe"
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
        case isPublic = "is_public"
        case ingredients
    }
}
