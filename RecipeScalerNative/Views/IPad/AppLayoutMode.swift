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
            .modifier(DebugWindowWidthModifier(width: DebugLaunchOptions.debugWindowWidth))
    }
}

/// `-DebugWindowWidth=<pt>` (DEBUG only): narrows the root to `width`, pinned to the
/// leading edge, and sets the horizontal size class by `IPadLayoutMetrics.regularMinWidth`.
/// Without the argument (and in Release) the content is returned untouched.
private struct DebugWindowWidthModifier: ViewModifier {
    let width: CGFloat?

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
        } else {
            content
        }
        #else
        content
        #endif
    }
}
