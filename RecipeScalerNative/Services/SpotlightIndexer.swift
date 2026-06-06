import Combine
import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers

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
            // User has no recipes (e.g. fresh install / logout) → wipe index.
            await clearAll()
            return
        }

        let live = entries.filter { !$0.deleted }
        let liveIds = Set(live.map { $0.id })

        // 1. Remove tombstoned / absent.
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

        // 2. Index new / changed (by updatedAt fingerprint).
        let dirty = live.filter { indexedFingerprints[$0.id] != $0.updatedAt }
        guard !dirty.isEmpty else { return }

        logger.info("Reindexing \(dirty.count) recipe(s); stale removed: \(stale.count)")

        for entry in dirty {
            await indexOne(entry: entry)
        }
    }

    private func indexOne(entry: CollectionEntry) async {
        guard let recipe = await syncService.peekRecipeData(recipeId: entry.id) else {
            // Snapshot not yet synced — skip; next reindex tick will retry.
            return
        }

        let attrs = CSSearchableItemAttributeSet(itemContentType: UTType.text.identifier)
        attrs.title = recipe.name
        attrs.contentDescription = Self.buildPreview(recipe: recipe)
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

        // Action button "Add to Shopping" — Info.plist declares title + SF Symbol.
        attrs.actionIdentifiers = [Self.actionAddToShopping]

        // Thumbnail: prefer local cached file, fall back to remote URL (Spotlight
        // will fetch and cache on its own).
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
            indexedFingerprints[entry.id] = entry.updatedAt
        } catch {
            logger.warning("Index failed for \(entry.id): \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static let dateParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Build a readable preview string for the Spotlight card.
    ///
    /// Prefers a structured ingredient list (one per line, "amount unit name"),
    /// falling back to the plain-text HTML description when no ingredients exist.
    private static func buildPreview(recipe: RecipeData) -> String? {
        let items = recipe.ingredients
            .filter { !$0.isSeparator && !$0.name.isEmpty }
            .prefix(8)
            .map { ingredient -> String in
                let parts = [ingredient.amount, ingredient.unit, ingredient.name]
                    .filter { !$0.isEmpty }
                return parts.joined(separator: " ")
            }
        if !items.isEmpty {
            let suffix = recipe.ingredients.count > 8 ? " …" : ""
            return items.joined(separator: "\n") + suffix
        }
        return plainText(fromHTML: recipe.description)
    }

    /// Best-effort HTML → plain text fallback.
    private static func plainText(fromHTML html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }
        let stripped = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let collapsed = stripped.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }
}
