//
//  AssistantSheet.swift
//  RecipeScalerNative
//
//  Streaming chat UI mirroring `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-sheet.tsx`.
//  Wire protocol: see `Services/AssistantAPI.swift` and spec 015/021.
//

import SwiftUI

struct AssistantSheet: View {
    @Environment(YjsSyncService.self) private var syncService

    let contextRecipeId: String?

    @State private var threadId: String?
    @State private var threads: [AssistantThreadDTO] = []
    @State private var messages: [AssistantMessage] = []
    @State private var input = ""
    @State private var attachments: [AssistantRecipeAttachment] = []
    @State private var isSending = false
    @State private var isBootstrapping = false
    @State private var isLoadingThreads = false
    @State private var loadError: String?
    @State private var showHistorySheet = false
    @State private var deletingThreadId: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var hasTriedSessionRestore = false
    @State private var messageListContentWidth: CGFloat = 0
    @State private var inputPlaceholderVariantIndex = Int.random(in: 0..<AssistantInputPlaceholder.variantCount)
    @State private var streamingToolStatusKey: String?

    private var isOnline: Bool {
        syncService.connectionState.isConnected
    }

    private static let newChatTimeout: TimeInterval = 60
    private static let userMessageLeadingInset: CGFloat = 48
    private static let messageMaxWidthFraction: CGFloat = 0.9

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isOnline {
                    messageList
                    AssistantComposer(
                        text: $input,
                        attachments: $attachments,
                        isSending: isSending,
                        inputPlaceholderVariantIndex: inputPlaceholderVariantIndex,
                        contextRecipeId: contextRecipeId,
                        onSend: { Task { await send() } }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                } else {
                    ContentUnavailableView {
                        AppEmptyState.label("assistant.error-unavailable", symbol: "wifi.slash")
                    } description: {
                        Text("assistant.offline.description")
                            .appBody()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier(AccessibilityIdentifiers.assistantOfflineFootnote)
                }
            }
            .background(Color(.systemBackground))
            .localizedNavigationTitle("assistant.title")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showHistorySheet = true
                    } label: {
                        AppToolbarStyle.iconOnly(systemName: "clock.arrow.circlepath")
                    }
                    .appToolbarIconButton()
                    .accessibilityLabel(Text("assistant.threads-title"))
                    .accessibilityIdentifier(AccessibilityIdentifiers.assistantHistoryButton)

