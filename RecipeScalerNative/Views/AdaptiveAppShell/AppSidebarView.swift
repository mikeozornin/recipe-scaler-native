//
//  AppSidebarView.swift
//  RecipeScalerNative
//
//  Spec 043 — system sidebar (HIG), not web icon strip.
//

import SwiftUI

/// System-style macOS / iPadOS sidebar.
///
/// The rows use `List(selection:)` + system `Label` + `.tag()` so the platform
/// owns the sidebar chrome and typography: translucency, hover, system
/// selection accent, full keyboard navigation (arrow keys + Return) and the
/// correct sidebar-row font metrics. Earlier revisions drew the selection pill,
/// forced a 44 pt mobile row height and overrode the label with `.appBody()`,
/// which made the sidebar read as an iOS cell list instead of a native
/// Mail/Settings surface.
///
/// Import and Assistant are action rows, not destinations: they never mutate
/// `selectedTab` and stay outside the selection binding. They are reachable
/// from every regular surface so the user does not have to switch tabs first.
struct AppSidebarView: View {
    @Bindable var coordinator: AppShellCoordinator
    @Binding var showAssistant: Bool

    private var selectionBinding: Binding<AppTab?> {
        Binding(
            get: { coordinator.selectedTab },
            set: { newValue in
                guard let newValue else { return }
                coordinator.handleSidebarSelection(newValue)
            }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                sidebarLabel(.discover)
                    .tag(AppTab.discover)
                    .accessibilityIdentifier(sidebarAccessibilityId(.discover))
                sidebarLabel(.recipes)
                    .tag(AppTab.recipes)
                    .accessibilityIdentifier(sidebarAccessibilityId(.recipes))
                sidebarLabel(.shopping)
                    .tag(AppTab.shopping)
                    .accessibilityIdentifier(sidebarAccessibilityId(.shopping))
            }

            Section {
                // Import is an action, not a destination: it never mutates
                // `selectedTab` and therefore stays outside the selection
                // binding. The system still renders it as a sidebar row.
                Button {
                    coordinator.presentImport()
                } label: {
                    sidebarLabel(.importTab)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(sidebarAccessibilityId(.importTab))

                #if os(macOS)
                // Mac sidebar owns generic assistant launch so the chat is
                // reachable from every surface. iPad keeps assistant on the
                // toolbar / FAB and is intentionally not changed here.
                Button {
                    showAssistant = true
                } label: {
                    Label("assistant.title", systemImage: "sparkles")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityIdentifiers.assistantToolbarButton)
                #endif

                sidebarLabel(.profile)
                    .tag(AppTab.profile)
                    .accessibilityIdentifier(sidebarAccessibilityId(.profile))
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarLabel(_ tab: AppTab) -> Label<Text, Image> {
        Label(tab.title, systemImage: tab.tabBarSymbol)
    }

    private func sidebarAccessibilityId(_ tab: AppTab) -> String {
        switch tab {
        case .discover: AccessibilityIdentifiers.sidebarDiscover
        case .importTab: AccessibilityIdentifiers.sidebarImport
        case .recipes: AccessibilityIdentifiers.sidebarRecipes
        case .shopping: AccessibilityIdentifiers.sidebarShopping
        case .profile: AccessibilityIdentifiers.sidebarProfile
        }
    }
}
