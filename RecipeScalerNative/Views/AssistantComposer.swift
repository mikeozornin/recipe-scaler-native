//
//  AssistantComposer.swift
//  RecipeScalerNative
//
//  Bottom composer for AssistantSheet: text input + attach-recipes + send.
//  Mirrors `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-composer.tsx`
//  layout (card shell, field on top, toolbar below). Voice recording comes in P3.
//

import SwiftUI
import RecipeScalerCore

struct AssistantComposer: View {
    private static let shellCornerRadius: CGFloat = 16

    @Binding var text: String
    @Binding var attachments: [AssistantRecipeAttachment]
    let isSending: Bool
    let inputPlaceholderVariantIndex: Int
    let onSend: () -> Void

    @Environment(\.locale) private var locale
    @EnvironmentObject private var syncService: YjsSyncService
    @State private var showAttachSheet = false

    private var inputPlaceholder: String {
        _ = locale
        return AssistantInputPlaceholder.localizedVariant(index: inputPlaceholderVariantIndex)
    }

    var body: some View {
        composerShell
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantComposerShell)
            .sheet(isPresented: $showAttachSheet) {
                AssistantRecipePicker(
                    attachments: $attachments,
                    availableEntries: availableEntries
                )
                .presentationDetents([.medium, .large])
            }
    }

    // MARK: - Shell

    private var composerShell: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !attachments.isEmpty {
                attachmentsRow
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            TextField("", text: $text, prompt: Text(verbatim: inputPlaceholder), axis: .vertical)
                .appBodyFieldTypography()
                .lineLimit(1...6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, attachments.isEmpty ? 12 : 4)
                .padding(.bottom, 4)
                .accessibilityIdentifier(AccessibilityIdentifiers.assistantMessageInput)

            composerToolbar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.shellCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.shellCornerRadius, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
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
        }
    }

    private var composerToolbar: some View {
        HStack(spacing: 0) {
            attachButton
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                voiceButton
                sendButton
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, 2)
        .padding(.bottom, 2)
    }

    private var attachButton: some View {
        Button {
            showAssistantAttachOpen()
        } label: {
            composerIconOnly(systemName: "plus")
        }
        .appToolbarIconButton()
        .accessibilityLabel(Text("assistant.attach-recipes"))
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantAttachmentButton)
        .disabled(availableEntries.isEmpty)
        .opacity(availableEntries.isEmpty ? 0.4 : 1)
    }

    private var voiceButton: some View {
        Button {
            // Voice recording — P3
        } label: {
            composerIconOnly(systemName: "mic")
        }
        .appToolbarIconButton()
        .accessibilityLabel(Text("assistant.voice-record"))
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantVoiceRecordButton)
        .disabled(true)
        .opacity(0.4)
    }

    private var sendButton: some View {
        Button {
            onSend()
        } label: {
            if isSending {
                ProgressView()
                    .tint(Color.primary)
                    .frame(width: AppToolbarStyle.iconSide, height: AppToolbarStyle.iconSide)
                    .frame(width: AppToolbarStyle.minimumTapSide, height: AppToolbarStyle.minimumTapSide)
            } else {
                composerIconOnly(systemName: "paperplane")
            }
        }
        .appToolbarIconButton()
        .accessibilityLabel(Text("assistant.send"))
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantSendButton)
        .disabled(!canSend)
    }

    @ViewBuilder
    private func composerIconOnly(systemName: String) -> some View {
        AppSymbol.toolbarImage(systemName)
            .resizable()
            .scaledToFit()
            .frame(width: AppToolbarStyle.iconSide, height: AppToolbarStyle.iconSide)
            .foregroundStyle(Color.primary)
            .frame(width: AppToolbarStyle.minimumTapSide, height: AppToolbarStyle.minimumTapSide)
            .contentShape(Rectangle())
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

enum AssistantInputPlaceholder {
    static let variantCount = 8

    static func localizedVariant(index: Int) -> String {
        let clamped = ((index % variantCount) + variantCount) % variantCount
        return Bundle.currentLocalizedString("assistant.input-placeholder-variants.\(clamped)")
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
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
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

    private var attachableEntries: [CollectionEntry] {
        availableEntries.filter { entry in
            !attachments.contains { $0.recipeId == entry.id }
        }
    }

    private var filtered: [CollectionEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(attachableEntries.prefix(50)) }
        let tokens = RecipeSearchUtils.tokenizeQuery(trimmed)
        guard !tokens.isEmpty else { return [] }
        return attachableEntries
            .filter { RecipeSearchUtils.matchesName($0.name, tokens: tokens) }
            .prefix(50)
            .map { $0 }
    }

    private func select(_ entry: CollectionEntry) {
        guard attachments.count < 10 else {
            dismiss()
            return
        }
        attachments.append(
            AssistantRecipeAttachment(
                recipeId: entry.id,
                recipeName: entry.name,
                recipeColor: entry.color
            )
        )
        dismiss()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if !availableEntries.isEmpty {
                    attachRecipesIntro
                }

                if availableEntries.isEmpty {
                    ContentUnavailableView(
                        Bundle.currentLocalizedString("assistant.no-recipes-found"),
                        systemImage: "book"
                    )
                } else if attachableEntries.isEmpty {
                    ContentUnavailableView(
                        Bundle.currentLocalizedString("assistant.no-recipes-found"),
                        systemImage: "book"
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        Bundle.currentLocalizedString("assistant.no-recipes-found"),
                        systemImage: "magnifyingglass"
                    )
                } else {
                    List(filtered) { entry in
                        Button {
                            select(entry)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: entry.color) ?? .accentColor)
                                    .frame(width: 10, height: 10)
                                Text(entry.name)
                                    .appBody()
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
                        .accessibilityIdentifier("assistant_recipe_picker_row_\(entry.id)")
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("assistant.recipe-search-placeholder")
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("assistant.close") { dismiss() }
                        .appToolbarTextButton()
                }
            }
        }
    }

    private var attachRecipesIntro: some View {
        Text("assistant.attach-recipe")
            .font(AppTypography.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
            .padding(.top, RecipeRowLayoutMetrics.listHorizontalInset)
            .padding(.bottom, 8)
    }
}
