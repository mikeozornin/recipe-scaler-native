import SwiftUI
import UIKit

/// Layout mode of the whole app (spec 081, plan.md Р1). Resolved once at the root
/// (`ContentView.rootChrome`) and read from the environment by every iPad branch.
/// Device model and orientation never take part (FR-030).
enum AppLayoutMode: Equatable {
    /// iPhone, and iPad in a compact window: the phone paths.
    case phone
    /// iPad in a regular-width window: sidebar, columns, inspector.
    case padRegular

    /// iPhone is always `.phone` — the main invariant.
    static func resolve(
        idiom: UIUserInterfaceIdiom,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> AppLayoutMode {
        idiom == .pad && horizontalSizeClass == .regular ? .padRegular : .phone
    }
}

extension EnvironmentValues {
    /// `.phone` until the root resolves it, so previews and isolated views keep the phone layout.
    @Entry var appLayoutMode: AppLayoutMode = .phone
}

/// Publishes `AppLayoutMode` for everything below the app root.
private struct AppLayoutModeRootModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.environment(
            \.appLayoutMode,
            AppLayoutMode.resolve(
                idiom: UIDevice.current.userInterfaceIdiom,
                horizontalSizeClass: horizontalSizeClass
            )
        )
    }
}

extension View {
    /// Applied once, in `ContentView.rootChrome`.
    func appLayoutModeRoot() -> some View {
        modifier(AppLayoutModeRootModifier())
            // Outside the resolver, so the overridden size class reaches it.
            .modifier(DebugWindowWidthModifier(
                width: DebugLaunchOptions.debugWindowWidth,
                compactInPortrait: DebugLaunchOptions.debugCompactInPortrait
            ))
    }
}

/// `-DebugWindowWidth=<pt>` (DEBUG only): narrows the root to `width`, pinned to the
/// leading edge, and sets the horizontal size class by `IPadLayoutMetrics.regularMinWidth`.
///
/// `-DebugCompactInPortrait=1` (DEBUG only): in portrait the root narrows to a ½ window
/// (402 pt, layout.md §Матрица) with a compact size class; landscape stays regular, so a
/// rotation is a runtime size class change (spec 081, T035).
///
/// Without the arguments (and in Release) the content is returned untouched.
private struct DebugWindowWidthModifier: ViewModifier {
    let width: CGFloat?
    let compactInPortrait: Bool
    /// The root with the keyboard hidden: typing in portrait keeps it portrait.
    @State private var sizeWithoutKeyboard: CGSize?

    func body(content: Content) -> some View {
        #if DEBUG
        if let width {
            content
                .environment(
                    \.horizontalSizeClass,
                    width >= IPadLayoutMetrics.regularMinWidth ? .regular : .compact
                )
                .frame(width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if compactInPortrait {
            GeometryReader { proxy in
                let height = IPadLayoutPolicy.contentHeightIgnoringKeyboard(
                    current: proxy.size,
                    withoutKeyboard: sizeWithoutKeyboard
                )
                let isPortrait = height > proxy.size.width
                content
                    .environment(\.horizontalSizeClass, isPortrait ? .compact : .regular)
                    .frame(width: isPortrait ? 402 : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .background {
                Color.clear
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { sizeWithoutKeyboard = $0 }
                    .ignoresSafeArea(.keyboard)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
