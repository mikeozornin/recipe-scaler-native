//
//  DescriptionEditorView.swift
//  RecipeScalerNative
//
//  Full-screen rich text editor for v3 `Y.XmlFragment('description')` (006).
//

import SwiftUI

struct DescriptionEditorView: View {
    let recipeId: String
    let accentColor: Color

    @EnvironmentObject private var syncService: YjsSyncService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bridge: DescriptionEditorBridge
    @State private var dismissBlockedMessage: String?

    init(recipeId: String, accentColor: Color, syncService: YjsSyncService) {
        self.recipeId = recipeId
        self.accentColor = accentColor
        _bridge = StateObject(wrappedValue: DescriptionEditorBridge(recipeId: recipeId, syncService: syncService))
    }

    private var syncState: WriteSyncState {
        syncService.writeSyncState(for: recipeId)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DescriptionEditorWebView(bridge: bridge)
                    .opacity(bridge.phase == .ready ? 1 : 0.35)

                if bridge.phase == .loading {
                    ProgressView(String(localized: "description.editor.loading"))
                        .padding()
                }

                if case .error(let message) = bridge.phase {
                    ContentUnavailableView {
                        AppLabel.make(String(localized: "description.editor.error.title"), symbol: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.descriptionEditor)
            .navigationTitle(String(localized: "description.editor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "edit.cancel")) {
                        Task { await closeEditor() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "edit.done")) {
                        Task { await closeEditor() }
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .principal) {
                    syncChip
                }
            }
            .alert(
                String(localized: "description.editor.syncInFlight.title"),
                isPresented: Binding(
                    get: { dismissBlockedMessage != nil },
                    set: { if !$0 { dismissBlockedMessage = nil } }
                )
            ) {
                Button(String(localized: "edit.error.ok"), role: .cancel) {}
            } message: {
                Text(dismissBlockedMessage ?? "")
            }
        }
        .tint(accentColor)
        .task {
            await syncService.suspendRecipeRefresh()
        }
        .onDisappear {
            bridge.teardown()
            Task { await syncService.resumeRecipeRefresh() }
        }
    }

    @ViewBuilder
    private var syncChip: some View {
        switch syncState {
        case .idle, .synced:
            EmptyView()
        case .pendingLocal:
            Text(String(localized: "edit.sync.pending"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .syncing:
            Text(String(localized: "edit.sync.syncing"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .queued:
            Text(String(localized: "edit.sync.queued"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error:
            Text(String(localized: "edit.sync.error"))
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func closeEditor() async {
        if syncState == .syncing || syncState == .pendingLocal {
            dismissBlockedMessage = String(localized: "description.editor.syncInFlight.message")
            return
        }
        await bridge.flushPendingSync()
        dismiss()
    }
}

/// Edit-mode entry row on recipe detail (opens sheet editor).
struct DescriptionEditorEntrySection: View {
    let recipe: RecipeData
    let accentColor: Color
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "description.editor.section"))
                .font(.custom(AppFonts.display, size: 20))
                .foregroundStyle(accentColor)

            if let description = recipe.description, !description.isEmpty {
                StepsSection(htmlContent: description, accentColor: accentColor)
            } else {
                Text(String(localized: "description.editor.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: onEdit) {
                AppLabel.make(String(localized: "description.editor.open"), symbol: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
        }
        .padding(.horizontal)
        .accessibilityIdentifier("description_editor_entry")
    }
}