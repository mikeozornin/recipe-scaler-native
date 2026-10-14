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
    let searchTokens: [String]
    let aspectRatio: CGFloat
    let fillsFrame: Bool

    init(
        imageURL: URL?,
        name: String,
        accentColor: Color,
        searchTokens: [String] = [],
        aspectRatio: CGFloat = 16.0 / 9.0,
        fillsFrame: Bool = true
    ) {
        self.imageURL = imageURL
        self.name = name
        self.accentColor = accentColor
        self.searchTokens = searchTokens
        self.aspectRatio = aspectRatio
        self.fillsFrame = fillsFrame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DiscoverRecipePreviewImage(
                url: imageURL,
                fallbackColor: accentColor,
                cornerRadius: 8,
                aspectRatio: aspectRatio,
                fillsFrame: fillsFrame
            )

            titleLabel
                .font(AppTypography.headline)
                .lineSpacing(AppTypography.bodyLineSpacing)
                .foregroundStyle(RecipeDescriptionStyle.linkColor)
                .underline(
                    true,
                    color: RecipeDescriptionStyle.linkColor.opacity(0.5)
                )
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var titleLabel: some View {
        if searchTokens.isEmpty {
            Text(name)
        } else {
            let title = RecipeSearchUtils.highlightedAttributedString(
                name,
                tokens: searchTokens,
                font: AppTypography.sansMediumBodyUIFont,
                foregroundColor: RecipeDescriptionStyle.linkUIColor
            )
            Text(title)
        }
    }
}

extension DiscoverRecipeCard {
    init(recipe: CuratedRecipeMetadataDTO, searchTokens: [String] = []) {
        self.init(
            imageURL: DiscoverImageURLs.collectionRecipeCard(recipe: recipe),
            name: recipe.name,
            accentColor: RecipeAccentColor.color(from: recipe.color),
            searchTokens: searchTokens
        )
    }

    init(recipe: PublicRecipePreviewDTO, searchTokens: [String] = []) {
        self.init(
            imageURL: DiscoverImageURLs.publicRecipeCard(recipe: recipe),
            name: recipe.name,
            accentColor: recipe.color.map(RecipeAccentColor.color(from:)) ?? .accentColor,
            searchTokens: searchTokens
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

    @Environment(\.appLayoutMode) private var layoutMode
    @State private var availableWidth: CGFloat = 0
    /// Spec 081: the grid width as `DiscoverRecipeCardGridPadWidthReader` measures it (iPad only).
    @State private var padWidth: CGFloat = 0

    private var columnCount: Int {
        DiscoverRecipeCardLayout.columnCount(
            availableWidth: layoutMode == .padRegular ? padWidth : availableWidth
        )
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
                            .id(item.id)
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
        .modifier(DiscoverRecipeCardGridPadWidthReader(width: $padWidth))
    }
}

/// Spec 081 — on iPadOS 26 the background `GeometryReader` preference above reaches the grid
/// only as 0, so the author page stayed one column of page-wide cards at any width. A
/// regular-width iPad takes the width from `onGeometryChange` instead (columns of at least
/// 280, as on the web). Keyed on the idiom, as `iPadReadableWidth`: the iPhone keeps the view
/// tree it had.
private struct DiscoverRecipeCardGridPadWidthReader: ViewModifier {
    @Binding var width: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        } else {
            content
        }
    }
}

private struct DiscoverRecipeCardGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
