import Foundation

/// Search normalization for ingredient catalog picker (parity with web `search-utils` + `RecipeSearchUtils`).
public enum IngredientIllustrationSearchNormalization {
    private static let combiningDiacritics = CharacterSet(charactersIn: "\u{0300}"..."\u{036F}")

    public static func normalizeForSearch(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespaces)
            .map(normalizeSearchCharacter)
            .joined()
    }

    /// Trim, tokenize with quoted phrases, normalize each token.
    public static func tokenizeQuery(_ query: String) -> [String] {
        var tokens: [String] = []
        var remaining = query[...]

        while !remaining.isEmpty {
            remaining = Substring(remaining.trimmingCharacters(in: .whitespaces))
            if remaining.isEmpty { break }

            if remaining.first == "\"" || remaining.first == "'" {
                let quote = remaining.first!
                remaining = remaining.dropFirst()
                guard let end = remaining.firstIndex(of: quote) else {
                    let phrase = String(remaining)
                    let normalized = normalizeForSearch(phrase)
                    if !normalized.isEmpty { tokens.append(normalized) }
                    break
                }
                let phrase = String(remaining[..<end])
                let normalized = normalizeForSearch(phrase)
                if !normalized.isEmpty { tokens.append(normalized) }
                remaining = remaining[remaining.index(after: end)...]
                continue
            }

            let wordEnd = remaining.firstIndex(where: { $0.isWhitespace }) ?? remaining.endIndex
            let word = String(remaining[..<wordEnd])
            let normalized = normalizeForSearch(word)
            if !normalized.isEmpty { tokens.append(normalized) }
            remaining = wordEnd < remaining.endIndex ? remaining[wordEnd...] : Substring()
        }

        return tokens
    }

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
}