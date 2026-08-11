//
//  AppSidebarView.swift
//  RecipeScalerNative
//
//  Spec 063 — iPad sidebar. Reuses `AppTab` (symbols, titles, accessibility IDs)
//  so the sidebar mirrors the iPhone tab bar 1:1 in semantics. Selection goes
//  through `AppShellCoordinator.handleSidebarSelection` so import remains a
//  sentinel that never becomes the active column.
//

import SwiftUI

/// Sidebar for `.regular` horizontal size class (iPad).
/// On `.compact` (iPhone) the app keeps the existing `TabView` — see `AppShellView`.
struct AppSidebarView: View {
    @Bindable private var coordinator: AppShellCoordinator

    init(coordinator: AppShellCoordinator) {
        _coordinator = Bindable(wrappedValue: coordinator)
    }

    var body: some View {
        List(selection: sidebarSelection) {
            Section {
                sidebarRow(.discover)
                sidebarRow(.recipes)
                sidebarRow(.shopping)
            }
            Section {
                // Import is a sentinel row: it presents a sheet and never
                // becomes the selected sidebar column, so it lives outside
                // the selectable section and carries no `.tag`.
                importRow
            }
            Section {
                sidebarRow(.profile)
            }
        }
        .localizedNavigationTitle("splash.app-name")
        .navigationBarTitleDisplayMode(.large)
        #if os(iOS)
        .listStyle(.sidebar)
        #endif
    }

    @ViewBuilder
    private func sidebarRow(_ tab: AppTab) -> some View {
        Button {
            coordinator.handleSidebarSelection(tab)
        } label: {
            Label {
                Text(tab.title)
            } icon: {
                Image(systemName: tab.tabBarSymbol)
            }
        }
        .buttonStyle(.plain)
        .tag(tab)
        .accessibilityIdentifier(Self.sidebarAccessibilityId(for: tab))
    }

    @ViewBuilder
    private var importRow: some View {
        Button {
            coordinator.presentImport()
        } label: {
            Label {
                Text(AppTab.importTab.title)
            } icon: {
                Image(systemName: AppTab.importTab.tabBarSymbol)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(Self.sidebarAccessibilityId(for: .importTab))
    }

    private var sidebarSelection: Binding<AppTab?> {
        Binding(
            get: { coordinator.selectedTab == .importTab ? nil : coordinator.selectedTab },
            set: { newValue in
                guard let newValue else { return }
                coordinator.handleSidebarSelection(newValue)
            }
        )
    }

    /// Maps an `AppTab` to the sidebar-row accessibility identifier.
    /// Distinct from `AppTab.accessibilityId` (which targets the tab-bar button)
    /// so XCUITest can address the sidebar row on iPad without ambiguity.
    static func sidebarAccessibilityId(for tab: AppTab) -> String {
        switch tab {
        case .discover: return AccessibilityIdentifiers.sidebarDiscover
        case .importTab: return AccessibilityIdentifiers.sidebarImport
        case .recipes: return AccessibilityIdentifiers.sidebarRecipes
        case .shopping: return AccessibilityIdentifiers.sidebarShopping
        case .profile: return AccessibilityIdentifiers.sidebarProfile
        }
    }
}
