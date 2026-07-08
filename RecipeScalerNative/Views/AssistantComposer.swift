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
    @Environment(YjsSyncService.self) private var syncService
    @Environment(AssistantRecipeContext.self) private var recipeContext
    @State private var showAttachSheet = false
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
            .errorAlert(title: "assistant.error-unavailable", message: $voiceErrorMessage)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isVoiceActive {
                AssistantRecordingShimmer(cornerRadius: Self.shellCornerRadius)
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
        // Pinned-first → alphabetical by display name (emoji ignored) → id, same rule as "All Recipes".
        // Reads the memoized `collectionIndex.live` (rebuilt on sync deltas) instead of re-sorting on every render.
        syncService.collectionIndex.live
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
            voiceErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func stopVoiceRecording() async {
        do {
            let audioData = try await voiceRecorder.stopCapture()
            // Owned by the recorder so cancel() can abort an in-flight upload.
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
            // cancel() may have flipped state to .idle mid-flight; in that case drop the result.
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
        font(Font(AppTypography.footnoteUIFont))
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

/// Cyan-blue shimmer that fills the composer shell while recording or transcribing.
/// Web parity: `.assistant-recording-shimmer` (recipe-scaler-web/src/index.css).
/// iOS 18+: animated `MeshGradient`; iOS 17: linear fallback. Pauses when Reduce Motion is on.
private struct AssistantRecordingShimmer: View {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                AssistantRecordingMeshShimmer(
                    cornerRadius: cornerRadius,
                    colorScheme: colorScheme,
                    reduceMotion: reduceMotion
                )
            } else {
                AssistantRecordingLinearShimmer(
                    cornerRadius: cornerRadius,
                    colorScheme: colorScheme,
                    reduceMotion: reduceMotion
                )
            }
        }
    }
}

// MARK: Mesh shimmer (iOS 18+)

@available(iOS 18.0, *)
private struct AssistantRecordingMeshShimmer: View {
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme
    let reduceMotion: Bool

