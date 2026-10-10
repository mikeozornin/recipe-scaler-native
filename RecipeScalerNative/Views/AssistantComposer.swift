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

// MARK: - Morph chrome strip (attach / voice / send)

/// Shared composer chrome: attachment chips, voice UI, and action toolbar.
/// Used inside legacy modal `AssistantComposer` (field + toolbar card).
/// Reports the voice transcribing state through `isVoiceTranscribing` so the
/// wrapper (which owns the text field) can disable input during transcription.
struct AssistantComposerChrome: View {
    fileprivate static let shellCornerRadius: CGFloat = 16

    @Binding var text: String
    @Binding var attachments: [AssistantRecipeAttachment]
    @Binding var isVoiceTranscribing: Bool
    /// Spec 078 — one-shot: when set true by the sheet, start recording and clear.
    @Binding var autoStartVoice: Bool
    let isSending: Bool
    let contextRecipeId: String?
    let onSend: () -> Void

    @ViewBuilder var topContent: () -> AnyView

    init(
        text: Binding<String>,
        attachments: Binding<[AssistantRecipeAttachment]>,
        isVoiceTranscribing: Binding<Bool>,
        autoStartVoice: Binding<Bool> = .constant(false),
        isSending: Bool,
        contextRecipeId: String?,
        onSend: @escaping () -> Void,
        syncService: YjsSyncService,
        @ViewBuilder topContent: @escaping () -> some View = { EmptyView() }
    ) {
        _text = text
        _attachments = attachments
        _isVoiceTranscribing = isVoiceTranscribing
        _autoStartVoice = autoStartVoice
        self.isSending = isSending
        self.contextRecipeId = contextRecipeId
        self.onSend = onSend
        self.syncService = syncService
        self.topContent = { AnyView(topContent()) }
    }

    /// Injected (not `@Environment`): the composer chrome can outlive the
    /// sheet presentation (dismiss animation) while iOS 26 re-measures bar
    /// items in a fallback environment that has no injected observables.
    /// `@Environment(YjsSyncService.self)` in that subtree traps.
    let syncService: YjsSyncService
    @Environment(AssistantRecipeContext.self) private var recipeContext
    @State private var showAttachSheet = false
    @State private var voiceRecorder = AssistantVoiceRecorder()
    @State private var voiceLimitAlertVisible = false
    @State private var voiceErrorMessage: String?

    private var effectiveContextRecipeId: String? {
        _ = recipeContext.visibleRecipeId
        return contextRecipeId ?? recipeContext.visibleRecipeId
    }

