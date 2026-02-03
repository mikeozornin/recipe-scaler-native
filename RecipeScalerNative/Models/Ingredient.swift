//
//  Ingredient.swift
//  RecipeScalerNative
//
//

import Foundation
import SwiftData

@Model
final class Ingredient {
    @Attribute(.unique) var id: String
    var name: String
    var originalAmount: Double?
    var unit: String
    var order: Int
    var isSeparator: Bool

    // Nutrition (optional)
    var calories: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?
    var weight: Double? // Weight in grams

    // Relationship
    var recipe: Recipe?

    // Computed - scaled amount
    func scaledAmount(scaleFactor: Double) -> Double? {
        guard let originalAmount = originalAmount else { return nil }
        return originalAmount * scaleFactor
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        originalAmount: Double? = nil,
        unit: String = "",
        order: Int = 0,
        isSeparator: Bool = false,
        calories: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        carbs: Double? = nil,
        weight: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.originalAmount = originalAmount
        self.unit = unit
        self.order = order
        self.isSeparator = isSeparator
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.weight = weight
    }
}

// MARK: - Codable for API
extension Ingredient {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case originalAmount
        case unit
        case order
        case isSeparator
        case calories
        case protein
        case fat
        case carbs
        case weight
    }
}
