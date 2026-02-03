//
//  RecipeListView.swift
//  RecipeScalerNative
//
//

import SwiftUI
import SwiftData
import UIKit

/// Value-type snapshot for list row to avoid reading SwiftData in body (breaks AttributeGraph cycle).
struct RecipeRowData: Identifiable {
    let id: String
    let name: String
    let color: String?
    let imagePreviewLocalPath: String?
    let imageUrl: String?
}

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var recipes: [Recipe]

    @StateObject private var viewModel: RecipeListViewModel
    @State private var searchText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var rowItems: [RecipeRowData] = []
    private let autoLoad: Bool

    @MainActor
    init(autoLoad: Bool = true) {
        _viewModel = StateObject(wrappedValue: RecipeListViewModel())
        self.autoLoad = autoLoad
    }

    init(autoLoad: Bool = true, viewModel: RecipeListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.autoLoad = autoLoad
    }

    var filteredRecipes: [Recipe] {
        let baseRecipes: [Recipe]
        if searchText.isEmpty {
            baseRecipes = recipes
        } else {
            baseRecipes = recipes.filter { recipe in
                recipe.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return baseRecipes.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.updatedAt > rhs.updatedAt
            }
            return comparison == .orderedAscending
        }
    }

    private func updateRowItems() {
        rowItems = filteredRecipes.map { recipe in
            RecipeRowData(
                id: recipe.id,
                name: recipe.name,
                color: recipe.color,
                imagePreviewLocalPath: recipe.imagePreviewLocalPath,
                imageUrl: recipe.imageUrl
            )
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && rowItems.isEmpty {
                    ProgressView("Loading recipes...")
                } else if rowItems.isEmpty {
                    ContentUnavailableView(
                        "No Recipes",
                        systemImage: "fork.knife",
                        description: Text("Your recipes will appear here")
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
                    .refreshable {
                        await viewModel.loadRecipes(modelContext: modelContext)
                    }
                }
            }
            .navigationTitle("Recipes")
            .navigationDestination(for: String.self) { recipeId in
                if let recipe = recipes.first(where: { $0.id == recipeId }) {
                    RecipeDetailView(recipe: recipe)
                }
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
                    HStack(spacing: 12) {
                        // Sync status indicator
                        if viewModel.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else if let lastSync = viewModel.lastSyncDate {
                            Text(lastSync, style: .relative)
                                .font(.custom(AppFonts.sans, size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            guard autoLoad else { return }
            await viewModel.loadRecipes(modelContext: modelContext)
            updateRowItems()
        }
        .onChange(of: recipes.count) { updateRowItems() }
        .onChange(of: searchText) { updateRowItems() }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            guard let message = newValue, !message.isEmpty else { return }
            errorMessage = message
            showingError = true
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
                // Color indicator
                if let colorHex = data.color {
                    Circle()
                        .fill(Color(hex: colorHex) ?? .gray)
                        .frame(width: 10, height: 10)
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            dimensions[VerticalAlignment.center] + circleBaselineOffset
                        }
                }

                // Recipe name (max 2 lines, no measurement feedback loop)
                Text(data.name)
                    .font(.custom(AppFonts.sans, size: bodyFont.pointSize))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Recipe image thumbnail
            if let localPath = data.imagePreviewLocalPath,
               let uiImage = UIImage(contentsOfFile: localPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: rowHeight, height: rowHeight)
                    .clipped()
            } else if data.imageUrl?.isEmpty == false {
                AsyncImage(url: APIClient.shared.recipeImageURL(id: data.id, preview: true)) { phase in
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

// MARK: - Preview
#Preview {
    RecipeListView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
