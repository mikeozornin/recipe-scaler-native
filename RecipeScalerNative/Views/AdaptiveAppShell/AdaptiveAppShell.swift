//
//  AdaptiveAppShell.swift
//  RecipeScalerNative
//
//  Spec 043 — compact TabView vs regular NavigationSplitView.
//

import SwiftUI
import RecipeScalerCore
#if canImport(UIKit)
import UIKit
#endif

struct AdaptiveAppShell: View {
    @Bindable private var coordinator: AppShellCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(TimerManager.self) private var timerManager
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext
    @State private var showAssistant = false
    @State private var assistantContextRecipeId: String?
    @State private var transientStatusMessage: String?
    @State private var transientStatusDismissTask: Task<Void, Never>?
    @State private var mobileTimerPanelCollapsed = true
    @State private var tabBarTopOffsetFromLayoutBottom: CGFloat = 0

    init(syncService: YjsSyncService, deepLinkRouter: DeepLinkRouter) {
        _coordinator = Bindable(
            wrappedValue: AppShellCoordinator(
                syncService: syncService,
                deepLinkRouter: deepLinkRouter
            )
        )
    }

    private var layoutMode: LayoutMode {
        #if DEBUG
        if let forced = DebugLaunchOptions.forceLayout {
            return forced
        }
        #endif
        return LayoutModeResolver.resolve(
            horizontalSizeClass: horizontalSizeClass,
            forceLayout: nil
        )
    }

    private var showsAssistantFab: Bool {
        layoutMode == .compact
    }

    private var assistantFabBottomPadding: CGFloat {
        let timerHeight = MobileTimerPanelLayout.height(
            timerCount: timerManager.timers.count,
            isExpanded: !mobileTimerPanelCollapsed
        )
        let tabBarOffset = tabBarTopOffsetFromLayoutBottom > 0
            ? tabBarTopOffsetFromLayoutBottom
            : Self.fallbackTabBarTopOffsetFromLayoutBottom
        return tabBarOffset + timerHeight + AssistantFabStyle.margin
    }

    private static var fallbackTabBarTopOffsetFromLayoutBottom: CGFloat { 49 }

    @ViewBuilder
    private var adaptiveShellRoot: some View {
        switch layoutMode {
        case .compact:
            CompactAppShell(
                coordinator: coordinator,
                showAssistant: $showAssistant,
                mobileTimerPanelCollapsed: $mobileTimerPanelCollapsed,
                tabBarTopOffsetFromLayoutBottom: $tabBarTopOffsetFromLayoutBottom
            )
        case .regular:
            RegularAppShell(
                coordinator: coordinator,
                showAssistant: $showAssistant,
                assistantContextRecipeId: $assistantContextRecipeId
            )
        }
    }

    var body: some View {
        adaptiveShellRoot
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onChange(of: layoutMode) { _, mode in
            coordinator.usesRegularRecipeSplit = mode == .regular
        }
        .onAppear {
            coordinator.usesRegularRecipeSplit = layoutMode == .regular
        }
        .environment(\.interactionProfile, InteractionProfile.current)
        .environment(
            \.featureAdoptionAppCta,
            makeFeatureAdoptionAppCtaHandler()
        )
        .appShellChrome(
            coordinator: coordinator,
            showAssistant: $showAssistant,
            assistantContextRecipeId: $assistantContextRecipeId,
            transientStatusMessage: $transientStatusMessage,
            transientStatusDismissTask: $transientStatusDismissTask,
            showsAssistantFab: showsAssistantFab,
            assistantFabBottomPadding: assistantFabBottomPadding
        )
        #if DEBUG
        .onAppear {
            coordinator.openDebugTabIfNeeded(DebugLaunchOptions.openTab)
            if DebugLaunchOptions.mobileTimerPanelExpanded {
                mobileTimerPanelCollapsed = false
            }
            if DebugLaunchOptions.showAssistant {
                assistantContextRecipeId = assistantRecipeContext.visibleRecipeId
                assistantRecipeContext.isAssistantSheetOpen = true
                showAssistant = true
            }
            coordinator.consumePendingRecipeIdIfNeeded()
        }
        #else
        .onAppear {
            coordinator.consumePendingRecipeIdIfNeeded()
        }
        #endif
    }

    private func makeFeatureAdoptionAppCtaHandler() -> FeatureAdoptionAppCtaHandler {
        FeatureAdoptionAppCtaHandler(
            openAssistant: {
                Task { @MainActor in
                    showAssistant = true
                    assistantRecipeContext.isAssistantSheetOpen = true
                }
            },
            openImport: {
                Task { @MainActor in
                    coordinator.presentImport()
                }
            },
            openSafari: { url in
                Task { @MainActor in
                    #if canImport(UIKit)
                    UIApplication.shared.open(url)
                    #endif
                }
            }
        )
    }
}

private struct InteractionProfileKey: EnvironmentKey {
    static let defaultValue: InteractionProfile = .touch
}

extension EnvironmentValues {
    var interactionProfile: InteractionProfile {
        get { self[InteractionProfileKey.self] }
        set { self[InteractionProfileKey.self] = newValue }
    }
}