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
    }
}
