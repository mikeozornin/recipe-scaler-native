import SwiftUI

/// Primary sections shared by the compact tab bar and the regular sidebar.
///
/// The navigation model is platform-neutral; only the presentation changes:
/// iPhone/iPad compact uses `TabView`, while iPad regular and macOS use the
/// system sidebar.
enum AppTab: String, CaseIterable, Hashable {
    case discover
    case importTab
    case recipes
    case shopping
    case profile

    var title: LocalizedStringKey {
        switch self {
        case .discover: "discover.nav.discover"
        case .importTab: "discover.nav.import"
        case .recipes: "discover.nav.my-recipes"
        case .shopping: "discover.nav.shopping"
        case .profile: "discover.nav.profile"
        }
    }

    /// Outline SF Symbol for the compact tab bar. The selected platform chrome
    /// supplies its own selected/active treatment.
    var tabBarSymbol: String {
        switch self {
        case .discover: "globe"
        case .importTab: "square.and.arrow.down"
        case .recipes: "book"
        case .shopping: "cart"
        case .profile: "person"
        }
    }

    var accessibilityId: String {
        switch self {
        case .discover: AccessibilityIdentifiers.tabDiscover
        case .importTab: AccessibilityIdentifiers.tabImport
        case .recipes: AccessibilityIdentifiers.tabRecipes
        case .shopping: AccessibilityIdentifiers.tabShopping
        case .profile: AccessibilityIdentifiers.tabProfile
        }
    }
}

/// Label used by the compact iOS tab bar. Kept out of `AppShellView` so the
/// regular shell can be compiled into the native macOS target independently.
struct AppTabBarLabel: View {
    let tab: AppTab

    var body: some View {
        Label(tab.title, systemImage: tab.tabBarSymbol)
            .font(AppTypography.tabBar)
            .accessibilityIdentifier(tab.accessibilityId)
    }
}
