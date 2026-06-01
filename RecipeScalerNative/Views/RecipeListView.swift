import SwiftUI

struct RecipeListView: View {
    @EnvironmentObject private var syncService: YjsSyncService
    @State private var searchText = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    private var filteredEntries: [CollectionEntry] {
        let entries = syncService.collectionEntries
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return entries
        }

        let tokens = tokenizeQuery(trimmed)
        return entries.filter { entry in
            tokens.allSatisfy { token in
                normalizeForSearch(entry.name).contains(token)
            }
        }
    }

    private var rowItems: [RecipeRowData] {
        filteredEntries
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if comparison == .orderedSame {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return comparison == .orderedAscending
            }
            .map { entry in
                RecipeRowData(
                    id: entry.id,
                    name: entry.name,
                    color: entry.color,
                    imageUrl: entry.imageUrl,
                    isPinned: entry.isPinned
                )
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if syncService.connectionState == .connecting && syncService.collectionEntries.isEmpty {
                    ProgressView(String(localized: "recipe.list.loading"))
                } else if rowItems.isEmpty {
                    ContentUnavailableView(
                        String(localized: "recipe.list.empty.title"),
                        systemImage: "fork.knife",
                        description: Text(String(localized: "Your recipes will appear here"))
                    )
                } else {
                    List {
                        ForEach(rowItems) { item in
                            NavigationLink(value: item.id) {
                                RecipeRow(data: item)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .accessibilityIdentifier(AccessibilityIdentifiers.recipeRow(id: item.id))
                        }
                    }
                    .listStyle(.plain)
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

// MARK: - Recipe Row

struct RecipeRow: View {
    let data: RecipeRowData

    private let rowHeight: CGFloat = 44
    private var bodyFont: UIFont {
        let size = UIFont.preferredFont(forTextStyle: .body).pointSize
        return UIFont(name: AppFonts.sans, size: size) ?? UIFont.preferredFont(forTextStyle: .body)
    }
    private var circleBaselineOffset: CGFloat {
        bodyFont.capHeight / 2
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let colorHex = data.color {
                    Circle()
                        .fill(Color(hex: colorHex) ?? .gray)
                        .frame(width: 10, height: 10)
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            dimensions[VerticalAlignment.center] + circleBaselineOffset
                        }
                }

                Text(data.name)
                    .font(.custom(AppFonts.sans, size: bodyFont.pointSize))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if data.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if data.imageUrl?.isEmpty == false {
                AsyncImage(url: URL(string: data.imageUrl!)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: rowHeight, height: rowHeight)
                .clipped()
            }
        }
        .frame(minHeight: rowHeight, alignment: .center)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Value Type

struct RecipeRowData: Identifiable {
    let id: String
    let name: String
    let color: String?
    let imageUrl: String?
    let isPinned: Bool
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
