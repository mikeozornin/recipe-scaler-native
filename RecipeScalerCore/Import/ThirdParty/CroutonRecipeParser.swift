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
        // #32: pre-flight JSON byte cap — defense-in-depth against CPU/memory bombs.
        guard jsonData.count <= ThirdPartyImportLimits.maxRecipeJSONBytes else {
            throw ThirdPartyImportError.jsonSizeLimitExceeded(fileName: fileName)
        }

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
        let photo = decodeFirstImage(object["images"], fileName: fileName)

        return ThirdPartyRecipeDraft(
            name: name,
            servings: servings,
            ingredients: ingredients,
            descriptionBlocks: descriptionBlocks,
            imageData: photo.data,
            categoryLabels: object["tags"] as? [String] ?? [],
            sourceFileName: fileName,
            sourceFormat: sourceFormat,
            imageOversized: photo.oversized
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

        // MIK-145 [review #62]: do not canonicalize quantityType to short
        // suffixes. Store the raw value lowercased — the source format is
        // preserved verbatim (no `GRAMS → g`, no `PIECES → ""` collapse).
        let rawType = (quantity["quantityType"] as? String) ?? ""
        let unit = rawType.lowercased()

        // TP14 [review #14]: guard against precondition trap on out-of-Int64
        // Double (e.g. 1e20) and non-finite values (NaN/Infinity) which can slip
        // through NSNumber bridges. Int(exactly:) returns nil on overflow.
        let amountString: String
        if amountValue.isNaN || amountValue.isInfinite {
            amountString = ""
        } else if let intValue = Int(exactly: amountValue) {
            amountString = String(intValue)
        } else {
            amountString = String(amountValue)
        }
        return (amountString, unit)
    }

    private static func parseDurationParagraphs(from object: [String: Any]) -> [DescriptionBlock] {
        var blocks: [DescriptionBlock] = []
        for key in ["duration", "cookingDuration"] {
            let minutes: Int?
            if let number = object[key] as? NSNumber, number.intValue > 0 {
                minutes = number.intValue
            } else if let value = object[key] as? Int, value > 0 {
                minutes = value
            } else {
                minutes = nil
            }
            if let mins = minutes {
                blocks.append(.durationMinutes(mins))
                break
            }
            // Free-form string duration (e.g. "overnight") — pass through verbatim.
            if let text = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                blocks.append(.paragraph(text))
                break
            }
        }
        if let difficulty = (object["rawDifficulty"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !difficulty.isEmpty {
            blocks.append(.difficulty(difficulty))
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

    private static func decodeFirstImage(_ value: Any?, fileName: String) -> (data: Data?, oversized: Bool) {
        guard let images = value as? [String], let base64 = images.first, !base64.isEmpty else {
            return (nil, false)
        }
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            return (nil, false)
        }
        // MIK-119 [review #35]: distinguish "no image" from "image too large" so
        // the import service can surface a dedicated warning instead of dropping
        // the image silently.
        //
        // NOTE: under current limits this branch is unreachable through a valid
        // JSON payload — `maxRecipeJSONBytes` (16 MB) < `maxImageBytes` (25 MB),
        // so any base64 image larger than 25 MB forces the surrounding JSON past
        // the pre-flight cap and is rejected earlier with `.jsonSizeLimitExceeded`.
        // The guard is kept as defense-in-depth in case the limits ever diverge.
        guard data.count <= ThirdPartyImportLimits.maxImageBytes else { return (nil, true) }
        return (data, false)
    }
}
