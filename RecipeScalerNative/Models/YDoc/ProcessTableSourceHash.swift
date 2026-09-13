import CryptoKit
import Foundation

/// Port of web `canonicalizeProcessTableSource` / `hashProcessTableFromRecipe`.
/// Canonical JSON is built by hand so key order matches `JSON.stringify`.
enum ProcessTableSourceHash {
    struct Step: Equatable, Sendable {
        let index: Int
        let text: String
        let mentionedIngredientIds: [String]
    }

    static func hash(ingredients: [IngredientData], descriptionHtml: String) -> String {
        compute(ingredients: hashIngredients(from: ingredients), steps: extractSteps(from: descriptionHtml).map(\.text))
    }

    static func compute(ingredients: [HashIngredient], steps: [String]) -> String {
        sha256Hex(canonicalize(ingredients: ingredients, steps: steps))
    }

    struct HashIngredient: Equatable, Sendable {
        let id: String
        let originalAmount: Double?
        let unit: String
    }

    static func hashIngredients(from ingredients: [IngredientData]) -> [HashIngredient] {
        ingredients.compactMap { row in
            guard !row.isSeparator, !row.id.isEmpty else { return nil }
            return HashIngredient(
                id: row.id,
                originalAmount: finiteAmount(row.originalAmount),
                unit: row.unit
            )
        }
    }

    static func canonicalize(ingredients: [HashIngredient], steps: [String]) -> String {
        let ingredientObjects = ingredients.map { row in
            let amountJSON = jsonNumber(row.originalAmount)
            return "{\"id\":\(jsonString(row.id)),\"originalAmount\":\(amountJSON),\"unit\":\(jsonString(row.unit))}"
        }
        let stepObjects = steps.map { jsonString($0) }
        return "{\"ingredients\":[\(ingredientObjects.joined(separator: ","))],\"steps\":[\(stepObjects.joined(separator: ","))]}"
    }

    static func extractSteps(from html: String) -> [Step] {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let fromList = extractBlocks(from: trimmed, tag: "li")
        if !fromList.isEmpty { return fromList }
        return extractBlocks(from: trimmed, tag: "p")
    }

    private static func extractBlocks(from html: String, tag: String) -> [Step] {
        let pattern = "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var items: [Step] = []
        var index = 0
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let inner = ns.substring(with: match.range(at: 1))
            let mentioned = extractIngredientIds(from: inner)
            let text = decodeBasicEntities(stripTags(inner))
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            items.append(Step(index: index, text: text, mentionedIngredientIds: mentioned))
            index += 1
        }
        return items
    }

    private static func extractIngredientIds(from inner: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"data-ingredient-id=["']([^"']+)["']"#,
            options: []
        ) else { return [] }
        let ns = inner as NSString
        let matches = regex.matches(in: inner, range: NSRange(location: 0, length: ns.length))
        var seen = Set<String>()
        var ordered: [String] = []
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let id = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        return ordered
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    static func decodeBasicEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func finiteAmount(_ raw: String) -> Double? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func jsonString(_ value: String) -> String {
        jsonFragment([value])
    }

    private static func jsonNumber(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "null" }
        return jsonFragment([value])
    }

    /// `JSONSerialization` of a one-element array, then drop `[` `]` — matches JS `JSON.stringify` for strings/numbers.
    private static func jsonFragment(_ array: [Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: array, options: []),
              var text = String(data: data, encoding: .utf8),
              text.count >= 2
        else {
            return "null"
        }
        text.removeFirst()
        text.removeLast()
        return text
    }

    private static func sha256Hex(_ utf8: String) -> String {
        let digest = SHA256.hash(data: Data(utf8.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
