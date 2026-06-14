//
//  AssistantComposer.swift
//  RecipeScalerNative
//
//  Bottom composer for AssistantSheet: text input + attach-recipes + send.
//  Mirrors `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-composer.tsx`
//  layout (card shell, field on top, toolbar below). Voice via AVFoundation + server transcribe.
//

import SwiftUI
import RecipeScalerCore

struct AssistantComposer: View {
    private static let shellCornerRadius: CGFloat = 16
    /// Web `min-h-12` — keeps the field height stable when placeholder disappears.
    private static let inputMinHeight: CGFloat = 48

    @Binding var text: String
    @Binding var attachments: [AssistantRecipeAttachment]
    let isSending: Bool
    let inputPlaceholderVariantIndex: Int
    let contextRecipeId: String?
    let onSend: () -> Void

    @Environment(\.locale) private var locale
    @EnvironmentObject private var syncService: YjsSyncService
    @State private var showAttachSheet = false
    @State private var recipeContext = AssistantRecipeContext.shared
    @State private var voiceRecorder = AssistantVoiceRecorder()
    @State private var voiceLimitAlertVisible = false
    @State private var voiceErrorMessage: String?
    @FocusState private var isInputFocused: Bool

    /// Snapshot from sheet open, with live fallback while the recipe screen stays mounted.
    private var effectiveContextRecipeId: String? {
        _ = recipeContext.visibleRecipeId
        return contextRecipeId ?? recipeContext.visibleRecipeId
    }

    private var inputPlaceholder: String {
        _ = locale
        return AssistantInputPlaceholder.localizedVariant(index: inputPlaceholderVariantIndex)
    }

