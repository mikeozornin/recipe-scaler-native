import SwiftUI
import UIKit

struct RecipeListView: View {
    @EnvironmentObject private var syncService: YjsSyncService
    @State private var searchText = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    private var filteredEntries: [CollectionEntry] {
        let sorted = RecipeTitleEmoji.sortCollectionEntries(syncService.collectionEntries)
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return sorted
        }

        let tokens = tokenizeQuery(trimmed)
        return sorted.filter { entry in
            tokens.allSatisfy { token in
                normalizeForSearch(entry.name).contains(token)
            }
        }
    }

    private var pinnedRowItems: [RecipeRowData] {
        filteredEntries
            .filter(\.isPinned)
            .map(RecipeRowData.init(entry:))
    }

    private var unpinnedRowItems: [RecipeRowData] {
        filteredEntries
            .filter { !$0.isPinned }
            .map(RecipeRowData.init(entry:))
    }

    private var hasAnyRows: Bool {
        !pinnedRowItems.isEmpty || !unpinnedRowItems.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if syncService.connectionState == .connecting && syncService.collectionEntries.isEmpty {
                    ProgressView(String(localized: "recipe.list.loading"))
                } else if !hasAnyRows {
                    ContentUnavailableView(
                        String(localized: "recipe.list.empty.title"),
                        systemImage: "fork.knife",
                        description: Text(String(localized: "Your recipes will appear here"))
                    )
                } else {
                    List {
                        if !pinnedRowItems.isEmpty {
                            RecipeListSectionHeader(isPinnedSection: true)
                                .recipeListSectionHeaderRow()

                            recipeRows(pinnedRowItems)
                        }

                        if !unpinnedRowItems.isEmpty {
                            if !pinnedRowItems.isEmpty {
                                RecipeListSectionHeader(isPinnedSection: false)
                                    .recipeListSectionHeaderRow()
                            }

                            recipeRows(unpinnedRowItems)
                        }
                    }
                    .listStyle(.plain)
                    .listSectionSpacing(0)
                    .padding(.top, -10)
                    .accessibilityIdentifier(AccessibilityIdentifiers.recipeList)
                    .searchable(text: $searchText, prompt: "Search recipes")
                }
            }
            .navigationTitle("Recipes")
            .navigationDestination(for: String.self) { recipeId in
                YDocRecipeDetailView(recipeId: recipeId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Image(systemName: "person.circle")
                            .font(.custom(AppFonts.sansMedium, size: 20))
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.profileButton)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionStateIndicator(state: syncService.connectionState)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var allowsImageNetworkRefresh: Bool {
        switch syncService.connectionState {
        case .connected:
            return true
        case .connecting, .reconnecting, .disconnected, .error:
            return false
        }
    }

    @ViewBuilder
    private func recipeRows(_ items: [RecipeRowData]) -> some View {
        ForEach(items) { item in
            ZStack(alignment: .leading) {
                RecipeRow(
                    data: item,
                    allowsNetworkRefresh: allowsImageNetworkRefresh
                )

                NavigationLink(value: item.id) {
                    Color.clear
                }
                .frame(maxWidth: .infinity, minHeight: RecipeRowLayoutMetrics.rowHeight)
                .opacity(0.01)
            }
            .buttonStyle(.plain)
            .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeRow(id: item.id))
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
            .decomposedStringWithCanonicalMapping
            .components(separatedBy: CharacterSet(charactersIn: "\u{0300}"..."\u{036F}"))
            .joined()
            .lowercased()
    }
}

private enum RecipeListMetrics {
    static let colorDotSide: CGFloat = 12
    static let emojiFontSize: CGFloat = 18
    static let thumbnailSide: CGFloat = 44
}

// MARK: - Section chrome

private struct RecipeListSectionHeader: View {
    let isPinnedSection: Bool

    var body: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            if isPinnedSection {
                Image(systemName: "pin")
                    .font(.system(size: 16, weight: .medium))
                    .frame(
                        width: RecipeRowLayoutMetrics.markerSlotWidth,
                        height: RecipeRowLayoutMetrics.titleLineHeight,
                        alignment: .center
                    )
            }

