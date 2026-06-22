import Foundation

/// Leading emoji in recipe titles — mirrors `shared/utils/recipe-title-emoji.ts`.
/// Uses `NSRegularExpression` with `\x{…}` escapes (Apple ICU does not accept `\u{…}` in patterns).
enum RecipeTitleEmoji {
    /// Full web-aligned pattern (ICU property escapes — may fail on some OS builds).
    private static let leadingEmojiPatternFull =
        "([\\p{Regional_Indicator}]{2}|[0-9#*][\\x{FE0F}]?\\x{20E3}|[\\p{Extended_Pictographic}](?:[\\x{FE0F}\\x{FE0E}])?(?:[\\x{1F3FB}-\\x{1F3FF}])?(?:\\x{200D}[\\p{Extended_Pictographic}](?:[\\x{FE0F}\\x{FE0E}])?(?:[\\x{1F3FB}-\\x{1F3FF}])?)*)"

    /// Simpler BMP/supplementary ranges — compiles reliably on Apple ICU.
    /// Includes ZWJ-joined sequences (family emoji like 👨‍👩‍👧) so the whole
    /// grapheme cluster is captured instead of just the first emoji.
    private static let leadingEmojiPatternFallback =
        "([\\x{1F1E6}-\\x{1F1FF}]{2}|[\\x{1F300}-\\x{1FAFF}\\x{2600}-\\x{27BF}][\\x{FE0F}\\x{FE0E}]?(?:[\\x{1F3FB}-\\x{1F3FF}])?(?:\\x{200D}[\\x{1F300}-\\x{1FAFF}\\x{2600}-\\x{27BF}][\\x{FE0F}\\x{FE0E}]?(?:[\\x{1F3FB}-\\x{1F3FF}])?)*)"

    private static let compiled: (leading: NSRegularExpression?, prefix: NSRegularExpression?) = compileRegexes()

    private static func compileRegexes() -> (NSRegularExpression?, NSRegularExpression?) {
        // Prefer the ICU-safe fallback first (see crash log 2026-06-02-010558.ips:
        // save color → collection refresh → RecipeListView sort → regex init).
        for pattern in [leadingEmojiPatternFallback, leadingEmojiPatternFull] {
            do {
                let leading = try NSRegularExpression(pattern: "^\\s*(\(pattern))", options: [])
                let prefix = try NSRegularExpression(pattern: "^\\s*\(pattern)\\s*", options: [])
                return (leading, prefix)
            } catch {
                continue
            }
        }
        return (nil, nil)
    }

    private static var leadingEmojiRegex: NSRegularExpression? { compiled.leading }
    private static var leadingEmojiPrefixRegex: NSRegularExpression? { compiled.prefix }

    static func leadingEmoji(in title: String?) -> String? {
        guard let title, !title.isEmpty,
              let leadingEmojiRegex,
              let match = leadingEmojiRegex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return String(title[captureRange])
    }

    static func titleWithoutLeadingEmoji(_ title: String?) -> String? {
        guard let title else { return title }
        let range = NSRange(title.startIndex..., in: title)
        guard let leadingEmojiRegex,
              leadingEmojiRegex.firstMatch(in: title, range: range) != nil,
              let leadingEmojiPrefixRegex else {
            return title
        }
        return leadingEmojiPrefixRegex.stringByReplacingMatches(in: title, range: range, withTemplate: "")
    }

    static func displayName(for title: String?) -> String {
        titleWithoutLeadingEmoji(title)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Same ordering as web `compareRecipeNamesIgnoringLeadingEmoji`.
    static func compareNames(_ a: String?, _ b: String?) -> ComparisonResult {
        let displayA = displayName(for: a)
        let displayB = displayName(for: b)
        let byDisplay = displayA.localizedStandardCompare(displayB)
        if byDisplay != .orderedSame {
            return byDisplay
        }
        return (a ?? "").localizedStandardCompare(b ?? "")
    }

    static func sortCollectionEntries(_ entries: [CollectionEntry]) -> [CollectionEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            let nameOrder = compareNames(lhs.name, rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }
}