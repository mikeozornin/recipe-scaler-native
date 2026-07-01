//
//  AppShellChrome.swift
//  RecipeScalerNative
//
//  Shared sheets, assistant, status — compact and regular shells.
//

import SwiftUI
import RecipeScalerCore
#if canImport(UIKit)
import UIKit
#endif

struct AppShellChrome: ViewModifier {
    @Bindable var coordinator: AppShellCoordinator
    @Binding var showAssistant: Bool
    @Binding var assistantContextRecipeId: String?
    @Binding var transientStatusMessage: String?
    var transientStatusDismissTask: Binding<Task<Void, Never>?>
    var showsAssistantFab: Bool
    var assistantFabBottomPadding: CGFloat
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(YjsSyncService.self) private var syncService

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let transientStatusMessage {
                    TransientStatusBanner(message: transientStatusMessage)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 72)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: transientStatusMessage != nil)
            .sheet(item: $coordinator.importPresentation) { _ in
                ImportRecipeSheet { result in
                    if let message = coordinator.completeImport(result) {
                        postTransientStatus(message)
                    }
                }
            }
            .onChange(of: showAssistant) { _, isOpen in
                assistantRecipeContext.isAssistantSheetOpen = isOpen
            }
            .sheet(isPresented: $showAssistant, onDismiss: {
                assistantRecipeContext.isAssistantSheetOpen = false
                assistantContextRecipeId = nil
            }) {
                AssistantSheet(
                    contextRecipeId: assistantContextRecipeId ?? assistantRecipeContext.visibleRecipeId
                )
            }
            .overlay(alignment: .bottomTrailing) {
                if showsAssistantFab, !showAssistant {
                    AssistantFabButton {
                        assistantContextRecipeId = assistantRecipeContext.visibleRecipeId
                        assistantRecipeContext.isAssistantSheetOpen = true
                        showAssistant = true
                    }
                    .padding(.trailing, AssistantFabStyle.margin)
                    .padding(.bottom, assistantFabBottomPadding)
                    .accessibilityIdentifier(AccessibilityIdentifiers.assistantFab)
                    .accessibilityLabel(Text("assistant.title"))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shoppingStatusMessage)) { notification in
                guard let message = notification.object as? String, !message.isEmpty else { return }
                transientStatusDismissTask.wrappedValue?.cancel()
                withAnimation(.easeInOut(duration: 0.25)) {
                    transientStatusMessage = message
                }
                let shownMessage = message
                transientStatusDismissTask.wrappedValue = Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if transientStatusMessage == shownMessage {
                            transientStatusMessage = nil
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRecipeRequested)) { _ in
                coordinator.consumePendingRecipeIdIfNeeded()
            }
            .onChange(of: deepLinkRouter.pending) { _, link in
                guard let link else { return }
                coordinator.handleDeepLink(link)
            }
            .onChange(of: syncService.collectionEntries) { _, entries in
                coordinator.resolvePendingSpotlightRecipe(in: entries)
            }
            .onAppear {
                RecipeImageDiskCache.migrateFromCachesIfNeeded()
            }
    }

    private func postTransientStatus(_ message: String) {
        NotificationCenter.default.post(name: .shoppingStatusMessage, object: message)
    }
}

extension View {
    func appShellChrome(
        coordinator: AppShellCoordinator,
        showAssistant: Binding<Bool>,
        assistantContextRecipeId: Binding<String?>,
        transientStatusMessage: Binding<String?>,
        transientStatusDismissTask: Binding<Task<Void, Never>?>,
        showsAssistantFab: Bool,
        assistantFabBottomPadding: CGFloat
    ) -> some View {
        modifier(
            AppShellChrome(
                coordinator: coordinator,
                showAssistant: showAssistant,
                assistantContextRecipeId: assistantContextRecipeId,
                transientStatusMessage: transientStatusMessage,
                transientStatusDismissTask: transientStatusDismissTask,
                showsAssistantFab: showsAssistantFab,
                assistantFabBottomPadding: assistantFabBottomPadding
            )
        )
    }
}