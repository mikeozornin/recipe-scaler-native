//
//  DiscoverRecipeCard.swift
//  RecipeScalerNative
//

import SwiftUI
import RecipeScalerCore

/// Vertical recipe preview card (web `RecipePreviewCard` parity):
/// 16:9 image on top, underlined brand-blue title below.
struct DiscoverRecipeCard: View {
    let imageURL: URL?
    let name: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DiscoverRecipePreviewImage(
                url: imageURL,
                fallbackColor: accentColor,
                cornerRadius: 8,
                aspectRatio: 16.0 / 9.0
            )

            Text(name)
                .appHeadline()
                .foregroundStyle(RecipeDescriptionStyle.linkColor)
                .underline(
                    true,
                    color: RecipeDescriptionStyle.linkColor.opacity(0.5)
                )
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension DiscoverRecipeCard {
    init(recipe: CuratedRecipeMetadataDTO) {
        self.init(
            imageURL: DiscoverAPI.collectionRecipeCardImageURL(recipe: recipe),
            name: recipe.name,
            accentColor: RecipeAccentColor.color(from: recipe.color)
        )
    }

    init(recipe: PublicRecipePreviewDTO) {
        self.init(
            imageURL: DiscoverAPI.publicRecipeCardImageURL(recipe: recipe),
            name: recipe.name,
            accentColor: recipe.color.map(RecipeAccentColor.color(from:)) ?? .accentColor
        )
    }
}

enum DiscoverRecipeCardLayout {
    /// Web `.card-grid`: `repeat(auto-fit, minmax(280px, 1fr))`.
    static let minimumColumnWidth: CGFloat = 280
    static let horizontalSpacing: CGFloat = 24
    static let verticalSpacing: CGFloat = 16

    static func columnCount(availableWidth: CGFloat) -> Int {
        guard availableWidth > 0 else { return 1 }
        return max(
            1,
            Int((availableWidth + horizontalSpacing) / (minimumColumnWidth + horizontalSpacing))
        )
    }
}

/// Eager grid — keeps cells alive while scrolling (no `LazyVGrid` image unload).
struct DiscoverRecipeCardGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    @State private var availableWidth: CGFloat = 0

    private var columnCount: Int {
        DiscoverRecipeCardLayout.columnCount(availableWidth: availableWidth)
    }

    private var rows: [[Item]] {
        guard columnCount > 0 else { return [] }
        return stride(from: 0, to: items.count, by: columnCount).map { start in
            Array(items[start ..< min(start + columnCount, items.count)])
        }
    }

    var body: some View {
        VStack(spacing: DiscoverRecipeCardLayout.verticalSpacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(alignment: .top, spacing: DiscoverRecipeCardLayout.horizontalSpacing) {
                    ForEach(rows[rowIndex]) { item in
                        content(item)
                            .frame(maxWidth: .infinity)
                    }
                    if rows[rowIndex].count < columnCount {
                        ForEach(0 ..< (columnCount - rows[rowIndex].count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: DiscoverRecipeCardGridWidthKey.self,
                    value: geometry.size.width
                )
            }
        }
        .onPreferenceChange(DiscoverRecipeCardGridWidthKey.self) { availableWidth = $0 }
    }
}

private struct DiscoverRecipeCardGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
