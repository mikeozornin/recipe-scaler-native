import SwiftUI
import UIKit
#if DEBUG
import notify
#endif

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
                live: DebugLaunchOptions.debugWindowWidthLive,
                compactInPortrait: DebugLaunchOptions.debugCompactInPortrait
            ))
    }
}

/// `-DebugWindowWidth=<pt>` (DEBUG only): narrows the root to `width`, pinned to the
/// leading edge, and sets the horizontal size class by `IPadLayoutMetrics.regularMinWidth`.
///
/// `-DebugWindowWidthLive=1` (DEBUG only): the same, with the width taken from
/// `DebugWindowWidthChannel` at runtime (no width = the whole window and the system size
/// class). One view structure for every width, so a change is a resize of the same tree,
/// as in Split View or Stage Manager, not a new app.
///
/// `-DebugCompactInPortrait=1` (DEBUG only): in portrait the root narrows to a ½ window
/// (402 pt, layout.md §Матрица) with a compact size class; landscape stays regular, so a
/// rotation is a runtime size class change (spec 081, T035).
///
/// Without the arguments (and in Release) the content is returned untouched.
private struct DebugWindowWidthModifier: ViewModifier {
    let width: CGFloat?
    let live: Bool
    let compactInPortrait: Bool
    /// The root with the keyboard hidden: typing in portrait keeps it portrait.
    @State private var sizeWithoutKeyboard: CGSize?
    #if DEBUG
    @Environment(\.horizontalSizeClass) private var systemSizeClass
    #endif

    func body(content: Content) -> some View {
        #if DEBUG
        if live {
            let liveWidth = DebugWindowWidthChannel.shared.width
            content
                .environment(\.horizontalSizeClass, liveWidth.map(Self.sizeClass(for:)) ?? systemSizeClass)
                .frame(width: liveWidth)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    DebugWindowWidthChannel.shared.reportApplied(width: $0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if let width {
            content
                .environment(\.horizontalSizeClass, Self.sizeClass(for: width))
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

    private static func sizeClass(for width: CGFloat) -> UserInterfaceSizeClass {
        width >= IPadLayoutMetrics.regularMinWidth ? .regular : .compact
    }
}

#if DEBUG
/// The runtime width of `-DebugWindowWidthLive=1`, over Darwin notifications, so a UI test
/// process can resize the app's window (spec 081, T049):
///   - `ru.recipescaler.debug.window-width`: the test sets the state to the width in points
///     (0 = the whole window) and posts the name;
///   - `ru.recipescaler.debug.window-width.applied`: the app sets the state to the width the
///     root got and posts the name, so the test knows the resize has reached the layout.
/// A state lives while some process holds the name: both sides register before use.
@MainActor
@Observable
final class DebugWindowWidthChannel {
    static let widthName = "ru.recipescaler.debug.window-width"
    static let appliedName = "ru.recipescaler.debug.window-width.applied"
    static let shared = DebugWindowWidthChannel()

    /// `nil` — the whole window.
    private(set) var width: CGFloat? = DebugLaunchOptions.debugWindowWidth
    @ObservationIgnored private var appliedToken = NOTIFY_TOKEN_INVALID

    private init() {
        var widthToken = NOTIFY_TOKEN_INVALID
        notify_register_dispatch(Self.widthName, &widthToken, .main) { token in
            var state: UInt64 = 0
            notify_get_state(token, &state)
            MainActor.assumeIsolated {
                DebugWindowWidthChannel.shared.width = state > 0 ? CGFloat(state) : nil
            }
        }
        notify_register_check(Self.appliedName, &appliedToken)
    }

    func reportApplied(width: CGFloat) {
        notify_set_state(appliedToken, UInt64(width.rounded()))
        notify_post(Self.appliedName)
    }
}
#endif
