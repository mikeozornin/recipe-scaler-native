//
//  PaprikaRecipeParser.swift
//  RecipeScalerCore
//

import Foundation

public enum PaprikaRecipeParser {
    private static let stepNumberPattern = try! NSRegularExpression(
        pattern: #"^\d+[\.\)]\s*"#
    )

    public static func parse(
        gzipData: Data,
        fileName: String,
        sourceFormat: ThirdPartyFormat
    ) throws -> ThirdPartyRecipeDraft {
        let jsonData: Data
        do {
            jsonData = try Gunzip.decompress(
                gzipData,
                fileName: fileName,
                maxOutputBytes: ThirdPartyImportLimits.maxGzipJSONBytes
            )
        } catch let error as ThirdPartyImportError {
            throw error
        } catch {
            throw ThirdPartyImportError.gzipFailed(fileName: fileName)
        }

        return try parse(jsonData: jsonData, fileName: fileName, sourceFormat: sourceFormat)
    }

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

        guard object["name"] != nil || object["ingredients"] != nil else {
            throw ThirdPartyImportError.invalidJSON(fileName: fileName)
        }

        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let servings = parseServings(object["servings"])
        let ingredients = parseIngredients(object["ingredients"])
        let directionBlocks = parseDirections(object["directions"])
        var descriptionBlocks = parseMetadataParagraphs(from: object)
        if let notes = trimmedString(object["notes"]) {
            descriptionBlocks.append(.paragraph(notes))
        }
        descriptionBlocks.append(contentsOf: directionBlocks)

        let imageData = decodePhotoData(object["photo_data"], fileName: fileName)

        return ThirdPartyRecipeDraft(
            name: name,
            servings: servings,
            ingredients: ingredients,
            descriptionBlocks: descriptionBlocks,
            originalRecipe: trimmedString(object["source"]),
            originalRecipeLink: trimmedString(object["source_url"]),
            imageData: imageData,
            categoryLabels: object["categories"] as? [String] ?? [],
            sourceFileName: fileName,
            sourceFormat: sourceFormat
        )
    }

    private static func parseServings(_ value: Any?) -> Int {
        if let number = value as? NSNumber {
            return max(1, number.intValue)
        }
        let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return 1 }
        if let first = text.split(whereSeparator: { !$0.isNumber && $0 != "-" }).first,
           let parsed = Int(first) {
            return max(1, parsed)
        }
        let digitPrefix = text.prefix(while: { $0.isNumber })
        if !digitPrefix.isEmpty, let parsed = Int(digitPrefix) {
            return max(1, parsed)
        }
        return 1
    }

    private static func parseIngredients(_ value: Any?) -> [IngredientDraft] {
        let lines: [String]
        if let string = value as? String {
            lines = string
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0) }
        } else {
            lines = []
        }

        var result: [IngredientDraft] = []
        var order = 1
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let split = PaprikaIngredientSplitter.split(line: trimmed)
            let parsedAmount = ThirdPartyIngredientAmountSplitter.split(split.amount)
            result.append(
                IngredientDraft(
                    name: split.name,
                    amount: parsedAmount.amount,
                    unit: parsedAmount.unit,
                    order: order
                )
            )
            order += 1
        }
        return result
    }

    private static func parseMetadataParagraphs(from object: [String: Any]) -> [DescriptionBlock] {
        var blocks: [DescriptionBlock] = []
        if let prep = trimmedString(object["prep_time"]) {
            blocks.append(.prepTime(prep))
        }
        if let cook = trimmedString(object["cook_time"]) {
            blocks.append(.cookTime(cook))
        }
        return blocks
    }

    private static func parseDirections(_ value: Any?) -> [DescriptionBlock] {
        guard let string = value as? String else { return [] }
        return string
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { stripStepNumber(from: $0) }
            .map { DescriptionBlock.orderedListItem($0) }
    }

    private static func stripStepNumber(from line: String) -> String {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let stripped = stepNumberPattern.stringByReplacingMatches(
            in: line,
            range: range,
            withTemplate: ""
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodePhotoData(_ value: Any?, fileName: String) -> Data? {
        guard var base64 = value as? String, !base64.isEmpty else { return nil }
        base64 = base64.replacingOccurrences(of: "\\/", with: "/")
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        guard data.count <= ThirdPartyImportLimits.maxImageBytes else { return nil }
        return data
    }

    private static func trimmedString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