            Text(
                isPinnedSection
                    ? String(localized: "recipe.list.section.pinned")
                    : String(localized: "recipe.list.section.unpinned")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.custom(AppFonts.sans, size: 14))
        .foregroundStyle(.secondary)
    }
}

private extension View {
    /// Web: `px-4 pt-2 pb-0 text-sm` — same leading grid as recipe rows (16 + 22 pt slot).
    func recipeListSectionHeaderRow() -> some View {
        fixedSize(horizontal: false, vertical: true)
            .listRowInsets(
                EdgeInsets(
                    top: 8,
                    leading: RecipeRowLayoutMetrics.listHorizontalInset,
                    bottom: 0,
                    trailing: RecipeRowLayoutMetrics.listHorizontalInset
                )
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .environment(\.defaultMinListRowHeight, 1)
    }
}

// MARK: - Connection State Indicator

private struct ConnectionStateIndicator: View {
    let state: ConnectionState

    var body: some View {
        switch state {
        case .connecting, .reconnecting:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        case .disconnected:
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Row marker slot (emoji or color dot in one frame)

private struct RecipeRowMarkerSlot: View {
    let emoji: String?
    let color: String?

    var body: some View {
        ZStack {
            if let emoji {
                Text(emoji)
                    .font(.system(size: RecipeListMetrics.emojiFontSize))
                    .fixedSize()
            } else {
                Circle()
                    .fill(RecipeAccentColor.color(from: color ?? "oklch(0.65 0.25 270)"))
                    .frame(
                        width: RecipeListMetrics.colorDotSide,
                        height: RecipeListMetrics.colorDotSide
                    )
            }
        }
        .frame(
            width: RecipeRowLayoutMetrics.markerSlotWidth,
            height: RecipeRowLayoutMetrics.titleLineHeight,
            alignment: .center
        )
    }
}

// MARK: - Recipe Row

struct RecipeRow: View {
    let data: RecipeRowData
    var allowsNetworkRefresh: Bool = true

    private var hasThumbnail: Bool { data.hasThumbnail }

    private var titleText: String {
        let trimmed = data.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "recipe.list.no-title")
        }
        return trimmed
    }

    var body: some View {
        titleRow
            .padding(.trailing, hasThumbnail ? RecipeListMetrics.thumbnailSide + 12 : 0)
            .overlay(alignment: .trailing) {
                if hasThumbnail {
                    recipeThumbnail
                }
            }
            .contentShape(Rectangle())
    }

    /// Height comes from title + marker only; thumbnail is overlaid (web: `self-center`, no stretch).
    private var titleRow: some View {
        HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
            RecipeRowMarkerSlot(
                emoji: data.leadingEmoji,
                color: data.color
            )

            Text(titleText)
                .font(.custom(AppFonts.sans, size: RecipeRowLayoutMetrics.titleFontSize))
                .foregroundColor(.primary)
                .lineSpacing(RecipeRowLayoutMetrics.wrappedLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ingredientListRowChrome()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recipeThumbnail: some View {
        RecipeCachedImageView(
            recipeId: data.id,
            imageUrl: data.imageUrl,
            variant: .preview,
            allowsNetworkRefresh: allowsNetworkRefresh
        )
        .frame(width: RecipeListMetrics.thumbnailSide, height: RecipeListMetrics.thumbnailSide)
        .clipped()
    }
}

// MARK: - Value Type

struct RecipeRowData: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let leadingEmoji: String?
    let color: String?
    let imageUrl: String?
    let isPinned: Bool

    var hasThumbnail: Bool {
        guard let imageUrl, !imageUrl.isEmpty else { return false }
        return true
    }

    init(entry: CollectionEntry) {
        id = entry.id
        name = entry.name
        leadingEmoji = RecipeTitleEmoji.leadingEmoji(in: entry.name)
        displayName = RecipeTitleEmoji.displayName(for: entry.name)
        color = entry.color
        imageUrl = entry.imageUrl
        isPinned = entry.isPinned
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    RecipeListView()
        .environmentObject({
            let database = try! YrsDatabase()
            let store = YDocStore(dbQueue: database.dbQueue)
            return YjsSyncService(store: store)
        }())
}