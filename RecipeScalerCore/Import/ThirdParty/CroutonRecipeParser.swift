//
//  CroutonRecipeParser.swift
//  RecipeScalerCore
//

import Foundation

public enum CroutonRecipeParser {
    public static func parse(
        jsonData: Data,
        fileName: String,
        sourceFormat: ThirdPartyFormat
    ) throws -> ThirdPartyRecipeDraft {
        let object: [String: Any]
        do {
            object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
        } catch {
            throw ThirdPartyImportError.invalidJSON(fileName: fileName)
        }

        guard object["uuid"] is String || object["ingredients"] is [[String: Any]] else {
            throw ThirdPartyImportError.invalidJSON(fileName: fileName)
        }

        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let servings: Int = {
            if let number = object["serves"] as? NSNumber {
                return max(1, number.intValue)
            }
            if let value = object["serves"] as? Int {
                return max(1, value)
            }
            return 1
        }()

        let ingredients = parseIngredients(object["ingredients"])
        var descriptionBlocks = parseDurationParagraphs(from: object)
        descriptionBlocks.append(contentsOf: parseSteps(object["steps"]))
        let imageData = decodeFirstImage(object["images"], fileName: fileName)

        return ThirdPartyRecipeDraft(
            name: name,
            servings: servings,
            ingredients: ingredients,
            descriptionBlocks: descriptionBlocks,
            imageData: imageData,
            categoryLabels: object["tags"] as? [String] ?? [],
            sourceFileName: fileName,
            sourceFormat: sourceFormat
        )
    }

    private static func parseIngredients(_ value: Any?) -> [IngredientDraft] {
        guard let array = value as? [[String: Any]] else { return [] }
        let sorted = array.sorted {
            let left = ($0["order"] as? NSNumber)?.intValue ?? ($0["order"] as? Int) ?? 0
            let right = ($1["order"] as? NSNumber)?.intValue ?? ($1["order"] as? Int) ?? 0
            return left < right
        }

        var result: [IngredientDraft] = []
        for (index, item) in sorted.enumerated() {
            let ingredient = item["ingredient"] as? [String: Any] ?? [:]
            let name = (ingredient["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            let quantity = parseQuantity(item["quantity"] as? [String: Any])
            let order = (item["order"] as? NSNumber)?.intValue ?? (item["order"] as? Int) ?? index
            result.append(
                IngredientDraft(
                    name: name,
                    amount: quantity.amount,
                    unit: quantity.unit,
                    order: order + 1
                )
            )
        }
        return result
    }

    private static func parseQuantity(_ quantity: [String: Any]?) -> (amount: String, unit: String) {
        guard let quantity else { return ("", "") }
        let amountValue: Double? = {
            if let number = quantity["amount"] as? NSNumber {
                return number.doubleValue
            }
            if let value = quantity["amount"] as? Double {
                return value
            }
            return nil
        }()
        guard let amountValue else { return ("", "") }

        let type = (quantity["quantityType"] as? String)?.uppercased() ?? ""
        let unit: String
        switch type {
        case "GRAMS": unit = "g"
        case "KILOGRAMS": unit = "kg"
        case "MILLILITERS": unit = "ml"
        case "LITERS": unit = "l"
        case "OUNCES": unit = "oz"
        case "POUNDS": unit = "lb"
        case "CUPS": unit = "cup"
        case "CUP": unit = "cup"
        case "TABLESPOONS": unit = "tbsp"
        case "TABLESPOON": unit = "tbsp"
        case "TEASPOONS": unit = "tsp"
        case "TEASPOON": unit = "tsp"
        case "PIECES": unit = ""
        case "ITEM": unit = ""
        default: unit = type.isEmpty ? "" : type.lowercased()
        }

        let amountString = amountValue.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(amountValue))
            : String(amountValue)
        return (amountString, unit)
    }

    private static func parseDurationParagraphs(from object: [String: Any]) -> [DescriptionBlock] {
        var blocks: [DescriptionBlock] = []
        for key in ["duration", "cookingDuration"] {
            let trimmed: String?
            if let number = object[key] as? NSNumber, number.intValue > 0 {
                trimmed = "\(number.intValue) min"
            } else if let value = object[key] as? Int, value > 0 {
                trimmed = "\(value) min"
            } else if let text = object[key] as? String {
                trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                trimmed = nil
            }
            if let text = trimmed, !text.isEmpty {
                blocks.append(.paragraph(text))
                break
            }
        }
        if let difficulty = (object["rawDifficulty"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !difficulty.isEmpty {
            blocks.append(.paragraph(difficulty))
        }
        return blocks
    }

    private static func parseSteps(_ value: Any?) -> [DescriptionBlock] {
        guard let array = value as? [[String: Any]] else { return [] }
        let sorted = array.sorted {
            let left = ($0["order"] as? NSNumber)?.intValue ?? ($0["order"] as? Int) ?? 0
            let right = ($1["order"] as? NSNumber)?.intValue ?? ($1["order"] as? Int) ?? 0
            return left < right
        }

        return sorted.compactMap { item -> DescriptionBlock? in
            let text = (item["step"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            let isSection = item["isSection"] as? Bool ?? false
            if isSection {
                return .heading(level: 3, text)
            }
            return .orderedListItem(text)
        }
    }

    private static func decodeFirstImage(_ value: Any?, fileName: String) -> Data? {
        guard let images = value as? [String], let base64 = images.first, !base64.isEmpty else {
            return nil
        }
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        guard data.count <= ThirdPartyImportLimits.maxImageBytes else { return nil }
        return data
    }
}