    var body: some View {
        chromeShell
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantComposerShell)
            .sheet(isPresented: $showAttachSheet) {
                AssistantRecipePicker(
                    attachments: $attachments,
                    availableEntries: availableEntries
                )
            }
            .onAppear {
                voiceRecorder.onLimitReached = {
                    voiceLimitAlertVisible = true
                }
                voiceRecorder.onAutoStopCapture = { data in
                    await transcribeCapturedAudio(data)
                }
                isVoiceTranscribing = voiceRecorder.state == .transcribing
                consumeAutoStartVoiceIfNeeded()
            }
            .onDisappear {
                voiceRecorder.cancel()
            }
            .onChange(of: voiceRecorder.state) { _, newState in
                isVoiceTranscribing = newState == .transcribing
            }
            .onChange(of: autoStartVoice) { _, shouldStart in
                guard shouldStart else { return }
                consumeAutoStartVoiceIfNeeded()
            }
            .errorAlert(title: "assistant.error-unavailable", message: $voiceErrorMessage)
    }

    private var chromeShell: some View {
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

            topContent()

            composerToolbar
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isVoiceActive {
                AssistantRecordingShimmer(cornerRadius: Self.shellCornerRadius, voiceRecorder: voiceRecorder)
            } else {
                Color(.systemBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.shellCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.shellCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var isVoiceActive: Bool {
        voiceRecorder.state == .recording || voiceRecorder.state == .transcribing
    }

    private var borderColor: Color {
        isVoiceActive ? .clear : Color(.separator)
    }

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
        Group {
            if voiceRecorder.state == .recording {
                recordingControls
                    .frame(height: AppToolbarStyle.minimumTapSide)
            } else if voiceRecorder.state == .transcribing {
                transcribingControls
                    .frame(height: AppToolbarStyle.minimumTapSide)
            } else {
                idleControls
                    .frame(minHeight: AppToolbarStyle.minimumTapSide)
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, 2)
        .padding(.bottom, 2)
    }

    private var recordingControls: some View {
        HStack(spacing: 0) {
            Button {
                voiceRecorder.cancel()
            } label: {
                composerIconOnly(systemName: "xmark")
            }
            .appToolbarIconButton()
            .accessibilityLabel(Text("assistant.voice-cancel"))
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantVoiceCancelButton)

            AssistantVoiceLevelMeter(barHeights: voiceRecorder.barHeights)
                .padding(.horizontal, 8)

            Button {
                guard voiceRecorder.state == .recording else { return }
                Task { await stopVoiceRecording() }
            } label: {
                composerIconOnly(systemName: "checkmark")
            }
            .appToolbarIconButton()
            .accessibilityLabel(Text("assistant.voice-stop"))
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantVoiceStopButton)
            .symbolEffect(.pulse)
        }
    }

    private var transcribingControls: some View {
        HStack(spacing: 6) {
            Spacer()
            ProgressView()
                .tint(Color.primary)
            Text("assistant.voice-transcribing")
                .appFootnote()
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantVoiceTranscribingButton)
    }

    private var idleControls: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                attachButton
                if showContextRecipeTag, let contextAttachment {
                    contextRecipeTagButton(for: contextAttachment)
                }
            }
            Spacer(minLength: 8)
            voiceButton
            sendButton
        }
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
            showAttachSheet = true
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
        syncService.collectionIndex.live
    }

    private func removeAttachment(_ attachment: AssistantRecipeAttachment) {
        attachments.removeAll { recipeIdsMatch($0.recipeId, attachment.recipeId) }
    }

    private func consumeAutoStartVoiceIfNeeded() {
        guard autoStartVoice else { return }
        autoStartVoice = false
        guard voiceRecorder.state == .idle, !isSending else { return }
        Task { await startVoiceRecording() }
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
            voiceErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func stopVoiceRecording() async {
        do {
            let audioData = try await voiceRecorder.stopCapture()
            let task = Task { [weak voiceRecorder] in
                await self.transcribeCapturedAudio(audioData)
                await MainActor.run { voiceRecorder?.transcriptionTask = nil }
            }
            voiceRecorder.transcriptionTask = task
            await task.value
        } catch let error as AssistantVoiceRecorderError {
            voiceRecorder.markIdle()
            voiceErrorMessage = error.errorDescription
        } catch {
            voiceRecorder.markIdle()
            voiceErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func transcribeCapturedAudio(_ audioData: Data) async {
        do {
            let transcribed = try await AssistantAPI.transcribe(audioData: audioData, mimeType: "audio/mp4")
            guard !Task.isCancelled, voiceRecorder.state == .transcribing else { return }
            voiceRecorder.markIdle()
            appendTranscription(transcribed)
        } catch is CancellationError {
            voiceRecorder.markIdle()
        } catch let error as APIError {
            voiceRecorder.markIdle()
            voiceErrorMessage = error.userFacingMessage()
        } catch {
            voiceRecorder.markIdle()
            voiceErrorMessage = UserFacingAPIError.message(for: error)
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
}

// MARK: - Legacy modal composer (field + chrome)

struct AssistantComposer: View {
    /// Web `min-h-12` — keeps the field height stable when placeholder disappears.
    private static let inputMinHeight: CGFloat = 48

    @Binding var text: String
    @Binding var attachments: [AssistantRecipeAttachment]
    let isSending: Bool
    let inputPlaceholderVariantIndex: Int
    let contextRecipeId: String?
    @Binding var autoStartVoice: Bool
    let onSend: () -> Void
    /// Injected through to `AssistantComposerChrome` — no `@Environment` in the
    /// composer subtree (iOS 26 fallback-env measurement during sheet dismiss).
    let syncService: YjsSyncService

    @Environment(\.locale) private var locale
    /// Mirrored from `AssistantComposerChrome.voiceRecorder` (which owns voice
    /// state) so the field can lock during transcription like it did before the
    /// Chrome/wrapper split.
    @State private var isVoiceTranscribing = false

    private var inputPlaceholder: String {
        _ = locale
        return AssistantInputPlaceholder.localizedVariant(index: inputPlaceholderVariantIndex)
    }

    var body: some View {
        AssistantComposerChrome(
            text: $text,
            attachments: $attachments,
            isVoiceTranscribing: $isVoiceTranscribing,
            autoStartVoice: $autoStartVoice,
            isSending: isSending,
            contextRecipeId: contextRecipeId,
            onSend: onSend,
            syncService: syncService
        ) {
            messageInput
                .padding(.horizontal, 16)
                .padding(.top, attachments.isEmpty ? 12 : 4)
                .padding(.bottom, 4)
        }
    }

    private var messageInput: some View {
        TextField(inputPlaceholder, text: $text, axis: .vertical)
            .appBodyFieldTypography()
            .lineLimit(1...6)
            .frame(maxWidth: .infinity, minHeight: Self.inputMinHeight, alignment: .topLeading)
            .disabled(isSending || isVoiceTranscribing)
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantMessageInput)
    }
}

enum AssistantInputPlaceholder {
    static let variantCount = 8

    static func localizedVariant(index: Int) -> String {
        let clamped = ((index % variantCount) + variantCount) % variantCount
        return Bundle.currentLocalizedString("assistant.input-placeholder-variants.\(clamped)")
    }
}

// MARK: - Attachment chip (composer removable wrapper)

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
                    ContentUnavailableView {
                        AppEmptyState.label("assistant.no-recipes-found", symbol: "book")
                    }
                    .font(AppTypography.body)
                } else if attachableEntries.isEmpty {
                    ContentUnavailableView {
                        AppEmptyState.label("assistant.no-recipes-found", symbol: "book")
                    }
                    .font(AppTypography.body)
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        AppEmptyState.label("assistant.no-recipes-found", symbol: "magnifyingglass")
                    }
                    .font(AppTypography.body)
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
                    .appOpaqueListSurface()
                    .environment(\.defaultMinListRowHeight, 1)
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("assistant.recipe-search-placeholder")
            )
            .background(AppSheetChrome.groupedBackground)
        }
        .appOpaqueSheetPresentation(detents: [.medium, .large])
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

