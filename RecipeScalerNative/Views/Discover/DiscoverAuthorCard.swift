//
//  DiscoverAuthorCard.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit

/// Spec 082 — collage of an author card by the number of `preview_recipes` (newest first).
enum DiscoverAuthorCollageLayout: Equatable {
    /// No photos: a fill with an icon, as tall as a collage.
    case placeholder
    case single
    /// Two photos side by side.
    case halves
    /// Three or more: the newest on the left (2/3 of the width), the next two stacked on the right.
    case featureAndStack

    static let aspectRatio: CGFloat = 16.0 / 9.0
    static let gap: CGFloat = 3

    init(photoCount: Int) {
        switch photoCount {
        case ..<1: self = .placeholder
        case 1: self = .single
        case 2: self = .halves
        default: self = .featureAndStack
        }
    }

    /// Photos the layout shows: the first ones of `preview_recipes`.
    var photoCount: Int {
        switch self {
        case .placeholder: 0
        case .single: 1
        case .halves: 2
        case .featureAndStack: 3
        }
    }

    /// Photo tiles in a collage of `size`, in `preview_recipes` order.
    func tileFrames(in size: CGSize) -> [CGRect] {
        let gap = Self.gap
        switch self {
        case .placeholder:
            return []
        case .single:
            return [CGRect(origin: .zero, size: size)]
        case .halves:
            let width = (size.width - gap) / 2
            return [
                CGRect(x: 0, y: 0, width: width, height: size.height),
                CGRect(x: width + gap, y: 0, width: width, height: size.height),
            ]
        case .featureAndStack:
            let featureWidth = (size.width - gap) * 2 / 3
            let sideX = featureWidth + gap
            let sideWidth = size.width - sideX
            let sideHeight = (size.height - gap) / 2
            return [
                CGRect(x: 0, y: 0, width: featureWidth, height: size.height),
                CGRect(x: sideX, y: 0, width: sideWidth, height: sideHeight),
                CGRect(x: sideX, y: sideHeight + gap, width: sideWidth, height: sideHeight),
            ]
        }
    }
}

/// Spec 082 «Обложка» — Discover author card: photo collage, avatar over its bottom edge,
/// name, description and recipe count. The caller wraps it in one `NavigationLink`.
struct DiscoverAuthorCard: View {
    /// `.plain` — one column: no fill, frame or rounding, the caller separates cards with a
    /// hairline. `.outlined` — grid: a rounded hairline frame, still no fill.
    enum Style {
        case plain
        case outlined
    }

    let profile: PublicProfilePreviewDTO
    var style: Style = .plain

    @Environment(\.appLayoutMode) private var layoutMode

    private static let cornerRadius: CGFloat = 20
    private static let avatarSize: CGFloat = 52
    private static let avatarRing: CGFloat = 3

    /// The page behind the card: the avatar ring is cut out of it.
    private static let ringColor = Color(.systemBackground)

    /// Name, or `@username` when the profile has none.
    static func displayName(for profile: PublicProfilePreviewDTO) -> String {
        let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "@\(profile.username)" : name
    }

    /// VoiceOver: «{name}, {N recipes}» — the card is one button, the photos are decorative.
    static func accessibilityLabel(for profile: PublicProfilePreviewDTO) -> String {
        String(
            format: Bundle.currentLocalizedString("discover.author-card.accessibility-label"),
            displayName(for: profile),
            recipeCountText(for: profile)
        )
    }

    private static func recipeCountText(for profile: PublicProfilePreviewDTO) -> String {
        Bundle.appPluralizedString(key: "discover.profile.recipe-count", count: profile.recipeCount)
    }

