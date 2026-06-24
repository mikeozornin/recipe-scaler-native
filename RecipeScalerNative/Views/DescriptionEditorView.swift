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

    @Environment(YjsSyncService.self) private var syncService
    @Environment(\.dismiss) private var dismiss
    @State private var bridge: DescriptionEditorBridge
    @State private var dismissBlockedMessage: String?

    init(recipeId: String, accentColor: Color, syncService: YjsSyncService) {
        self.recipeId = recipeId
        self.accentColor = accentColor
        _bridge = State(
            initialValue: DescriptionEditorBridge(
                recipeId: recipeId,
                syncService: syncService,
                presentation: .fullscreen
            )
        )
    }

    private var syncState: WriteSyncState {
        syncService.writeSyncState(for: recipeId)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DescriptionEditorWebView(bridge: bridge, allowsScrolling: true, accentColor: accentColor)
                    .opacity(bridge.phase == .ready ? 1 : 0.35)

                if bridge.phase == .loading {
                    ProgressView("description.editor.loading")
                        .padding()
                }

                if case .error(let message) = bridge.phase {
                    ContentUnavailableView {
                        AppEmptyState.label("description.editor.error.title", symbol: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                            .appBody()
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.descriptionEditor)
            .localizedNavigationTitle("description.editor.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("edit.cancel") {
                        Task { await closeEditor() }
                    }
                    .appToolbarTextButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("edit.done") {
                        Task { await closeEditor() }
                    }
                    .appToolbarConfirmButton()
                }
                ToolbarItem(placement: .principal) {
                    syncChip
                }
            }
            .errorAlert(title: "description.editor.syncInFlight.title", message: $dismissBlockedMessage)
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
            Text("edit.sync.pending")
                .appFootnote()
                .foregroundStyle(.secondary)
        case .syncing:
            Text("edit.sync.syncing")
                .appFootnote()
                .foregroundStyle(.secondary)
        case .queued:
            Text("edit.sync.queued")
                .appFootnote()
                .foregroundStyle(.secondary)
        case .error:
            Text("edit.sync.error")
                .appFootnote()
                .foregroundStyle(.red)
        }
    }

    private func closeEditor() async {
        if syncState == .syncing || syncState == .pendingLocal {
            dismissBlockedMessage = Bundle.currentLocalizedString("description.editor.syncInFlight.message")
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
            if let description = recipe.description, !description.isEmpty {
                StepsSection(htmlContent: description, accentColor: accentColor)
            } else {
                Text("description.editor.empty")
                    .appBody()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
            }

            Button(action: onEdit) {
                AppLabel.make("description.editor.open", symbol: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
        }
        .accessibilityIdentifier("description_editor_entry")
    }
}