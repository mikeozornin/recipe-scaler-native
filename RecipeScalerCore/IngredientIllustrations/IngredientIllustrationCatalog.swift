import Foundation

public struct IngredientIllustrationCatalogEntry: Codable, Sendable, Equatable {
    public let id: String
    public let category: String
    public let labelRu: String
    public let labelEn: String
    public let aliasesRu: [String]
    public let aliasesEn: [String]
}

public struct IngredientIllustrationPickerEntry: Sendable, Equatable {
    public let id: String
    public let primaryLabel: String
}

public enum IngredientIllustrationCatalogLocale: Sendable {
    case ru
    case en

    public static func from(languageCode: String?) -> Self {
        guard let languageCode, languageCode.lowercased().hasPrefix("ru") else { return .en }
        return .ru
    }
}

public final class IngredientIllustrationCatalog: @unchecked Sendable {
    public static let shared = IngredientIllustrationCatalog()

    private let entries: [IngredientIllustrationCatalogEntry]
    private let entriesById: [String: IngredientIllustrationCatalogEntry]
    private let searchIndex: [(entry: IngredientIllustrationCatalogEntry, haystack: String)]
    private lazy var cachedAliasIndex: [IngredientIllustrationAliasEntry] = Self.buildAliasIndex(entries: entries)

    public var entryCount: Int { entries.count }

    /// Full catalog entries for alias index building (name matcher).
    public func allEntriesForMatching() -> [IngredientIllustrationCatalogEntry] {
        entries
    }

    /// Precomputed alias index for `IngredientIllustrationNameMatcher` (built once per catalog).
    public func aliasIndexForMatching() -> [IngredientIllustrationAliasEntry] {
        cachedAliasIndex
    }

    public init(bundle: Bundle = Bundle(for: IngredientIllustrationCatalog.self)) {
        let loaded = Self.loadEntries(from: bundle)
        self.entries = loaded
        self.entriesById = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        self.searchIndex = loaded.map { entry in
            let parts = [
                entry.labelRu,
                entry.labelEn,
                entry.aliasesRu.joined(separator: " "),
                entry.aliasesEn.joined(separator: " "),
                entry.id,
            ]
            let haystack = IngredientIllustrationSearchNormalization.normalizeForSearch(parts.joined(separator: " "))
            return (entry, haystack)
        }
    }

    public func contains(id: String?) -> Bool {
        guard let id, !id.isEmpty else { return false }
        return entriesById[id] != nil
    }

    public func label(id: String, locale: IngredientIllustrationCatalogLocale) -> String? {
        guard let entry = entriesById[id] else { return nil }
        switch locale {
        case .ru: return entry.labelRu
        case .en: return entry.labelEn
        }
    }

    public func allPickerEntries(locale: IngredientIllustrationCatalogLocale) -> [IngredientIllustrationPickerEntry] {
        entries
            .sorted { lhs, rhs in
                let l = primaryLabel(for: lhs, locale: locale)
                let r = primaryLabel(for: rhs, locale: locale)
                if l != r { return l.localizedCompare(r) == .orderedAscending }
                return lhs.id.localizedCompare(rhs.id) == .orderedAscending
            }
            .map { IngredientIllustrationPickerEntry(id: $0.id, primaryLabel: primaryLabel(for: $0, locale: locale)) }
    }

    /// Empty query returns all entries (sorted). Non-empty: AND token match on NFKD haystack.
    public func search(query: String, locale: IngredientIllustrationCatalogLocale) -> [IngredientIllustrationPickerEntry] {
        let tokens = IngredientIllustrationSearchNormalization.tokenizeQuery(query)
        let filtered: [IngredientIllustrationCatalogEntry]
        if tokens.isEmpty {
            filtered = entries
        } else {
            filtered = searchIndex.compactMap { indexed in
                tokens.allSatisfy { indexed.haystack.contains($0) } ? indexed.entry : nil
            }
        }
        return filtered
            .sorted { lhs, rhs in
                let l = primaryLabel(for: lhs, locale: locale)
                let r = primaryLabel(for: rhs, locale: locale)
                if l != r { return l.localizedCompare(r) == .orderedAscending }
                return lhs.id.localizedCompare(rhs.id) == .orderedAscending
            }
            .map { IngredientIllustrationPickerEntry(id: $0.id, primaryLabel: primaryLabel(for: $0, locale: locale)) }
    }

    private func primaryLabel(for entry: IngredientIllustrationCatalogEntry, locale: IngredientIllustrationCatalogLocale) -> String {
        switch locale {
        case .ru: return entry.labelRu
        case .en: return entry.labelEn
        }
    }

    private static func loadEntries(from bundle: Bundle) -> [IngredientIllustrationCatalogEntry] {
        guard let url = bundle.url(forResource: "ingredient-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CatalogFile.self, from: data)
        else {
            return []
        }
        return payload.entries
    }

    private struct CatalogFile: Codable {
        let entries: [IngredientIllustrationCatalogEntry]
    }

    private static func buildAliasIndex(entries: [IngredientIllustrationCatalogEntry]) -> [IngredientIllustrationAliasEntry] {
        var out: [IngredientIllustrationAliasEntry] = []
        for entry in entries {
            pushUniqueAlias(&out, id: entry.id, raw: entry.labelRu)
            pushUniqueAlias(&out, id: entry.id, raw: entry.labelEn)
            for alias in entry.aliasesRu { pushUniqueAlias(&out, id: entry.id, raw: alias) }
            for alias in entry.aliasesEn { pushUniqueAlias(&out, id: entry.id, raw: alias) }
        }
        out.sort { $0.normalized.count > $1.normalized.count }
        return out
    }

    private static func pushUniqueAlias(_ out: inout [IngredientIllustrationAliasEntry], id: String, raw: String) {
        let normalized = IngredientIllustrationSearchNormalization.normalizeForSearch(raw)
        guard !normalized.isEmpty else { return }
        if out.contains(where: { $0.id == id && $0.normalized == normalized }) { return }
        out.append(IngredientIllustrationAliasEntry(id: id, normalized: normalized))
    }
}

public struct IngredientIllustrationAliasEntry: Sendable, Equatable {
    public let id: String
    public let normalized: String
}