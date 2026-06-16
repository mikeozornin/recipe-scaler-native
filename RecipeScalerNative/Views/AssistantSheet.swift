//
//  AssistantSheet.swift
//  RecipeScalerNative
//
//  Streaming chat UI mirroring `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-sheet.tsx`.
//  Wire protocol: see `Services/AssistantAPI.swift` and spec 015/021.
//

import SwiftUI

struct AssistantSheet: View {
    @EnvironmentObject private var syncService: YjsSyncService

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
                messageList
                if isOnline {
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
                    Text("assistant.offline.description")
                        .appFootnote()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .accessibilityIdentifier(AccessibilityIdentifiers.assistantOfflineFootnote)
                }
            }
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
                .presentationDetents([.medium, .large])
            }
            .alert(
                "assistant.error-unavailable",
                isPresented: Binding(
                    get: { loadError != nil },
                    set: { if !$0 { loadError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { loadError = nil }
            } message: {
                if let loadError {
                    Text(verbatim: loadError)
                }
            }
            .task { await initialize() }
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
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(messages.indices, id: \.self) { index in
                    let message = messages[index]
                    let isLast = index == messages.indices.last
                    messageBubble(for: message, isLast: isLast)
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
    private func messageBubble(for message: AssistantMessage, isLast: Bool) -> some View {
        let isUser = message.role == "user"
        let showMeta = shouldShowMessageMeta(for: message)
        let followUps = AssistantMessageFollowUps.suggestions(
            for: message,
            isLastMessage: isLast,
            isSending: isSending
        )
        let bubble = messageBubbleBody(for: message, isLast: isLast, isUser: isUser)

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
                AssistantMessageMetaRow(message: message, isUser: isUser)
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
    private func messageBubbleBody(for message: AssistantMessage, isLast: Bool, isUser: Bool) -> some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if isUser {
                // Web parity: user-bubble shows the friendlier resolved text (e.g. "Удалить"
                // instead of "confirm_delete") for messages that resolved a pending action.
                Text(AssistantMessageCopyText.text(for: message))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            } else if message.text.isEmpty && message.isStreaming {
                Text(verbatim: streamingPlaceholder(for: message, isLast: isLast))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
            } else {
                AssistantMarkdownText(content: message.text)
            }

            AssistantMessageFooter(
                message: message,
                isLastMessage: isLast,
                isSending: isSending,
                onWidgetSubmit: { value, attachment in
                    submitWidgetValue(value, displayText: nil, recipeAttachment: attachment)
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
        hasTriedSessionRestore = true
        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            threads = try await AssistantAPI.listThreads()
        } catch {
            loadError = error.localizedDescription
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
            let thread = try await AssistantAPI.createThread()
            threadId = thread.id
            threads.insert(thread, at: 0)
            persistSession()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func refreshThreadsList() async {
        if threads.isEmpty {
            isLoadingThreads = true
        }
        defer { isLoadingThreads = false }
        do {
            threads = try await AssistantAPI.listThreads()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deleteThread(_ id: String) async {
        deletingThreadId = id
        defer { deletingThreadId = nil }
        do {
            try await AssistantAPI.deleteThread(threadId: id)
            threads.removeAll { $0.id == id }
            if threadId == id {
                if let nextThread = threads.first {
                    await openThread(nextThread.id)
                } else {
                    startNewChat()
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadHistory(for id: String) async {
        do {
            let history = try await AssistantAPI.getMessages(threadId: id)
            // #region agent log
            for msg in history.prefix(10) {
                AssistantPendingActionDebugTrace.write(
                    hypothesisId: "H1A-H2A-H3A",
                    location: "AssistantSheet.loadHistory:message",
                    message: "server message loaded from history",
                    data: [
                        "msg_id": msg.id,
                        "role": msg.role,
                        "content_head": String(msg.content.prefix(80)),
                        "content_len": String(msg.content.count),
                        "hasMetadata": (msg.metadata != nil).description,
                        "hasPendingAction": (msg.metadata?.pendingAction != nil).description,
                        "pendingActionStatus": msg.metadata?.pendingAction?.status.rawValue ?? "nil",
                        "hasInteractiveWidget": (msg.metadata?.interactiveWidget != nil).description,
                        "hasActionResolution": (msg.metadata?.actionResolution != nil).description,
                        "actionResolutionSource": msg.metadata?.actionResolution?.source ?? "nil"
                    ]
                )
            }
            // #endregion
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
            loadError = error.localizedDescription
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
    private func send() async {
        await ensureThread()
        guard let threadId else { return }

        let trimmedText = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Web requires non-empty text even with attachments (assistant-composer.tsx:388-394).
        guard !trimmedText.isEmpty else { return }

        let attachedIds = attachments.compactMap { UUID(uuidString: $0.recipeId)?.uuidString.lowercased() }
        let snapshotAttachments = attachments
        let displayText = trimmedText

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
                text: displayText,
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
                displayText: displayText
            )
        } catch {
            // Drop optimistic user bubble on failure so the user can retry.
            messages.removeAll { $0.id == userMessageId }
            input = displayText
            attachments = snapshotAttachments
            messages.append(
                AssistantMessage(
                    id: "error-\(UUID().uuidString)",
                    role: "assistant",
                    text: error.localizedDescription,
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
        // #region agent log
        AssistantPendingActionDebugTrace.write(
            hypothesisId: "H2A",
            location: "AssistantSheet.submitWidgetValue",
            message: "widget value submitted",
            data: [
                "value": value,
                "displayText": displayText ?? "nil"
            ]
        )
        // #endregion
        let attachments: [AssistantRecipeAttachment]
        if let recipeAttachment {
            attachments = [recipeAttachment]
        } else {
            attachments = []
        }
        input = value
        self.attachments = attachments
        Task {
            await send()
            // After widget submit, restore the visible text to the friendlier displayText
            // (the server still received `value`).
            if let displayText, let lastUserIndex = messages.lastIndex(where: { $0.role == "user" }) {
                messages[lastUserIndex].text = displayText
            }
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
            attachedRecipeIds: attachedRecipeIds
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
                return
            case .error(let serverMessage):
                streamingToolStatusKey = nil
                updateStreamingMessage(id: assistantMessageId) { msg in
                    msg.text = Bundle.currentLocalizedString(serverMessage)
                    msg.isStreaming = false
                }
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
        // #region agent log
        AssistantPendingActionDebugTrace.write(
            hypothesisId: "H2A-H3A-H3B",
            location: "AssistantSheet.applyFinal:entry",
            message: "final event received",
            data: [
                "userMessage.id": data.userMessage?.id ?? "nil",
                "userMessage.content": data.userMessage?.content ?? "nil",
                "assistantMessage.id": data.assistantMessage?.id ?? "nil",
                "assistantMessage.content": data.assistantMessage?.content ?? "nil",
                "assistantMessage.content.isEmpty": (data.assistantMessage?.content?.isEmpty ?? true).description,
                "assistantMessage.metadata.hasPendingAction": (data.assistantMessage?.metadata?.pendingAction != nil).description,
                "assistantMessage.metadata.pendingActionStatus": data.assistantMessage?.metadata?.pendingAction?.status.rawValue ?? "nil",
                "assistantMessage.metadata.hasInteractiveWidget": (data.assistantMessage?.metadata?.interactiveWidget != nil).description,
                "assistantMessage.metadata.hasActionResolution": (data.assistantMessage?.metadata?.actionResolution != nil).description,
                "userMessage.metadata.hasActionResolution": (data.userMessage?.metadata?.actionResolution != nil).description
            ]
        )
        // #endregion
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
            // #region agent log
            AssistantPendingActionDebugTrace.write(
                hypothesisId: "H2A",
                location: "AssistantSheet.applyFinal:userMessage",
                message: "patching optimistic user message",
                data: [
                    "optimisticIndex": String(userIndex),
                    "before_text": messages[userIndex].text,
                    "before_hasMetadata": (messages[userIndex].metadata != nil).description,
                    "before_hasActionResolution": (messages[userIndex].metadata?.actionResolution != nil).description,
                    "server_id": userMessage.id ?? "nil",
                    "server_content": userMessage.content ?? "nil",
                    "server_hasMetadata": (userMessage.metadata != nil).description,
                    "server_hasActionResolution": (userMessage.metadata?.actionResolution != nil).description
                ]
            )
            // #endregion
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
                // #region agent log
                AssistantPendingActionDebugTrace.write(
                    hypothesisId: "H1A-H3A",
                    location: "AssistantSheet.applyFinal:assistantMessage:postUpdate",
                    message: "assistant streaming message finalized",
                    data: [
                        "final_id": msg.id,
                        "final_text_len": String(msg.text.count),
                        "final_text_head": String(msg.text.prefix(80)),
                        "final_isStreaming": msg.isStreaming.description,
                        "final_hasMetadata": (msg.metadata != nil).description,
                        "final_hasInteractiveWidget": (msg.metadata?.interactiveWidget != nil).description,
                        "final_hasPendingAction": (msg.metadata?.pendingAction != nil).description,
                        "final_pendingActionStatus": msg.metadata?.pendingAction?.status.rawValue ?? "nil"
                    ]
                )
                // #endregion
            }
        } else {
            // #region agent log
            AssistantPendingActionDebugTrace.write(
                hypothesisId: "H3A",
                location: "AssistantSheet.applyFinal:noAssistantMessage",
                message: "final event has no assistantMessage — keeping optimistic bubble",
                data: ["optimisticId": optimisticAssistantId]
            )
            // #endregion
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
