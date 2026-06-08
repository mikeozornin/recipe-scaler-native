import Combine
import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Indexes the user's recipe collection into the system Spotlight index.
///
/// Indexing is reactive: subscribes to `YjsSyncService.$collectionEntries` and
/// reindexes on change (debounced). Each recipe produces a `CSSearchableItem`
/// with title, description, ingredient keywords, thumbnail, and an
/// `addToShopping` action button (declared in Info.plist `CoreSpotlightActions`).
///
/// Tap handling: see `RecipeScalerNativeApp` `.onContinueUserActivity(CSSearchableItemActionType)`.
@MainActor
final class SpotlightIndexer: ObservableObject {
    static let domainIdentifier = "ru.recipescaler.RecipeScalerNative.recipes"

    /// Mirrors `CoreSpotlightActionIdentifier` in Info.plist.
    static let actionAddToShopping = "addToShopping"

    /// Bump when indexing payload shape changes so existing items reindex.
    private static let previewFormatVersion = "2"

    private let syncService: YjsSyncService
    private let logger = Logger(subsystem: "com.recipescaler.native", category: "SpotlightIndexer")
    private var cancellables = Set<AnyCancellable>()
    /// recipeId → updatedAt. Used to skip reindex when content unchanged.
    private var indexedFingerprints: [String: String] = [:]
    private var isStarted = false

    init(syncService: YjsSyncService) {
        self.syncService = syncService
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        syncService.$collectionEntries
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] entries in
                Task { [weak self] in
                    await self?.reindex(entries: entries)
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        isStarted = false
    }

    /// Wipe everything this app indexed. Called on logout / user switch.
    func clearAll() async {
        let domainId = Self.domainIdentifier
        do {
            try await CSSearchableIndex.default()
                .deleteSearchableItems(withDomainIdentifiers: [domainId])
        } catch {
            logger.warning("clearAll failed: \(error.localizedDescription)")
        }
        indexedFingerprints.removeAll()
    }

    // MARK: - Internal

    private func reindex(entries: [CollectionEntry]) async {
        guard !entries.isEmpty else {
            await clearAll()
            return
        }

        let live = entries.filter { !$0.deleted }
        let liveIds = Set(live.map { $0.id })

        let stale = Set(indexedFingerprints.keys).subtracting(liveIds)
        if !stale.isEmpty {
            do {
                try await CSSearchableIndex.default()
                    .deleteSearchableItems(withIdentifiers: Array(stale))
            } catch {
                logger.warning("delete stale failed: \(error.localizedDescription)")
            }
            for id in stale {
                indexedFingerprints.removeValue(forKey: id)
            }
        }

        let dirty = live.filter { indexedFingerprints[$0.id] != indexFingerprint(for: $0) }
        guard !dirty.isEmpty else { return }

        logger.info("Reindexing \(dirty.count) recipe(s); stale removed: \(stale.count)")

        for entry in dirty {
            await indexOne(entry: entry)
        }
    }

    private func indexOne(entry: CollectionEntry) async {
        guard var recipe = await syncService.peekRecipeData(recipeId: entry.id) else {
            return
        }

        recipe = RecipeCollectionMerge.merged(recipe, with: entry)

        let attrs = CSSearchableItemAttributeSet(itemContentType: UTType.text.identifier)
        attrs.title = recipe.name
        let displayTitle = RecipeTitleEmoji.displayName(for: recipe.name)
        if !displayTitle.isEmpty {
            attrs.displayName = displayTitle
        }
        attrs.contentDescription = Self.buildPreview(recipe: recipe)
        if let fullText = Self.plainText(fromHTML: recipe.description), !fullText.isEmpty {
            attrs.textContent = fullText
        }
        attrs.identifier = recipe.id

        let ingredientKeywords = recipe.ingredients
            .filter { !$0.isSeparator && !$0.name.isEmpty }
            .map { $0.name }
        attrs.keywords = ingredientKeywords.isEmpty ? nil : ingredientKeywords

        if let updated = Self.dateParser.date(from: entry.updatedAt) {
            attrs.lastUsedDate = updated
            attrs.contentCreationDate = updated
            attrs.contentModificationDate = updated
        }

        attrs.actionIdentifiers = [Self.actionAddToShopping]

        if let localURL = RecipeImageDiskCache.existingFileURL(recipeId: entry.id, variant: .preview)
            ?? RecipeImageDiskCache.existingFileURL(recipeId: entry.id, variant: .full),
            let data = try? Data(contentsOf: localURL) {
            attrs.thumbnailData = data
        } else if let urlString = entry.imageUrl, let url = URL(string: urlString) {
            attrs.thumbnailURL = url
        }

        let item = CSSearchableItem(
            uniqueIdentifier: entry.id,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attrs
        )
        item.expirationDate = .distantFuture

        do {
            try await CSSearchableIndex.default().indexSearchableItems([item])
            indexedFingerprints[entry.id] = indexFingerprint(for: entry)
        } catch {
            logger.warning("Index failed for \(entry.id): \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func indexFingerprint(for entry: CollectionEntry) -> String {
        "\(entry.updatedAt)|\(Self.previewFormatVersion)"
    }

    private static let dateParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Spotlight snippet: ingredients on line 1, description on lines 2+.
    private static func buildPreview(recipe: RecipeData) -> String? {
        let ingredientSnippet = buildIngredientSnippet(recipe: recipe)
        let descriptionText = plainText(fromHTML: recipe.description)
            .flatMap { $0.isEmpty ? nil : $0 }

        switch (ingredientSnippet, descriptionText) {
        case (let ingredients?, let description?):
            let remaining = spotlightTotalMaxLength - ingredients.count - 1
            let truncatedDesc = remaining > 0 ? truncateToLength(description, maxLength: remaining) : ""
            if truncatedDesc.isEmpty {
                return ingredients
            }
            return ingredients + "\n" + truncatedDesc
        case (let ingredients?, nil):
            return ingredients
        case (nil, let description?):
            return truncateToLength(description, maxLength: spotlightTotalMaxLength)
        case (nil, nil):
            return nil
        }
    }

    private static func buildIngredientSnippet(recipe: RecipeData) -> String? {
        let ingredientLines = recipe.ingredients
            .filter { !$0.isHeaderRow }
            .compactMap { spotlightIngredientLine($0) }
            .filter { !$0.isEmpty }

        guard !ingredientLines.isEmpty else { return nil }

        let maxItems = 6
        var snippet = ingredientLines.prefix(maxItems).joined(separator: " · ")
        if ingredientLines.count > maxItems {
            snippet += " · …"
        }
        return truncateToLength(snippet, maxLength: spotlightSnippetMaxLength)
    }

    private static func spotlightIngredientLine(_ ingredient: IngredientData) -> String? {
        let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let qty = ingredient.quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !qty.isEmpty { parts.append(qty) }
        if !unit.isEmpty { parts.append(unit) }
        parts.append(name)
        return parts.joined(separator: " ")
    }

    private static let spotlightSnippetMaxLength = 220
    private static let spotlightTotalMaxLength = 300

    private static func truncateToLength(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func plainText(fromHTML html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }

        #if canImport(UIKit)
        if let data = html.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           ) {
            let raw = attributed.string
                .replacingOccurrences(of: "\u{00a0}", with: " ")
            let collapsed = raw.replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            if !collapsed.isEmpty { return collapsed }
        }
        #endif

        var text = html
        text = text.replacingOccurrences(of: "(?i)</p>|</li>|</div>|</h[1-6]>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }
}