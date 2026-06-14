import Foundation
import SwiftUI
import UIKit

/// Recipe search toolkit: tokenization, field matching, snippets, highlighting.
///
/// Tokenization follows the project search rules
/// (https://mikeozornin.ru/blog/all/search-ui-tricks/):
/// - case-insensitive, diacritic-insensitive (NFKD + strip 0300–036F + lowercase)
/// - whitespace AND between tokens
/// - quoted phrases (`"beef broth" soup` → ["beef broth", "soup"])
/// - search from the first character, no minimum length
///
/// Field matching, snippets and highlighting mirror the web's `recipe-list`
/// behavior: match by name (fast path) → ingredients → description; render the
/// matched ingredient or a ~250-char description window under the title with
/// highlighted occurrences (like Mail.app).
enum RecipeSearchUtils {
    private static let combiningDiacritics = CharacterSet(charactersIn: "\u{0300}"..."\u{036F}")

    // MARK: - Query normalization (case- and diacritic-insensitive)

    static func normalizeForSearch(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespaces)
            .map(normalizeSearchCharacter)
            .joined()
    }

    /// Latin text: NFKD + strip combining marks + lowercase.
    /// Cyrillic: lowercase only — NFKD decomposes `й` into `и` + breve and breaks search.
    private static func normalizeSearchCharacter(_ character: Character) -> String {
        if isCyrillicCharacter(character) {
            return String(character).lowercased()
        }
        return String(character)
            .decomposedStringWithCanonicalMapping
            .unicodeScalars
            .filter { !combiningDiacritics.contains($0) }
            .map { String($0).lowercased() }
            .joined()
    }

    private static func isCyrillicScalar(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x0400 ... 0x04FF).contains(value) || (0x0500 ... 0x052F).contains(value)
    }

    private static func isCyrillicCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains(where: isCyrillicScalar)
    }

    /// Trim, split by whitespace into independent AND tokens, honor quoted phrases.
    static func tokenizeQuery(_ query: String) -> [String] {
        var tokens: [String] = []
        var remaining = query[...]

        while !remaining.isEmpty {
            remaining = Substring(remaining.trimmingCharacters(in: .whitespaces))
            if remaining.isEmpty { break }

            if remaining.hasPrefix("\"") {
                remaining = remaining.dropFirst()
                if let end = remaining.range(of: "\"") {
                    let phrase = String(remaining[..<end.lowerBound])
                    if !phrase.isEmpty {
                        tokens.append(normalizeForSearch(phrase))
                    }
                    remaining = remaining[end.upperBound...]
                } else {
                    let phrase = String(remaining)
                    tokens.append(normalizeForSearch(phrase))
                    break
                }
            } else {
                if let space = remaining.range(of: " ") {
                    let word = String(remaining[..<space.lowerBound])
                    tokens.append(normalizeForSearch(word))
                    remaining = remaining[space.upperBound...]
                } else {
                    tokens.append(normalizeForSearch(String(remaining)))
                    break
                }
            }
        }
        return tokens
    }

    // MARK: - Matching

    /// Fast path: every token must occur in the normalized name.
    /// Convenience overload that normalizes the name on each call — prefer the
    /// `matchesName(normalized:tokens:)` variant when the caller can cache the
    /// normalized form.
    static func matchesName(_ name: String, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        return matchesName(normalized: normalizeForSearch(name), tokens: tokens)
    }

    /// Fast path variant for cached normalized names. Avoids re-running NFKD on
    /// the same name across re-renders.
    static func matchesName(normalized: String, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { normalized.contains($0) }
    }

    /// Full-text fallback: ingredients or description plain text.
    static func matchesRecipeContent(_ recipe: RecipeData, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        if findIngredientMatch(in: recipe, tokens: tokens) != nil { return true }
        return findDescriptionMatch(in: recipe, tokens: tokens) != nil
    }

    /// First ingredient whose normalized name contains every token.
    static func findIngredientMatch(in recipe: RecipeData, tokens: [String]) -> IngredientData? {
        for ingredient in recipe.ingredients where !ingredient.isSeparator {
            let normalized = normalizeForSearch(ingredient.name)
            guard !normalized.isEmpty else { continue }
            if tokens.allSatisfy({ normalized.contains($0) }) {
                return ingredient
            }
        }
        return nil
    }

    /// Description plain text where every token occurs (AND), with the earliest
    /// match index used to anchor the snippet window.
    static func findDescriptionMatch(in recipe: RecipeData, tokens: [String]) -> (text: String, matchIndex: Int)? {
        let plain = plainText(fromDescriptionHTML: recipe.description)
        guard !plain.isEmpty else { return nil }

        let normalized = normalizeForSearch(plain)
        var checks: [(found: Bool, index: Int)] = []
        checks.reserveCapacity(tokens.count)

        for token in tokens {
            let index = (normalized as NSString).range(of: token).location
            checks.append((index != NSNotFound, index == NSNotFound ? 0 : index))
        }

        guard checks.allSatisfy(\.found) else { return nil }
        let firstMatchIndex = checks.map(\.index).min() ?? 0
        return (plain, firstMatchIndex)
    }

    // MARK: - Snippets (ingredient name or description window)

    /// Returns the snippet shown under the title when search hit content (not name).
    /// - Ingredients: `"<name>, <original amount>"` when amount is present.
    /// - Description: ~250-char window anchored at the first match, with `…` ellipses.
    static func snippet(for recipe: RecipeData, tokens: [String], matchesNameOnly: Bool) -> String? {
        guard !matchesNameOnly, !tokens.isEmpty else { return nil }

        if let ingredient = findIngredientMatch(in: recipe, tokens: tokens) {
            var parts: [String] = []
            if !ingredient.name.isEmpty { parts.append(ingredient.name) }
            if ingredient.hasQuantity, !ingredient.originalAmount.isEmpty {
                parts.append(ingredient.originalAmount)
            }
            return parts.joined(separator: ", ")
        }

        if let descriptionMatch = findDescriptionMatch(in: recipe, tokens: tokens) {
            let originalIndex = originalCharacterIndex(
                in: descriptionMatch.text,
                normalizedIndex: descriptionMatch.matchIndex
            )
            return snippetWindow(in: descriptionMatch.text, matchIndex: originalIndex)
        }

        return nil
    }

    /// Maps a normalized-text character index back to the original-text index,
    /// so the snippet window is anchored correctly when diacritics were stripped.
    private static func originalCharacterIndex(in text: String, normalizedIndex: Int) -> Int {
        let mapping = buildNormalizedWithMap(text)
        guard !mapping.map.isEmpty else { return 0 }
        let clamped = min(max(normalizedIndex, 0), mapping.map.count - 1)
        return mapping.map[clamped]
    }

    private static func snippetWindow(in text: String, matchIndex: Int) -> String {
        let snippetLength = 250
        let matchPositionInSnippet = Int(Double(snippetLength) * 0.3)

        var start = max(0, matchIndex - matchPositionInSnippet)
        var end = min(text.count, start + snippetLength)

        let textEndIndex = text.endIndex
        let matchCharIndex = text.index(text.startIndex, offsetBy: min(matchIndex, text.count), limitedBy: textEndIndex) ?? text.startIndex
        let tailLength = text.distance(from: matchCharIndex, to: textEndIndex)
        if tailLength < Int(Double(snippetLength) * 0.2) {
            end = min(text.count, matchIndex + Int(Double(snippetLength) * 0.2))
            start = max(0, end - snippetLength)
        }

        var startIndex = text.index(text.startIndex, offsetBy: min(start, text.count), limitedBy: textEndIndex) ?? text.startIndex
        var endIndex = text.index(text.startIndex, offsetBy: min(end, text.count), limitedBy: textEndIndex) ?? textEndIndex

        // Snap to word boundaries within a small slack window.
        if start > 0, let spaceRange = text[..<startIndex].range(of: " ", options: .backwards) {
            let spaceDistance = text.distance(from: text.startIndex, to: spaceRange.upperBound)
            if start - spaceDistance <= 20 {
                startIndex = spaceRange.upperBound
            }
        }
        if end < text.count, let spaceRange = text[endIndex...].range(of: " ") {
            let spaceDistance = text.distance(from: endIndex, to: spaceRange.upperBound)
            if spaceDistance <= 20 {
                endIndex = spaceRange.upperBound
            }
        }

        var snippet = String(text[startIndex..<endIndex])
        if start > 0 { snippet = "…" + snippet }
        if end < text.count { snippet += "…" }
        return snippet
    }

    // MARK: - Highlighting (Mail.app-style yellow background)

    static var highlightBackgroundColor: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.68, green: 0.55, blue: 0.02, alpha: 1)
            }
            return UIColor(red: 0.99, green: 0.92, blue: 0.25, alpha: 1)
        }
    }

    /// Renders `text` with all token occurrences highlighted.
    /// Highlight ranges are computed against the normalized string and mapped
    /// back to original-text UTF-16 ranges, so multi-scalar graphemes (ё, é, ư)
    /// highlight correctly.
    static func highlightedAttributedString(
        _ text: String,
        tokens: [String],
        font: UIFont = AppTypography.bodyUIFont,
        foregroundColor: UIColor = .label
    ) -> AttributedString {
        guard !text.isEmpty, !tokens.isEmpty else {
            return plainAttributed(text, font: font, foregroundColor: foregroundColor)
        }

        let nsText = text as NSString
        let mergedRanges = mergedHighlightRanges(in: text, tokens: tokens)
        guard !mergedRanges.isEmpty else {
            return plainAttributed(text, font: font, foregroundColor: foregroundColor)
        }

        var result = AttributedString()
        var lastLocation = 0
        let highlight = highlightBackgroundColor

        for range in mergedRanges {
            if range.location > lastLocation {
                result += attributed(
                    nsText.substring(with: NSRange(location: lastLocation, length: range.location - lastLocation)),
                    font: font,
                    foregroundColor: foregroundColor
                )
            }

            var highlighted = attributed(
                nsText.substring(with: range),
                font: font,
                foregroundColor: foregroundColor
            )
            highlighted.backgroundColor = highlight
            result += highlighted

            lastLocation = range.location + range.length
        }

        if lastLocation < nsText.length {
            result += attributed(
                nsText.substring(with: NSRange(location: lastLocation, length: nsText.length - lastLocation)),
                font: font,
                foregroundColor: foregroundColor
            )
        }

        return result
    }

    private static func plainAttributed(_ text: String, font: UIFont, foregroundColor: UIColor) -> AttributedString {
        var attr = AttributedString(text)
        attr.font = font
        attr.foregroundColor = foregroundColor
        return attr
    }

    private static func attributed(_ substring: String, font: UIFont, foregroundColor: UIColor) -> AttributedString {
        var attr = AttributedString(substring)
        attr.font = font
        attr.foregroundColor = foregroundColor
        return attr
    }

    private static func mergedHighlightRanges(in text: String, tokens: [String]) -> [NSRange] {
        let mapping = buildNormalizedWithMap(text)
        guard !mapping.normalized.isEmpty else { return [] }

        var ranges: [NSRange] = []
        let nsNormalized = mapping.normalized as NSString

        for token in tokens where !token.isEmpty {
            var searchIndex = 0
            while searchIndex < nsNormalized.length {
                let index = nsNormalized.range(of: token, options: [], range: NSRange(location: searchIndex, length: nsNormalized.length - searchIndex)).location
                if index == NSNotFound { break }

                let startOrig = mapping.map[index]
                let endNormIndex = index + (token as NSString).length - 1
                let endOrigSourceIndex = mapping.map[min(endNormIndex, mapping.map.count - 1)]
                let endOrig = utf16IndexAfterCodePoint(at: text, utf16Start: endOrigSourceIndex)

                if startOrig < endOrig {
                    ranges.append(NSRange(location: startOrig, length: endOrig - startOrig))
                }

                searchIndex = index + (token as NSString).length
            }
        }

        guard !ranges.isEmpty else { return [] }
        ranges.sort { $0.location < $1.location }

        var merged: [NSRange] = []
        for range in ranges {
            if let last = merged.last, range.location <= last.location + last.length {
                let end = max(last.location + last.length, range.location + range.length)
                merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    // MARK: - Normalized ↔ original index mapping

    private struct NormalizedMap {
        let normalized: String
        /// For each character of `normalized`, the corresponding UTF-16 offset
        /// in the original string.
        let map: [Int]
    }

    private static func buildNormalizedWithMap(_ value: String) -> NormalizedMap {
        var normalized = ""
        var map: [Int] = []
        normalized.reserveCapacity(value.count)
        map.reserveCapacity(value.count)

        var utf16Index = 0
        for character in value {
            let segmentStart = utf16Index
            if isCyrillicCharacter(character) {
                normalized.append(String(character).lowercased())
                map.append(segmentStart)
            } else {
                let decomposed = String(character).decomposedStringWithCanonicalMapping
                for scalar in decomposed.unicodeScalars where !combiningDiacritics.contains(scalar) {
                    normalized.append(String(scalar).lowercased())
                    map.append(segmentStart)
                }
            }
            utf16Index += character.utf16.count
        }

        return NormalizedMap(normalized: normalized, map: map)
    }

    private static func utf16IndexAfterCodePoint(at text: String, utf16Start: Int) -> Int {
        guard utf16Start < text.utf16.count else { return utf16Start }
        let start = String.Index(utf16Offset: utf16Start, in: text)
        let next = text.index(after: start)
        return next.utf16Offset(in: text)
    }

    // MARK: - Plain text extraction

    /// Flattens recipe description HTML into plain text using the project parser,
    /// so timer labels and ingredient references inside the description survive.
    static func plainText(fromDescriptionHTML html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        let document = RecipeDescriptionParser.parse(html)
        var parts: [String] = []
        parts.reserveCapacity(document.blocks.count)

        for block in document.blocks {
            let runs: [RecipeDescriptionInlineRun]
            switch block {
            case .paragraph(_, let blockRuns),
                 .orderedStep(_, _, let blockRuns),
                 .bullet(_, let blockRuns),
                 .heading(_, _, let blockRuns):
                runs = blockRuns
            }
            var segment = ""
            for run in runs {
                switch run {
                case .plain(let text), .strong(let text), .em(let text):
                    segment += text
                case .link(_, let text):
                    segment += text
                case .timer(let reference):
                    segment += reference.displayText
                case .ingredient(let name):
                    segment += name
                case .lineBreak:
                    segment += " "
                }
            }
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }

        return parts
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