    var body: some View {
        Group {
            if reduceMotion {
                mesh(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    mesh(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func mesh(at time: TimeInterval) -> some View {
        MeshGradient(
            width: AssistantRecordingMeshShimmerMath.gridWidth,
            height: AssistantRecordingMeshShimmerMath.gridHeight,
            points: AssistantRecordingMeshShimmerMath.points(at: time),
            colors: AssistantRecordingMeshShimmerMath.colors(for: colorScheme, at: time),
            background: AssistantRecordingMeshShimmerMath.background(for: colorScheme),
            smoothsColors: true
        )
    }
}

// MARK: Mesh shimmer math (iOS 18+ view, but pure-Swift math usable from iOS 17 / tests)

private enum AssistantRecordingMeshShimmerMath {
    static let gridWidth = 4
    static let gridHeight = 4
    static let animationSpeed = 1.0

    /// Near-static grid. Tiny drift keeps the surface organic without introducing
    /// several visible "moving centres" — the colour flow does the work.
    private static let jitter: Float = 0.02

    static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let t = time * animationSpeed
        func p(_ x: Float, _ y: Float, _ phase: Double) -> SIMD2<Float> {
            // Corners/edges pinned; interior nudged by a shared slow drift only.
            let interior = (x > 0 && x < 1 && y > 0 && y < 1)
            guard interior else { return SIMD2(x, y) }
            return SIMD2(
                x + jitter * Float(sin(t * 0.5 + phase)),
                y + jitter * Float(cos(t * 0.4 + phase))
            )
        }
        return [
            p(0, 0, 0), p(0.34, 0, 0), p(0.66, 0, 0), p(1, 0, 0),
            p(0, 0.34, 1), p(0.34, 0.34, 1), p(0.66, 0.34, 2), p(1, 0.34, 2),
            p(0, 0.66, 3), p(0.34, 0.66, 3), p(0.66, 0.66, 4), p(1, 0.66, 4),
            p(0, 1, 0), p(0.34, 1, 0), p(0.66, 1, 0), p(1, 1, 0),
        ]
    }

    /// One coherent gradient band that flows diagonally and gently sways — a single smooth
    /// sweep across the whole shell, not many independent blinking centres.
    static func colors(for scheme: ColorScheme, at time: TimeInterval) -> [Color] {
        let t = time * animationSpeed
        // Direction sways slowly around the diagonal for an organic, non-linear feel.
        let angle = 0.72 + 0.30 * sin(t * 0.13)
        let dirX = cos(angle)
        let dirY = sin(angle)
        let tone = scheme == .dark ? darkTones : lightTones

        // Pre-resolve the 16 node positions once per frame; nodeColor does the rest.
        return (0 ..< gridWidth * gridHeight).map { index in
            let x = Double(index % gridWidth) / Double(gridWidth - 1)
            let y = Double(index / gridWidth) / Double(gridHeight - 1)
            return nodeColor(tone: tone, x: x, y: y, dirX: dirX, dirY: dirY, time: t)
        }
    }

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(hue: 202.0 / 360.0, saturation: 0.60, brightness: 0.60)
            : Color(hue: 200.0 / 360.0, saturation: 0.52, brightness: 0.88)
    }

    private static func nodeColor(
        tone: Tone,
        x: Double,
        y: Double,
        dirX: Double,
        dirY: Double,
        time: Double
    ) -> Color {
        // Projection onto the (swaying) flow direction → one smooth band across the grid.
        let proj = x * dirX + y * dirY
        let band = (sin(proj * 3.1 - time * 1.4) + 1) / 2

        // Blue ↔ light-cyan along the band; mostly blue, so it reads as a tinted gradient.
        let base = lerpHSB(tone.deep, tone.light, smoothstep(band))
        // Gentle crest of brightness only at the very peak — no heavy white wash.
        let crest = pow(band, 4.0) * 0.28
        return color(from: lerpHSB(base, tone.crest, crest))
    }

    private static func smoothstep(_ v: Double) -> Double {
        let c = max(0, min(1, v))
        return c * c * (3 - 2 * c)
    }

    fileprivate struct Tone {
        let crest: (h: Double, s: Double, b: Double)
        let light: (h: Double, s: Double, b: Double)
        let deep: (h: Double, s: Double, b: Double)
    }

    private static let lightTones = Tone(
        crest: (192.0 / 360.0, 0.12, 1.00),
        light: (193.0 / 360.0, 0.42, 0.94),
        deep: (206.0 / 360.0, 0.74, 0.80)
    )

    private static let darkTones = Tone(
        crest: (194.0 / 360.0, 0.16, 0.90),
        light: (196.0 / 360.0, 0.46, 0.78),
        deep: (208.0 / 360.0, 0.70, 0.60)
    )

    private static func lerpHSB(_ a: (h: Double, s: Double, b: Double), _ b: (h: Double, s: Double, b: Double), _ t: Double) -> (h: Double, s: Double, b: Double) {
        let clamped = max(0, min(1, t))
        return (
            h: a.h + (b.h - a.h) * clamped,
            s: a.s + (b.s - a.s) * clamped,
            b: a.b + (b.b - a.b) * clamped
        )
    }

    private static func color(from hsb: (h: Double, s: Double, b: Double)) -> Color {
        Color(hue: hsb.h, saturation: hsb.s, brightness: hsb.b)
    }
}

// MARK: Linear shimmer fallback (iOS 17)

private struct AssistantRecordingLinearShimmer: View {
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme
    let reduceMotion: Bool

    private static let halfCycleDuration: TimeInterval = 3.5

    @State private var animate = false

    var body: some View {
        LinearGradient(
            stops: colorScheme == .dark ? Self.darkGradientStops : Self.lightGradientStops,
            startPoint: animate ? Self.endStartPoint : Self.startStartPoint,
            endPoint: animate ? Self.endEndPoint : Self.startEndPoint
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: Self.halfCycleDuration).repeatForever(autoreverses: true),
            value: animate
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            guard !reduceMotion else { return }
            animate = true
        }
        .onDisappear {
            animate = false
        }
        .onChange(of: reduceMotion) { _, newValue in
            animate = !newValue
        }
    }

    private static let startStartPoint = UnitPoint(x: -0.45, y: -0.05)
    private static let startEndPoint = UnitPoint(x: 0.55, y: 1.05)
    private static let endStartPoint = UnitPoint(x: 0.45, y: -0.05)
    private static let endEndPoint = UnitPoint(x: 1.45, y: 1.05)

    private static let lightGradientStops: [Gradient.Stop] = [
        .init(color: Color.white.opacity(0.98), location: 0.0),
        .init(color: Color.white.opacity(0.92), location: 0.14),
        .init(color: Color(hue: 190.0 / 360.0, saturation: 0.50, brightness: 0.97, opacity: 0.88), location: 0.32),
        .init(color: Color(hue: 200.0 / 360.0, saturation: 0.82, brightness: 0.78, opacity: 0.92), location: 0.58),
        .init(color: Color(hue: 205.0 / 360.0, saturation: 0.92, brightness: 0.52, opacity: 0.96), location: 1.0),
    ]

    private static let darkGradientStops: [Gradient.Stop] = [
        .init(color: Color.white.opacity(0.82), location: 0.0),
        .init(color: Color(hue: 185.0 / 360.0, saturation: 0.35, brightness: 0.95, opacity: 0.72), location: 0.14),
        .init(color: Color(hue: 195.0 / 360.0, saturation: 0.65, brightness: 0.72, opacity: 0.68), location: 0.38),
        .init(color: Color(hue: 200.0 / 360.0, saturation: 0.80, brightness: 0.58, opacity: 0.74), location: 0.62),
        .init(color: Color(hue: 205.0 / 360.0, saturation: 0.88, brightness: 0.45, opacity: 0.78), location: 1.0),
    ]
}
