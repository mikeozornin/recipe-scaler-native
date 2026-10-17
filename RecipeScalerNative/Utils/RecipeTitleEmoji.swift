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
        "([\\x{1F1E6}-\\x{1F1FF}]{2}|[0-9#*][\\x{FE0F}]?\\x{20E3}|[\\x{1F300}-\\x{1FAFF}\\x{2600}-\\x{27BF}][\\x{FE0F}\\x{FE0E}]?(?:[\\x{1F3FB}-\\x{1F3FF}])?(?:\\x{200D}[\\x{1F300}-\\x{1FAFF}\\x{2600}-\\x{27BF}][\\x{FE0F}\\x{FE0E}]?(?:[\\x{1F3FB}-\\x{1F3FF}])?)*)"

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

    /// `true` when the first scalar of `title` can neither be `\s` nor start an emoji of
    /// either pattern, so the regexes cannot match. Covers printable ASCII (other than
    /// `0-9 # *`), Latin-1 Supplement and Latin Extended (other than `©`/`®`, which are
    /// `Extended_Pictographic`), Greek, Cyrillic, kana, CJK ideographs and Hangul; any
    /// other first scalar goes through the regex.
    static func cannotStartWithEmoji(_ title: String) -> Bool {
        guard let first = title.unicodeScalars.first else { return true }
        switch first.value {
        case 0x30 ... 0x39, 0x23, 0x2A:
            return false
        case 0x21 ... 0x7E:
            return true
        case 0xA9, 0xAE:
            return false
        case 0xA1 ... 0x24F, 0x370 ... 0x3FF, 0x400 ... 0x52F, 0x3040 ... 0x30FF, 0x4E00 ... 0x9FFF, 0xAC00 ... 0xD7A3:
            return true
        default:
            return false
        }
    }

    static func leadingEmoji(in title: String?) -> String? {
        guard let title, !title.isEmpty, !cannotStartWithEmoji(title),
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
        if cannotStartWithEmoji(title) { return title }
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
        compare(NameSortKey(a), NameSortKey(b))
    }

    /// `compareNames` operands computed once per item, so a sort runs the emoji regex `n`
    /// times instead of twice per comparison.
    struct NameSortKey: Sendable {
        let display: String
        let name: String

        init(_ title: String?) {
            display = RecipeTitleEmoji.displayName(for: title)
            name = title ?? ""
        }

        init(display: String, name: String) {
            self.display = display
            self.name = name
        }
    }

    /// `compareNames` on precomputed keys.
    static func compare(_ a: NameSortKey, _ b: NameSortKey) -> ComparisonResult {
        let byDisplay = a.display.localizedStandardCompare(b.display)
        if byDisplay != .orderedSame {
            return byDisplay
        }
        return a.name.localizedStandardCompare(b.name)
    }

    /// `items` sorted A–Z by `compareNames(name(item))`: the keys are computed once per item
    /// and the sort sees the same comparison results, so the order is the same.
    static func sortedByName<Item>(_ items: [Item], name: (Item) -> String?) -> [Item] {
        items
            .map { (key: NameSortKey(name($0)), item: $0) }
            .sorted { compare($0.key, $1.key) == .orderedAscending }
            .map(\.item)
    }

    /// Pinned first, then `compareNames` order, then id. Matches web
    /// `sortRecipesForListDisplay`. Uses the entries' precomputed display names.
    static func sortCollectionEntries(_ entries: [CollectionEntry]) -> [CollectionEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            let nameOrder = compare(
                NameSortKey(display: lhs.displayName, name: lhs.name),
                NameSortKey(display: rhs.displayName, name: rhs.name)
            )
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }
}