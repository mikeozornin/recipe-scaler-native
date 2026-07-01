//
//  AppSidebarView.swift
//  RecipeScalerNative
//
//  Spec 043 — system sidebar (HIG), not web icon strip.
//

import SwiftUI

struct AppSidebarView: View {
    @Bindable var coordinator: AppShellCoordinator

    private static let navigableTabs: [AppTab] = [
        .discover, .importTab, .recipes, .shopping, .profile,
    ]

    var body: some View {
        List {
            ForEach(Self.navigableTabs, id: \.self) { tab in
                Button {
                    if tab == .importTab {
                        coordinator.presentImport()
                    } else {
                        coordinator.handleSidebarSelection(tab)
                    }
                } label: {
                    Label {
                        Text(tab.title)
                            .appBody()
                    } icon: {
                        Image(systemName: tab.tabBarSymbol)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .listRowBackground(rowBackground(tab))
                .accessibilityIdentifier(sidebarAccessibilityId(tab))
                .accessibilityAddTraits(tab == coordinator.selectedTab && tab != .importTab ? .isSelected : [])
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func rowBackground(_ tab: AppTab) -> some View {
        if tab == coordinator.selectedTab, tab != .importTab {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.15))
        } else {
            Color.clear
        }
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