// MARK: - Recording shimmer overlay

/// Twilight mesh that fills the composer shell while recording or transcribing.
/// Colour field lives in `AssistantRecordingShimmer.metal`; this view feeds it a smoothed
/// voice level and an accumulated phase, so speaking speeds the drift and lifts light from
/// the toolbar without the pattern jumping. Transcribing breathes gently; Reduce Motion
/// shows a still frame.
private struct AssistantRecordingShimmer: View {
    let cornerRadius: CGFloat
    let voiceRecorder: AssistantVoiceRecorder

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var motion = AssistantRecordingShimmerMotion()

    var body: some View {
        Group {
            if reduceMotion {
                surface(phase: 0, level: 0, grainSeed: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let frame = motion.advance(to: time, target: targetLevel(at: time))
                    surface(phase: frame.phase, level: frame.level, grainSeed: time.truncatingRemainder(dividingBy: 1))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func targetLevel(at time: TimeInterval) -> Double {
        switch voiceRecorder.state {
        case .recording: Double(voiceRecorder.level)
        case .transcribing: 0.16 + 0.1 * sin(time * 2.2)
        case .idle: 0
        }
    }

    private func surface(phase: Double, level: Double, grainSeed: Double) -> some View {
        let isDark: Float = colorScheme == .dark ? 1 : 0
        let scale = Float(displayScale)
        let palette = Self.palette
        return Rectangle().visualEffect { content, proxy in
            content.colorEffect(
                ShaderLibrary.assistantRecordingMesh(
                    .float2(proxy.size),
                    .float(Float(phase)),
                    .float(Float(level)),
                    .float(isDark),
                    .float(Float(grainSeed)),
                    .float(scale),
                    .color(palette[0]),
                    .color(palette[1]),
                    .color(palette[2]),
                    .color(palette[3])
                )
            )
        }
    }

    /// «Сумерки»: indigo, lavender, rose, peach.
    private static let palette: [Color] = [
        Color(red: 0x5B / 255.0, green: 0x5B / 255.0, blue: 0xD6 / 255.0),
        Color(red: 0xA7 / 255.0, green: 0x8B / 255.0, blue: 0xFA / 255.0),
        Color(red: 0xF4 / 255.0, green: 0x9A / 255.0, blue: 0xC1 / 255.0),
        Color(red: 0xFF / 255.0, green: 0xC8 / 255.0, blue: 0xA2 / 255.0),
    ]
}

/// Per-frame integrator for the shimmer: eases the raw meter level (fast attack, slow
/// release) and accumulates phase at a voice-dependent speed.
private final class AssistantRecordingShimmerMotion {
    private var lastTime: TimeInterval?
    private var phase: Double = 0
    private var level: Double = 0

    func advance(to time: TimeInterval, target: Double) -> (phase: Double, level: Double) {
        let dt = lastTime.map { min(max(time - $0, 0), 0.05) } ?? 0
        lastTime = time
        let rate = target > level ? 16.0 : 4.5
        level += (target - level) * (1 - exp(-dt * rate))
        phase += dt * (0.35 + 1.5 * level)
        return (phase, level)
    }
}