    private var description: String? {
        let text = profile.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// In the iPad grid every card keeps four description lines, so cards in a row are one height.
    private var reservesDescriptionSpace: Bool { layoutMode == .padRegular }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiscoverAuthorCollage(username: profile.username, recipes: profile.previewRecipes)

            VStack(alignment: .leading, spacing: 0) {
                DiscoverAvatar(
                    avatarURL: DiscoverImageURLs.avatar(username: profile.username),
                    size: Self.avatarSize
                )
                .background {
                    // The prototype's `outline: 3px solid`; also covers the photo under the
                    // translucent avatar placeholder.
                    RoundedRectangle(cornerRadius: 8 + Self.avatarRing, style: .continuous)
                        .fill(Self.ringColor)
                        .padding(-Self.avatarRing)
                }
                .padding(.top, -Self.avatarSize / 2)

                Text(verbatim: Self.displayName(for: profile))
                    .font(AppTypography.sansMedium(17))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 8)

                if let description {
                    Text(verbatim: description)
                        .appBody()
                        .foregroundStyle(.primary)
                        .lineLimit(4, reservesSpace: reservesDescriptionSpace)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                } else if reservesDescriptionSpace {
                    Text(verbatim: " ")
                        .appBody()
                        .lineLimit(4, reservesSpace: true)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }

                Text(verbatim: Self.recipeCountText(for: profile))
                    .font(AppTypography.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 8)
            }
            .padding(.horizontal, style == .outlined ? 14 : 0)
            .padding(.bottom, style == .outlined ? 14 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(DiscoverAuthorCardFrame(style: style, cornerRadius: Self.cornerRadius))
    }
}

private struct DiscoverAuthorCardFrame: ViewModifier {
    let style: DiscoverAuthorCard.Style
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .plain:
            content.contentShape(Rectangle())
        case .outlined:
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color(.separator), lineWidth: 1))
                .contentShape(shape)
        }
    }
}

/// 16:9 collage: the height follows the card width only (not Dynamic Type), and a failed
/// photo keeps its tile, so neighbours never move.
private struct DiscoverAuthorCollage: View {
    let username: String
    let recipes: [DiscoverPreviewRecipeDTO]

    private var layout: DiscoverAuthorCollageLayout {
        DiscoverAuthorCollageLayout(photoCount: recipes.count)
    }

    var body: some View {
        Color.clear
            .aspectRatio(DiscoverAuthorCollageLayout.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if layout == .placeholder {
                    DiscoverAuthorCollageFill(showsIcon: true)
                } else {
                    GeometryReader { proxy in
                        let frames = layout.tileFrames(in: proxy.size)
                        ForEach(Array(recipes.prefix(frames.count).enumerated()), id: \.element.id) { index, recipe in
                            DiscoverAuthorCollageTile(url: DiscoverImageURLs.authorPreviewRecipe(recipe))
                                .frame(width: frames[index].width, height: frames[index].height)
                                // One node per tile, the tile's frame whether the photo is loaded or
                                // not. Inside the card's button VoiceOver reads only the button; UI
                                // tests find and tap the tile by this id.
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier(
                                    AccessibilityIdentifiers.discoverAuthorCardPhoto(
                                        username: username,
                                        index: index
                                    )
                                )
                                .position(x: frames[index].midX, y: frames[index].midY)
                        }
                    }
                }
            }
            .clipped()
    }
}

/// Photo tile: a fill while loading, the fill with an icon when the photo is missing or failed.
private struct DiscoverAuthorCollageTile: View {
    let url: URL?

    @State private var loadedImage: UIImage?
    @State private var loadFailed = false

    /// Lazy grid cells come back on re-scroll: take a cached photo synchronously, without a flash.
    private var displayedImage: UIImage? {
        if let loadedImage { return loadedImage }
        guard let url else { return nil }
        return DiscoverImageMemoryCache.image(for: url)
    }

    var body: some View {
        DiscoverAuthorCollageFill(showsIcon: displayedImage == nil && (url == nil || loadFailed))
            .overlay {
                if let displayedImage {
                    Image(uiImage: displayedImage)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: url) {
                await loadIfNeeded()
            }
    }

    private func loadIfNeeded() async {
        loadFailed = false
        guard let url else {
            loadedImage = nil
            return
        }
        if let cached = DiscoverImageMemoryCache.image(for: url) {
            loadedImage = cached
            return
        }
        // A new URL: the previous photo must not stay in the tile while this one loads.
        loadedImage = nil
        let image = await DiscoverImageLoader.loadImageRetryingInCapture(from: url)
        // A task cancelled by a newer URL must not overwrite that URL's photo.
        guard !Task.isCancelled else { return }
        loadedImage = image
        loadFailed = image == nil
    }
}

/// The prototype's `.ph` / `.ph.is-empty`: system fill, `fork.knife` in the tertiary label colour.
private struct DiscoverAuthorCollageFill: View {
    let showsIcon: Bool

    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill))
            .overlay {
                if showsIcon {
                    AppSymbol.sizedImage("fork.knife", pointSize: 28)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
    }
}