                    Button {
                        startNewChat()
                    } label: {
                        AppToolbarStyle.iconOnly(systemName: "plus")
                    }
                    .appToolbarIconButton()
                    .accessibilityLabel(Text("assistant.new-chat"))
                    .accessibilityIdentifier(AccessibilityIdentifiers.assistantNewThreadButton)
                }
            }
            .overlay {
                if isBootstrapping {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.6))
                }
            }
            .sheet(isPresented: $showHistorySheet) {
                AssistantThreadListSheet(
                    threads: threads,
                    activeThreadId: threadId,
                    deletingThreadId: deletingThreadId,
                    isLoading: isLoadingThreads || (isBootstrapping && threads.isEmpty),
                    onSelect: { selectedId in
                        showHistorySheet = false
                        Task { await openThread(selectedId) }
                    },
                    onDelete: { deletedId in
                        Task { await deleteThread(deletedId) }
                    }
                )
            }
            .errorAlert(title: "assistant.error-unavailable", message: $loadError)
            .task { await initialize() }
            .onChange(of: isOnline) { _, connected in
                if connected { Task { await initialize() } }
            }
            .onChange(of: showHistorySheet) { _, isOpen in
                if isOpen {
                    Task { await refreshThreadsList() }
                }
            }
            .onAppear {
                inputPlaceholderVariantIndex = Int.random(in: 0..<AssistantInputPlaceholder.variantCount)
                #if DEBUG
                AgentSyncDebugLog.sync(
                    location: "AssistantSheet.onAppear",
                    message: "assistant_sheet_appeared",
                    data: ["has_thread_id": threadId != nil ? "true" : "false"]
                )
                #endif
            }
            .onDisappear {
                persistSession()
                streamTask?.cancel()
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantSheet)
        }
        .appOpaqueSheetPresentationPlain()
    }

    // MARK: - Message list

    private var messageList: some View {
        // Build once per body pass (not per bubble). Streaming deltas re-render the
        // sheet; recomputing these maps inside each message was O(visible × collection).
        // `collectionEntries` is already filtered to non-deleted entries.
        let lookups = AssistantAttachableRecipeLookups.build(from: syncService.collectionEntries)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(messages) { message in
                    let isLast = message.id == messages.last?.id
                    messageBubble(for: message, isLast: isLast, lookups: lookups)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            max(0, proxy.size.width - 28)
        } action: { width in
            messageListContentWidth = width
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func userBubbleMaxWidth(for contentWidth: CGFloat) -> CGFloat {
        guard contentWidth > 0 else { return 280 }
        return min(
            contentWidth * Self.messageMaxWidthFraction,
            contentWidth - Self.userMessageLeadingInset
        )
    }

    @ViewBuilder
    private func messageBubble(
        for message: AssistantMessage,
        isLast: Bool,
        lookups: AssistantAttachableRecipeLookups
    ) -> some View {
        let isUser = message.role == "user"
        let showMeta = shouldShowMessageMeta(for: message)
        let followUps = AssistantMessageFollowUps.suggestions(
            for: message,
            isLastMessage: isLast,
            isSending: isSending
        )
        let bubble = messageBubbleBody(for: message, isLast: isLast, isUser: isUser, lookups: lookups)

        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Group {
                if isUser {
                    HStack(alignment: .top, spacing: 0) {
                        Spacer(minLength: Self.userMessageLeadingInset)
                        bubble
                            .frame(
                                maxWidth: userBubbleMaxWidth(for: messageListContentWidth),
                                alignment: .trailing
                            )
                    }
                } else {
                    bubble
                        .frame(
                            maxWidth: messageListContentWidth > 0
                                ? messageListContentWidth * Self.messageMaxWidthFraction
                                : nil,
                            alignment: .leading
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if showMeta {
                AssistantMessageMetaRow(
                    message: message,
                    isUser: isUser,
                    fallbackRecipeNameById: lookups.nameById
                )
            }

            if !followUps.isEmpty {
                AssistantFollowUpsView(suggestions: followUps) { suggestion in
                    submitWidgetValue(suggestion.value, displayText: suggestion.label, recipeAttachment: nil)
                }
                .frame(
                    maxWidth: messageListContentWidth > 0
                        ? messageListContentWidth * Self.messageMaxWidthFraction
                        : nil,
                    alignment: .leading
                )
            }
        }
    }

    private func shouldShowMessageMeta(for message: AssistantMessage) -> Bool {
        if message.role == "assistant",
           message.isStreaming,
           message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    @ViewBuilder
    private func messageBubbleBody(
        for message: AssistantMessage,
        isLast: Bool,
        isUser: Bool,
        lookups: AssistantAttachableRecipeLookups
    ) -> some View {
        let attachments = isUser ? (message.metadata?.attachments ?? []) : []
        let chipsOnly = isUser && AssistantUserBubblePresentation.showsAttachmentChipsOnly(message: message)
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if isUser {
                // Web parity: user-bubble shows the friendlier resolved text (e.g. "Удалить"
                // instead of "confirm_delete") for messages that resolved a pending action.
                // Attachments render as read-only recipe chips below the text — or instead of
                // the text when it is empty / equals the recipeId (widget recipe submit).
                if !chipsOnly {
                    let displayText = AssistantMessageCopyText.text(for: message)
                    if !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(displayText)
                            .appBodySelectable(multilineTextAlignment: .trailing)
                    }
                }
                if !attachments.isEmpty {
                    FlowLayout(spacing: 8, alignment: .trailing) {
                        ForEach(attachments) { attachment in
                            AssistantAttachmentChipDisplayView(
                                attachment: attachment,
                                fallbackNameById: lookups.nameById,
                                fallbackColorById: lookups.colorById
                            )
                        }
                    }
                }
            } else if message.text.isEmpty && message.isStreaming {
                Text(verbatim: streamingPlaceholder(for: message, isLast: isLast))
                    .appBodySelectable(multilineTextAlignment: .leading)
            } else {
                AssistantMarkdownText(content: message.text)
            }

            AssistantMessageFooter(
                message: message,
                isLastMessage: isLast,
                isSending: isSending,
                onWidgetSubmit: { value, displayText, attachment in
                    submitWidgetValue(value, displayText: displayText, recipeAttachment: attachment)
                }
            )
        }
        .padding(10)
        .background(
            isUser
                ? Color.accentColor.opacity(0.15)
                : Color.secondary.opacity(0.12)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("assistant_message_\(message.id)")
    }

    // MARK: - Lifecycle

    /// On first appearance: load thread list, then restore recent thread (≤60s) or start empty chat.
    /// Mirrors web `buildInitialSelection` + `useAssistantChat` bootstrap.
    private func initialize() async {
        guard !hasTriedSessionRestore else { return }
        // While offline, show the offline state instead of a network bootstrap spinner.
        // `hasTriedSessionRestore` stays false so the bootstrap runs once the connection
        // comes back (see `.onChange(of: isOnline)`).
        guard isOnline else { return }
        hasTriedSessionRestore = true
        #if DEBUG
        if DebugLaunchOptions.screenshotAssistantFixture {
            applyScreenshotAssistantFixture()
            return
        }
        #endif
        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            threads = try await AssistantAPI.listThreads(language: AppLanguagePreference.current.rawValue)
        } catch {
            loadError = UserFacingAPIError.message(for: error)
            threads = []
        }

        let now = Date().timeIntervalSince1970
        let lastOpenedAt = UserDefaults.standard.double(forKey: Self.sessionLastOpenedAtKey)
        if lastOpenedAt > 0,
           now - lastOpenedAt < Self.newChatTimeout,
           let savedThreadId = UserDefaults.standard.string(forKey: Self.sessionThreadIdKey),
           threads.contains(where: { $0.id == savedThreadId }) {
            await openThread(savedThreadId)
            return
        }
        startNewChat()
    }

    #if DEBUG
    private func applyScreenshotAssistantFixture() {
        let isEnglish = AppLanguagePreference.current == .en
        let stamp = AssistantISO8601.parse("2026-04-12T10:00:00.000Z") ?? Date()
        threadId = "about-assistant-thread"
        messages = [
            AssistantMessage(
                id: "about-assistant-user-message",
                role: "user",
                text: isEnglish
                    ? "My sauce split. How can I save the pasta?"
                    : "Соус свернулся. Как спасти пасту?",
                isStreaming: false,
                metadata: nil,
                createdAt: stamp
            ),
            AssistantMessage(
                id: "about-assistant-reply",
                role: "assistant",
                text: isEnglish
                    ? "Don't panic: you can usually bring the sauce back.\n\n1. Take the pan off the heat and let it rest for 20-30 seconds.\n2. Add 1-2 spoonfuls of warm pasta water and whisk quickly.\n3. If it still looks grainy, stir in a little cold butter.\n\nThen keep the sauce over low heat and do not let it boil."
                    : "Спокойно: чаще всего соус можно вернуть.\n\n1. Сними сковороду с огня и дай ей постоять 20-30 секунд.\n2. Добавь 1-2 ложки теплой воды от пасты и энергично размешай.\n3. Если соус все еще зернистый, вмешай немного холодного сливочного масла.\n\nДальше держи соус на слабом огне и не давай ему кипеть.",
                isStreaming: false,
                metadata: nil,
                createdAt: stamp
            ),
        ]
    }
    #endif

    private func startNewChat() {
        streamTask?.cancel()
        threadId = nil
        messages = []
        input = ""
        attachments = []
        UserDefaults.standard.removeObject(forKey: Self.sessionThreadIdKey)
    }

    private func openThread(_ id: String) async {
        streamTask?.cancel()
        threadId = id
        persistSession()
        await loadHistory(for: id)
    }

    private func ensureThread() async {
        guard threadId == nil else { return }
        do {
            let thread = try await AssistantAPI.createThread(language: AppLanguagePreference.current.rawValue)
            threadId = thread.id
            threads.insert(thread, at: 0)
            persistSession()
        } catch {
            loadError = UserFacingAPIError.message(for: error)
        }
    }

    private func refreshThreadsList() async {
        if threads.isEmpty {
            isLoadingThreads = true
        }
        defer { isLoadingThreads = false }
        do {
            threads = try await AssistantAPI.listThreads(language: AppLanguagePreference.current.rawValue)
        } catch {
            loadError = UserFacingAPIError.message(for: error)
        }
    }

    private func deleteThread(_ id: String) async {
        deletingThreadId = id
        do {
            try await AssistantAPI.deleteThread(threadId: id, language: AppLanguagePreference.current.rawValue)
            let needsNewActive = threadId == id
            withAnimation(.easeInOut(duration: 0.25)) {
                threads.removeAll { $0.id == id }
            }
            deletingThreadId = nil
            guard needsNewActive else { return }
            if let nextThread = threads.first {
                await openThread(nextThread.id)
            } else {
                startNewChat()
            }
        } catch {
            deletingThreadId = nil
            loadError = UserFacingAPIError.message(for: error)
        }
    }

    private func loadHistory(for id: String) async {
        do {
            let history = try await AssistantAPI.getMessages(threadId: id, language: AppLanguagePreference.current.rawValue)
            messages = history.map {
                AssistantMessage(
                    id: $0.id,
                    role: $0.role,
                    text: $0.content,
                    isStreaming: false,
                    metadata: $0.metadata,
                    createdAt: AssistantISO8601.parse($0.createdAt) ?? Date()
                )
            }
        } catch {
            loadError = UserFacingAPIError.message(for: error)
            if threadId == id {
                threads.removeAll { $0.id == id }
                startNewChat()
            }
        }
    }

    private func promoteActiveThread(updatedTitle: String? = nil) {
        guard let threadId,
              let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        let existing = threads.remove(at: index)
        let refreshed = AssistantThreadDTO(
            id: existing.id,
            title: updatedTitle ?? existing.title,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
            lastMessageAt: existing.lastMessageAt
        )
        threads.insert(refreshed, at: 0)
    }

    // MARK: - Send

    /// Web `handleSend` (assistant-sheet.tsx:464-511): trim text, snapshot attachments,
    /// optimistic user bubble, then stream.
    private func send(displayText: String? = nil) async {
        await ensureThread()
        guard let threadId else { return }

        let trimmedText = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Web requires non-empty text even with attachments (assistant-composer.tsx:388-394).
        guard !trimmedText.isEmpty else { return }

        let attachedIds = attachments.compactMap { UUID(uuidString: $0.recipeId)?.uuidString.lowercased() }
        let snapshotAttachments = attachments
        let bubbleText = displayText ?? trimmedText

        input = ""
        attachments = []
        isSending = true
        defer { isSending = false }
        streamingToolStatusKey = nil

        let userMessageId = "optimistic-user-\(UUID().uuidString)"
        let now = Date()
        messages.append(
            AssistantMessage(
                id: userMessageId,
                role: "user",
                text: bubbleText,
                isStreaming: false,
                metadata: AssistantMessageMetadata(
                    attachments: snapshotAttachments.isEmpty ? nil : snapshotAttachments,
                    interactiveWidget: nil,
                    pendingAction: nil,
                    actionResolution: nil,
                    followUpSuggestions: nil
                ),
                createdAt: now
            )
        )
        stampSession()

        do {
            try await consumeStream(
                threadId: threadId,
                message: trimmedText,
                attachedRecipeIds: attachedIds,
                displayText: bubbleText
            )
        } catch {
            // Drop optimistic user bubble on failure so the user can retry.
            messages.removeAll { $0.id == userMessageId }
            input = bubbleText
            attachments = snapshotAttachments
            messages.append(
                AssistantMessage(
                    id: "error-\(UUID().uuidString)",
                    role: "assistant",
                    text: UserFacingAPIError.message(for: error),
                    isStreaming: false,
                    metadata: nil,
                    createdAt: Date()
                )
            )
        }
    }

    /// Widget / follow-up submit (assistant-widget.tsx). The raw `value` goes to the server;
    /// `displayText` (optional) overrides what we render in the user bubble (e.g. for follow-ups
    /// where `value` is a verbose canned phrase).
    private func submitWidgetValue(
        _ value: String,
        displayText: String?,
        recipeAttachment: AssistantRecipeAttachment?
    ) {
        let attachments: [AssistantRecipeAttachment]
        if let recipeAttachment {
            attachments = [recipeAttachment]
        } else {
            attachments = []
        }
        input = value
        self.attachments = attachments
        Task {
            await send(displayText: displayText)
        }
    }

    // MARK: - Stream

    private func consumeStream(
        threadId: String,
        message: String,
        attachedRecipeIds: [String],
        displayText: String
    ) async throws {
        let assistantMessageId = "optimistic-assistant-\(UUID().uuidString)"
        await MainActor.run {
            messages.append(
                AssistantMessage(
                    id: assistantMessageId,
                    role: "assistant",
                    text: "",
                    isStreaming: true,
                    metadata: nil,
                    createdAt: Date()
                )
            )
        }

        let stream = try await AssistantAPI.stream(
            threadId: threadId,
            message: message,
            attachedRecipeIds: attachedRecipeIds,
            language: AppLanguagePreference.current.rawValue
        )
        for try await event in stream {
            switch event {
            case .textStart:
                updateStreamingMessage(id: assistantMessageId) { msg in
                    msg.isStreaming = true
                }
            case .textDelta(let delta):
                updateStreamingMessage(id: assistantMessageId) { msg in
                    msg.text.append(delta)
                }
            case .toolStart(let toolName, _):
                streamingToolStatusKey = AssistantToolStatusI18n.localizationKey(for: toolName)
            case .final(let data):
                streamingToolStatusKey = nil
                applyFinal(data, optimisticAssistantId: assistantMessageId)
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                return
            case .error(let code):
                streamingToolStatusKey = nil
                updateStreamingMessage(id: assistantMessageId) { msg in
                    msg.text = Bundle.currentLocalizedString(code.rawValue)
                    msg.isStreaming = false
                }
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                #endif
                return
            }
        }
    }

    private func updateStreamingMessage(id: String, _ mutate: (inout AssistantMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[index])
    }

    private func applyFinal(_ data: AssistantStreamFinalData, optimisticAssistantId: String) {
        streamingToolStatusKey = nil
        if let threadData = data.thread {
            if threadData.id != threadId {
                threadId = threadData.id
            }
            persistSession()
            promoteActiveThread(updatedTitle: threadData.title)
        } else {
            promoteActiveThread()
        }
        if let userMessage = data.userMessage,
           let userIndex = messages.lastIndex(where: { $0.id.hasPrefix("optimistic-user-") }) {
            if let id = userMessage.id {
                messages[userIndex].id = id
            }
            if let createdAt = userMessage.createdAt,
               let parsed = AssistantISO8601.parse(createdAt) {
                messages[userIndex].createdAt = parsed
            }
            // Web parity: the server returns the persisted user message with full metadata
            // (including actionResolution) in the final event. Copy it so the bubble can render
            // friendly confirm/cancel labels (e.g. "Удалить") instead of raw values.
            messages[userIndex].metadata = userMessage.metadata
        }
        if let assistant = data.assistantMessage {
            updateStreamingMessage(id: optimisticAssistantId) { msg in
                if let id = assistant.id {
                    msg.id = id
                }
                if let content = assistant.content, !content.isEmpty {
                    msg.text = content
                }
                msg.metadata = assistant.metadata
                msg.isStreaming = false
                if let createdAt = assistant.createdAt,
                   let parsed = AssistantISO8601.parse(createdAt) {
                    msg.createdAt = parsed
                }
            }
        } else {
            updateStreamingMessage(id: optimisticAssistantId) { msg in
                msg.isStreaming = false
            }
        }
    }

    // MARK: - Session persistence

    private func persistSession() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.sessionLastOpenedAtKey)
        if let threadId {
            UserDefaults.standard.set(threadId, forKey: Self.sessionThreadIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.sessionThreadIdKey)
        }
    }

    private func stampSession() {
        persistSession()
    }

    private static let sessionThreadIdKey = "assistant.session.threadId"
    private static let sessionLastOpenedAtKey = "assistant.session.lastOpenedAt"

    private func streamingPlaceholder(for message: AssistantMessage, isLast: Bool) -> String {
        if isLast,
           message.isStreaming,
           message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let streamingToolStatusKey {
            return Bundle.currentLocalizedString(streamingToolStatusKey)
        }
        return Bundle.currentLocalizedString("assistant.thinking")
    }
}