    var body: some View {
        composerShell
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantComposerShell)
            .sheet(isPresented: $showAttachSheet) {
                AssistantRecipePicker(
                    attachments: $attachments,
                    availableEntries: availableEntries
                )
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                voiceRecorder.onLimitReached = {
                    voiceLimitAlertVisible = true
                }
                voiceRecorder.onAutoStopCapture = { data in
                    await transcribeCapturedAudio(data)
                }
            }
            .onDisappear {
                voiceRecorder.cancel()
            }
            .alert(
                "assistant.error-unavailable",
                isPresented: Binding(
                    get: { voiceErrorMessage != nil },
                    set: { if !$0 { voiceErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { voiceErrorMessage = nil }
            } message: {
                if let voiceErrorMessage {
                    Text(verbatim: voiceErrorMessage)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("edit.done") {
                        isInputFocused = false
                    }
                    .appToolbarTextButton()
                    .accessibilityIdentifier(AccessibilityIdentifiers.assistantKeyboardDone)
                }
            }
    }

    // MARK: - Shell

    private var composerShell: some View {
        VStack(alignment: .leading, spacing: 0) {
            if voiceLimitAlertVisible {
                voiceLimitAlert
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if !attachments.isEmpty {
                attachmentsRow
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            messageInput
                .padding(.horizontal, 16)
                .padding(.top, attachments.isEmpty ? 12 : 4)
                .padding(.bottom, 4)

            composerToolbar
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.shellCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.shellCornerRadius, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
                .allowsHitTesting(false)
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

    private var messageInput: some View {
        TextField(inputPlaceholder, text: $text, axis: .vertical)
            .appBodyFieldTypography()
            .lineLimit(1...6)
            .frame(maxWidth: .infinity, minHeight: Self.inputMinHeight, alignment: .topLeading)
            .focused($isInputFocused)
            .disabled(isComposerInputDisabled)
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantMessageInput)
    }

    private var isComposerInputDisabled: Bool {
        isSending || voiceRecorder.state == .transcribing
    }

    private var composerToolbar: some View {
        HStack(spacing: 0) {
            if voiceRecorder.state == .recording {
                AssistantVoiceLevelMeter(samples: voiceRecorder.samples)
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, minHeight: AppToolbarStyle.minimumTapSide)
                    .background(Color(.systemBackground))
            } else {
                HStack(spacing: 4) {
                    attachButton
                    if showContextRecipeTag, let contextAttachment {
                        contextRecipeTagButton(for: contextAttachment)
                    }
                }
                Spacer(minLength: 8)
            }
            voiceButton
            sendButton
        }
        .padding(.leading, 2)
        .padding(.trailing, 2)
        .padding(.bottom, 2)
    }

    private var contextRecipeEntry: CollectionEntry? {
        guard let effectiveContextRecipeId else { return nil }
        return syncService.collectionEntries.first {
            !$0.deleted && recipeIdsMatch($0.id, effectiveContextRecipeId)
        }
    }

    private var contextAttachment: AssistantRecipeAttachment? {
        guard let entry = contextRecipeEntry else { return nil }
        return AssistantRecipeAttachment(
            recipeId: entry.id,
            recipeName: entry.name,
            recipeColor: entry.color
        )
    }

    private var isContextRecipeAttached: Bool {
        guard let effectiveContextRecipeId else { return false }
        return attachments.contains { recipeIdsMatch($0.recipeId, effectiveContextRecipeId) }
    }

    private var showContextRecipeTag: Bool {
        contextAttachment != nil && !isContextRecipeAttached
    }

    private func contextRecipeTagButton(for attachment: AssistantRecipeAttachment) -> some View {
        AssistantAttachmentChipLabel(attachment: attachment)
            .assistantAttachmentChipChrome()
            .frame(minHeight: AppToolbarStyle.minimumTapSide)
            .contentShape(Capsule())
            .onTapGesture {
                attachContextRecipe(attachment)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("assistant.attach-current-recipe"))
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantContextRecipeTag)
    }

    private func attachContextRecipe(_ attachment: AssistantRecipeAttachment) {
        guard !isContextRecipeAttached, attachments.count < 10 else { return }
        attachments = attachments + [attachment]
    }

    private func recipeIdsMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
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

    private var voiceLimitAlert: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("assistant.voice-limit-alert")
                .appFootnote()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                voiceLimitAlertVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppToolbarStyle.minimumTapSide, height: AppToolbarStyle.minimumTapSide)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("assistant.close"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantVoiceLimitAlert)
    }

    @ViewBuilder
    private var voiceButton: some View {
        switch voiceRecorder.state {
        case .idle:
            Button {
                Task { await startVoiceRecording() }
            } label: {
                composerIconOnly(systemName: "mic")
            }
            .appToolbarIconButton()
            .accessibilityLabel(Text("assistant.voice-record"))
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantVoiceRecordButton)
            .disabled(isSending)
            .opacity(isSending ? 0.4 : 1)
        case .recording:
            Button {
                Task { await stopVoiceRecording() }
            } label: {
                composerIconOnly(systemName: "stop.fill", tint: .red)
            }
            .appToolbarIconButton()
            .accessibilityLabel(Text("assistant.voice-stop"))
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantVoiceStopButton)
        case .transcribing:
            ProgressView()
                .tint(Color.primary)
                .frame(width: AppToolbarStyle.iconSide, height: AppToolbarStyle.iconSide)
                .frame(width: AppToolbarStyle.minimumTapSide, height: AppToolbarStyle.minimumTapSide)
                .accessibilityLabel(Text("assistant.voice-transcribing"))
                .accessibilityIdentifier(AccessibilityIdentifiers.assistantVoiceTranscribingButton)
        }
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
        .disabled(!canSend || voiceRecorder.state == .recording)
        .opacity(canSend && voiceRecorder.state != .recording ? 1 : 0.35)
    }

    @ViewBuilder
    private func composerIconOnly(systemName: String, tint: Color = .primary) -> some View {
        AppSymbol.toolbarImage(systemName)
            .resizable()
            .scaledToFit()
            .frame(width: AppToolbarStyle.iconSide, height: AppToolbarStyle.iconSide)
            .foregroundStyle(tint)
            .frame(width: AppToolbarStyle.minimumTapSide, height: AppToolbarStyle.minimumTapSide)
            .contentShape(Rectangle())
    }

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var availableEntries: [CollectionEntry] {
        // Pinned-first → alphabetical by display name (emoji ignored) → id, same rule as "All Recipes".
        RecipeTitleEmoji.sortCollectionEntries(
            syncService.collectionEntries.filter { !$0.deleted }
        )
    }

    // MARK: - Actions

    private func showAssistantAttachOpen() {
        showAttachSheet = true
    }

    private func removeAttachment(_ attachment: AssistantRecipeAttachment) {
        attachments.removeAll { recipeIdsMatch($0.recipeId, attachment.recipeId) }
    }

    private func startVoiceRecording() async {
        voiceLimitAlertVisible = false
        do {
            try await voiceRecorder.start()
        } catch let error as AssistantVoiceRecorderError {
            voiceRecorder.markIdle()
            voiceErrorMessage = error.errorDescription
        } catch {
            voiceRecorder.markIdle()
            voiceErrorMessage = error.localizedDescription
        }
    }

    private func stopVoiceRecording() async {
        do {
            let audioData = try await voiceRecorder.stopCapture()
            await transcribeCapturedAudio(audioData)
        } catch let error as AssistantVoiceRecorderError {
            voiceRecorder.markIdle()
            voiceErrorMessage = error.errorDescription
        } catch {
            voiceRecorder.markIdle()
            voiceErrorMessage = error.localizedDescription
        }
    }

    private func transcribeCapturedAudio(_ audioData: Data) async {
        do {
            let transcribed = try await AssistantAPI.transcribe(audioData: audioData, mimeType: "audio/mp4")
            voiceRecorder.markIdle()
            appendTranscription(transcribed)
        } catch let error as APIError {
            voiceRecorder.markIdle()
            voiceErrorMessage = localizedAPIErrorMessage(error)
        } catch {
            voiceRecorder.markIdle()
            voiceErrorMessage = error.localizedDescription
        }
    }

    private func appendTranscription(_ transcribed: String) {
        let trimmed = transcribed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            text = trimmed
        } else if text.hasSuffix(" ") {
            text += trimmed
        } else {
            text += " \(trimmed)"
        }
    }

    private func localizedAPIErrorMessage(_ error: APIError) -> String {
        if case .serverError(let message) = error, message.hasPrefix("assistant.") {
            return Bundle.currentLocalizedString(message)
        }
        return error.localizedDescription
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

private struct AssistantAttachmentChipLabel: View {
    let attachment: AssistantRecipeAttachment

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: attachment.recipeColor ?? "") ?? .accentColor)
                .frame(width: 8, height: 8)
            Text(attachment.recipeName ?? attachment.recipeId)
                .font(.footnote)
                .lineLimit(1)
        }
    }
}

private struct AssistantAttachmentChip: View {
    let attachment: AssistantRecipeAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            AssistantAttachmentChipLabel(attachment: attachment)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("assistant.remove-attached-recipe"))
        }
        .assistantAttachmentChipChrome()
    }
}

private extension View {
    func assistantAttachmentChipChrome() -> some View {
        padding(.horizontal, 10)
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
                            HStack(alignment: .top, spacing: RecipeRowLayoutMetrics.rowMarkerSpacing) {
                                Circle()
                                    .fill(Color(hex: entry.color) ?? .accentColor)
                                    .frame(width: 10, height: 10)
                                    .frame(
                                        width: RecipeRowLayoutMetrics.markerSlotWidth,
                                        height: RecipeRowLayoutMetrics.titleLineHeight,
                                        alignment: .center
                                    )
                                Text(entry.name)
                                    .appBody()
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                            }
                            .ingredientListRowChrome()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
                        .accessibilityIdentifier("assistant_recipe_picker_row_\(entry.id)")
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 1)
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("assistant.recipe-search-placeholder")
            )
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
