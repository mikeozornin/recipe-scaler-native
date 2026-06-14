//
//  AssistantComposer.swift
//  RecipeScalerNative
//
//  Bottom composer for AssistantSheet: text input + attach-recipes + send.
//  Mirrors `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-composer.tsx`
//  (subset for P2 — voice comes in P3).
//

import SwiftUI
import RecipeScalerCore

struct AssistantComposer: View {
    @Binding var text: String
    @Binding var attachments: [AssistantRecipeAttachment]
    let isSending: Bool
    let onSend: () -> Void

    @EnvironmentObject private var syncService: YjsSyncService
    @State private var showAttachSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                attachmentsRow
            }
            HStack(alignment: .bottom, spacing: 8) {
                attachButton
                TextField("assistant.input-placeholder", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                sendButton
            }
        }
        .sheet(isPresented: $showAttachSheet) {
            AssistantRecipePicker(
                attachments: $attachments,
                availableEntries: availableEntries
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Subviews

    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AssistantAttachmentChip(attachment: attachment) {
                        removeAttachment(attachment)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var attachButton: some View {
        Button {
            showAssistantAttachOpen()
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
        }
        .accessibilityLabel(Text("assistant.attach-recipes"))
        .disabled(availableEntries.isEmpty)
        .opacity(availableEntries.isEmpty ? 0.4 : 1)
    }

    private var sendButton: some View {
        Button {
            onSend()
        } label: {
            Text("assistant.send")
                .padding(.horizontal, 4)
        }
        .disabled(!canSend)
    }

    private var canSend: Bool {
        !isSending && (
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
        )
    }

    private var availableEntries: [CollectionEntry] {
        // Exclude soft-deleted entries; keep order stable (collectionEntries is already ordered by the sync layer).
        syncService.collectionEntries.filter { !$0.deleted }
    }

    // MARK: - Actions

    private func showAssistantAttachOpen() {
        showAttachSheet = true
    }

    private func removeAttachment(_ attachment: AssistantRecipeAttachment) {
        attachments.removeAll { $0.recipeId == attachment.recipeId }
    }
}

// MARK: - Attachment chip

private struct AssistantAttachmentChip: View {
    let attachment: AssistantRecipeAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: attachment.recipeColor ?? "") ?? .accentColor)
                .frame(width: 8, height: 8)
            Text(attachment.recipeName ?? attachment.recipeId)
                .font(.footnote)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }
            .accessibilityLabel(Text("assistant.remove-attached-recipe"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Recipe picker sheet

struct AssistantRecipePicker: View {
    @Binding var attachments: [AssistantRecipeAttachment]
    let availableEntries: [CollectionEntry]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [CollectionEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(availableEntries.prefix(50)) }
        let tokens = RecipeSearchUtils.tokenizeQuery(trimmed)
        guard !tokens.isEmpty else { return [] }
        return availableEntries
            .filter { RecipeSearchUtils.matchesName($0.name, tokens: tokens) }
            .prefix(50)
            .map { $0 }
    }

    private func isSelected(_ entry: CollectionEntry) -> Bool {
        attachments.contains { $0.recipeId == entry.id }
    }

    private func toggle(_ entry: CollectionEntry) {
        if let idx = attachments.firstIndex(where: { $0.recipeId == entry.id }) {
            attachments.remove(at: idx)
        } else if attachments.count < 10 {
            attachments.append(
                AssistantRecipeAttachment(
                    recipeId: entry.id,
                    recipeName: entry.name,
                    recipeColor: entry.color
                )
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if availableEntries.isEmpty {
                    ContentUnavailableView(
                        Bundle.currentLocalizedString("assistant.no-recipes-found"),
                        systemImage: "book"
                    )
                } else {
                    List(filtered) { entry in
                        Button {
                            toggle(entry)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: entry.color) ?? .accentColor)
                                    .frame(width: 10, height: 10)
                                Text(entry.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSelected(entry) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityIdentifier("assistant_recipe_picker_row_\(entry.id)")
                    }
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("assistant.recipe-search-placeholder")
            )
            .localizedNavigationTitle("assistant.attach-recipes.menu-title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("assistant.close") { dismiss() }
                        .appToolbarTextButton()
                }
            }
        }
    }
}
