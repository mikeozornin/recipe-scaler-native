import Foundation
import SwiftUI
import SwiftData

@MainActor
class RecipeListViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let syncService: YjsSyncService

    /// Collection entries from YjsSyncService, filtered for display.
    var collectionEntries: [CollectionEntry] {
        return syncService.collectionEntries
    }

    /// Current connection state.
    var connectionState: ConnectionState {
        return syncService.connectionState
    }

    init(syncService: YjsSyncService) {
        self.syncService = syncService
    }

    /// Start sync service for the given user.
    func start(userId: String) async {
        isLoading = true
        defer { isLoading = false }

        await syncService.start(userId: userId)
    }

    /// Filter collection entries by search query.
    /// Supports tokenized search across name field.
    func filteredEntries(query: String) -> [CollectionEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return collectionEntries
        }

        let tokens = tokenizeQuery(trimmed)
        return collectionEntries.filter { entry in
            tokens.allSatisfy { token in
                normalizeForSearch(entry.name).contains(token)
            }
        }
    }

    // MARK: - Search Helpers

    private func tokenizeQuery(_ query: String) -> [String] {
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

    private func normalizeForSearch(_ value: String) -> String {
        return value
            .trimmingCharacters(in: .whitespaces)
            .normalizeNFKD()
            .lowercased()
    }

    /// Persist documents on background.
    func persistAll() async {
        await syncService.persistAll()
    }
}

// MARK: - String Normalization Extension

private extension String {
    func normalizeNFKD() -> String {
        return self.decomposedStringWithCanonicalMapping
            .components(separatedBy: CharacterSet(charactersIn: "\u{0300}"..."\u{036F}"))
            .joined()
    }
}
