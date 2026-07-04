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
    private let haystackById: [String: String]
    private let pickerEntriesRu: [IngredientIllustrationCatalogEntry]
    private let pickerEntriesEn: [IngredientIllustrationCatalogEntry]
    private let pickerViewRu: [IngredientIllustrationPickerEntry]
    private let pickerViewEn: [IngredientIllustrationPickerEntry]
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
        let canonical = Self.loadEntries(from: bundle, resource: "ingredient-catalog")
        let ruSorted = Self.loadEntries(from: bundle, resource: "ingredient-catalog.ru")
        let enSorted = Self.loadEntries(from: bundle, resource: "ingredient-catalog.en")

        self.entries = canonical
        self.entriesById = Dictionary(uniqueKeysWithValues: canonical.map { ($0.id, $0) })
        self.haystackById = Dictionary(uniqueKeysWithValues: canonical.map { entry in
            let parts = [
                entry.labelRu,
                entry.labelEn,
                entry.aliasesRu.joined(separator: " "),
                entry.aliasesEn.joined(separator: " "),
                entry.id,
            ]
            let haystack = IngredientIllustrationSearchNormalization.normalizeForSearch(parts.joined(separator: " "))
            return (entry.id, haystack)
        })

        let resolvedRu = ruSorted.count == canonical.count ? ruSorted : Self.legacyLocalizedSort(canonical, locale: .ru)
        let resolvedEn = enSorted.count == canonical.count ? enSorted : Self.legacyLocalizedSort(canonical, locale: .en)
        self.pickerEntriesRu = resolvedRu
        self.pickerEntriesEn = resolvedEn
        self.pickerViewRu = resolvedRu.map { IngredientIllustrationPickerEntry(id: $0.id, primaryLabel: $0.labelRu) }
        self.pickerViewEn = resolvedEn.map { IngredientIllustrationPickerEntry(id: $0.id, primaryLabel: $0.labelEn) }
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
        switch locale {
        case .ru: return pickerViewRu
        case .en: return pickerViewEn
        }
    }

    /// Empty query returns all entries in pre-sorted picker order.
    /// Non-empty: AND token match on NFKD haystack, preserving pre-sorted order.
    public func search(query: String, locale: IngredientIllustrationCatalogLocale) -> [IngredientIllustrationPickerEntry] {
        let tokens = IngredientIllustrationSearchNormalization.tokenizeQuery(query)
        let source: [IngredientIllustrationCatalogEntry]
        let view: [IngredientIllustrationPickerEntry]
        switch locale {
        case .ru:
            source = pickerEntriesRu
            view = pickerViewRu
        case .en:
            source = pickerEntriesEn
            view = pickerViewEn
        }

        if tokens.isEmpty {
            return view
        }

        return source
            .filter { entry in
                guard let haystack = haystackById[entry.id] else { return false }
                return tokens.allSatisfy { haystack.contains($0) }
            }
            .map { IngredientIllustrationPickerEntry(id: $0.id, primaryLabel: primaryLabel(for: $0, locale: locale)) }
    }

    private func primaryLabel(for entry: IngredientIllustrationCatalogEntry, locale: IngredientIllustrationCatalogLocale) -> String {
        switch locale {
        case .ru: return entry.labelRu
        case .en: return entry.labelEn
        }
    }

    private static func loadEntries(from bundle: Bundle, resource: String) -> [IngredientIllustrationCatalogEntry] {
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
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

    /// Backwards-compatibility fallback used when the pre-sorted `*.ru.json` / `*.en.json`
    /// artifacts are missing (e.g. partial bundle). Produces the same order the runtime
    /// used to compute on every call before the build-time pre-sort optimization.
    private static func legacyLocalizedSort(
        _ entries: [IngredientIllustrationCatalogEntry],
        locale: IngredientIllustrationCatalogLocale
    ) -> [IngredientIllustrationCatalogEntry] {
        entries.sorted { lhs, rhs in
            let l = locale == .ru ? lhs.labelRu : lhs.labelEn
            let r = locale == .ru ? rhs.labelRu : rhs.labelEn
            if l != r { return l.localizedCompare(r) == .orderedAscending }
            return lhs.id.localizedCompare(rhs.id) == .orderedAscending
        }
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
