//
//  AssistantSheet.swift
//  RecipeScalerNative
//
//  Streaming chat UI mirroring `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-sheet.tsx`.
//  Wire protocol: see `Services/AssistantAPI.swift` and spec 015/021.
//

import SwiftUI

struct AssistantSheet: View {
    @Environment(\.dismiss) private var dismiss

    let contextRecipeId: String?

    @State private var threadId: String?
    @State private var messages: [AssistantMessage] = []
    @State private var input = ""
    @State private var attachments: [AssistantRecipeAttachment] = []
    @State private var isSending = false
    @State private var loadError: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var hasTriedSessionRestore = false
    @State private var messageListContentWidth: CGFloat = 0
    @State private var inputPlaceholderVariantIndex = Int.random(in: 0..<AssistantInputPlaceholder.variantCount)

    private static let newChatTimeout: TimeInterval = 60
    private static let userMessageLeadingInset: CGFloat = 48
    private static let messageMaxWidthFraction: CGFloat = 0.9

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
            }
            .localizedNavigationTitle("assistant.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("assistant.close") { dismiss() }
                        .appToolbarTextButton()
                }
            }
            .task { await initialize() }
            .onAppear {
                inputPlaceholderVariantIndex = Int.random(in: 0..<AssistantInputPlaceholder.variantCount)
                // #region agent log
                AgentSyncDebugLog.sync(
                    location: "AssistantSheet.onAppear",
                    message: "assistant_sheet_appeared",
                    data: ["has_thread_id": threadId != nil ? "true" : "false"]
                )
                // #endregion
            }
            .onDisappear { streamTask?.cancel() }
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantSheet)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
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
        let bubble = messageBubbleBody(for: message, isLast: isLast, isUser: isUser)

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
    }

    @ViewBuilder
    private func messageBubbleBody(for message: AssistantMessage, isLast: Bool, isUser: Bool) -> some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            Text(message.text.isEmpty && message.isStreaming
                ? Bundle.currentLocalizedString("assistant.thinking")
                : message.text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(isUser ? .trailing : .leading)

            AssistantMessageFooter(
                message: message,
                isLastMessage: isLast,
                isSending: isSending,
                onWidgetSubmit: { value, attachment in
                    submitWidgetValue(value, displayText: nil, recipeAttachment: attachment)
                },
                onFollowUp: { suggestion in
                    submitWidgetValue(suggestion.value, displayText: suggestion.label, recipeAttachment: nil)
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

    /// On first appearance: try to restore a recent thread (≤60s since last close),
    /// otherwise create a new one. Mirrors web `ASSISTANT_NEW_CHAT_TIMEOUT_MS`.
    private func initialize() async {
        guard !hasTriedSessionRestore else { return }
        hasTriedSessionRestore = true

        let now = Date().timeIntervalSince1970
        let lastOpenedAt = UserDefaults.standard.double(forKey: Self.sessionLastOpenedAtKey)
        if lastOpenedAt > 0,
           now - lastOpenedAt < Self.newChatTimeout,
           let savedThreadId = UserDefaults.standard.string(forKey: Self.sessionThreadIdKey) {
            threadId = savedThreadId
            await loadHistory(for: savedThreadId)
            return
        }
        await ensureThread()
    }

    private func ensureThread() async {
        guard threadId == nil else { return }
        do {
            let thread = try await AssistantAPI.createThread()
            threadId = thread.id
            UserDefaults.standard.set(thread.id, forKey: Self.sessionThreadIdKey)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadHistory(for id: String) async {
        do {
            let history = try await AssistantAPI.getMessages(threadId: id)
            messages = history.map {
                AssistantMessage(
                    id: $0.id,
                    role: $0.role,
                    text: $0.content,
                    isStreaming: false,
                    metadata: $0.metadata
                )
            }
        } catch {
            // History load is best-effort; fall through to creating a fresh thread.
            loadError = error.localizedDescription
            threadId = nil
            await ensureThread()
        }
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

        let userMessageId = "optimistic-user-\(UUID().uuidString)"
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
                    followUpSuggestions: nil
                )
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
                    metadata: nil
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
                    metadata: nil
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
            case .toolStart:
                // Tool status rendering is optional for P2; keep streaming without a status row.
                continue
            case .final(let data):
                applyFinal(data, optimisticAssistantId: assistantMessageId)
                return
            case .error(let serverMessage):
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
        if let newThreadId = data.thread?.id, newThreadId != threadId {
            threadId = newThreadId
            UserDefaults.standard.set(newThreadId, forKey: Self.sessionThreadIdKey)
        }
        if let assistant = data.assistantMessage {
            updateStreamingMessage(id: optimisticAssistantId) { msg in
                if let content = assistant.content, !content.isEmpty {
                    msg.text = content
                }
                msg.metadata = assistant.metadata
                msg.isStreaming = false
            }
        } else {
            updateStreamingMessage(id: optimisticAssistantId) { msg in
                msg.isStreaming = false
            }
        }
    }

    // MARK: - Session persistence

    private func stampSession() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.sessionLastOpenedAtKey)
    }

    private static let sessionThreadIdKey = "assistant.session.threadId"
    private static let sessionLastOpenedAtKey = "assistant.session.lastOpenedAt"
}
