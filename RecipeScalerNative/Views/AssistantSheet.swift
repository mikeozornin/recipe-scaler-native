//
//  AssistantSheet.swift
//  RecipeScalerNative
//
//  Streaming chat UI mirroring `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-sheet.tsx`.
//  Wire protocol: see `Services/AssistantAPI.swift` and spec 015/021.
//  Spec 081 (T032a): the chat state lives in `AssistantSessionModel` (one per
//  app); this view only renders it, so the iPad panel and the compact sheet
//  show the same chat.
//

import SwiftUI
import RecipeScalerCore

/// Where the chat is shown (spec 081, plan.md Р7).
enum AssistantPresentation {
    /// The phone sheet (iPhone, compact iPad window): unchanged.
    case sheet
    /// The iPad panel beside the tabs (`.padRegular`, T032).
    case inspector
}

struct AssistantSheet: View {
    @Environment(AppShellCoordinator.self) private var coordinator
    @Environment(OfflineBannerGate.self) private var offlineGate
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext

    /// Injected (not `@Environment`): shared by the sheet and the iPad panel.
    @Bindable private var session: AssistantSessionModel
    let contextRecipeId: String?
    let openRequest: AssistantOpenRequest?
    /// Spec 078 — shake entry (auto-attach / new chat / voice).
    let shakeOpenRequest: AssistantShakeOpenRequest?
    /// Injected (not `@Environment`): the sheet subtree can be re-measured by
    /// iOS 26 in a fallback environment (bar-item sizing) after dismissal
    /// starts; `@Environment(YjsSyncService.self)` traps there.
    let syncService: YjsSyncService
    let presentation: AssistantPresentation
    /// The panel's ×; the sheet closes by swiping it down.
    let onClose: () -> Void

    @State private var showHistorySheet = false
    @State private var messageListContentWidth: CGFloat = 0

    init(
        session: AssistantSessionModel,
        contextRecipeId: String?,
        openRequest: AssistantOpenRequest? = nil,
        shakeOpenRequest: AssistantShakeOpenRequest? = nil,
        syncService: YjsSyncService,
        presentation: AssistantPresentation = .sheet,
        onClose: @escaping () -> Void = {}
    ) {
        _session = Bindable(session)
        self.contextRecipeId = contextRecipeId
        self.openRequest = openRequest
        self.shakeOpenRequest = shakeOpenRequest
        self.syncService = syncService
        self.presentation = presentation
        self.onClose = onClose
    }

    private var isOnline: Bool {
        syncService.connectionState.isConnected
    }

    /// Debounced online signal for the body branch (spec 066 `OfflineBannerGate`):
    /// hides the foreground-reconnect flash (.disconnected → .connecting →
    /// .connected after unlock/app return). Action paths stay on instant `isOnline`.
    private var showsOnlineContent: Bool {
        !offlineGate.isVisible
    }

    private static let userMessageLeadingInset: CGFloat = 48
    private static let messageMaxWidthFraction: CGFloat = 0.9

    var body: some View {
        NavigationStack {
            switch presentation {
            case .sheet:
                AssistantSheetToolbarHost(
                    onShowHistory: { showHistorySheet = true },
                    onStartNewChat: { session.startNewChat() }
                ) {
                    chat
                }
            case .inspector:
                AssistantInspectorToolbarHost(
                    isHistoryPresented: $showHistorySheet,
                    onStartNewChat: { session.startNewChat() },
                    onClose: onClose,
                    history: {
                        threadList
                            .frame(
                                width: IPadLayoutMetrics.historyPopoverWidth,
                                height: IPadLayoutMetrics.historyPopoverMaxHeight
                            )
                    }
                ) {
                    chat
                }
            }
        }
    }

    /// The history list: the phone sheet, or the panel's popover (FR-020).
    private var threadList: some View {
        AssistantThreadListSheet(
            threads: session.threads,
            activeThreadId: session.threadId,
            deletingThreadId: session.deletingThreadId,
            isLoading: session.isLoadingThreads || (session.isBootstrapping && session.threads.isEmpty),
            onSelect: { selectedId in
                showHistorySheet = false
                Task { await session.openThread(selectedId) }
            },
            onDelete: { deletedId in
                Task { await session.deleteThread(deletedId) }
            }
        )
    }

    private var chat: some View {
        VStack(spacing: 0) {
            if showsOnlineContent {
                messageList
                AssistantComposer(
                    text: $session.input,
                    attachments: $session.attachments,
                    isSending: session.isSending,
                    inputPlaceholderVariantIndex: session.inputPlaceholderVariantIndex,
                    contextRecipeId: contextRecipeId,
                    autoStartVoice: $session.autoStartVoice,
                    onSend: { session.launchSend() },
                    syncService: syncService
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
        .overlay {
            if session.isBootstrapping {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground).opacity(0.6))
            }
        }
        // The panel opens the list as its popover instead (T033).
        .sheet(isPresented: presentation == .sheet ? $showHistorySheet : .constant(false)) {
            threadList
        }
        .errorAlert(title: "assistant.error-unavailable", message: $session.loadError)
        .onChange(of: coordinator.assistantSessionEpoch) { _, _ in
            session.teardownForSessionInvalidation()
        }
        .onChange(of: isOnline) { _, connected in
            session.handleConnectivityChange(isConnected: connected)
        }
        .onChange(of: openRequest) { _, request in
            session.receiveExternalRequest(request)
        }
        .onChange(of: shakeOpenRequest) { _, request in
            session.receiveShakeRequest(request)
        }
        .onChange(of: showHistorySheet) { _, isOpen in
            if isOpen {
                session.historyDidOpen()
            }
        }
        .onAppear {
            session.viewDidAppear(shakeRequest: shakeOpenRequest)
            #if DEBUG
            AgentSyncDebugLog.sync(
                location: "AssistantSheet.onAppear",
                message: "assistant_sheet_appeared",
                data: ["has_thread_id": session.threadId != nil ? "true" : "false"]
            )
            #endif
        }
        .onDisappear {
            // Spec 081 (T032a): no teardown here — a panel ↔ sheet swap
            // must keep the chat. The shell calls `session.close()`.
            #if DEBUG
            // #region agent log
            AgentSyncDebugLog.assistantLayout(
                hypothesisId: "H1",
                location: "AssistantSheet.onDisappear",
                message: "assistant_sheet_disappeared",
                data: ["has_thread_id": session.threadId != nil ? "true" : "false"]
            )
            AgentSyncDebugLog.logNavigationBarState(
                hypothesisId: "H2",
                location: "AssistantSheet.onDisappear",
                tag: "sheet_disappear"
            )
            // #endregion
            #endif
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantSheet)
    }

    // MARK: - Message list

    private var messageList: some View {
        // Build once per body pass (not per bubble). Streaming deltas re-render the
        // sheet; recomputing these maps inside each message was O(visible × collection).
        // `collectionEntries` is already filtered to non-deleted entries.
        let lookups = AssistantAttachableRecipeLookups.build(from: syncService.collectionEntries)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(session.messages) { message in
                    let isLast = message.id == session.messages.last?.id
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
            isSending: session.isSending
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
                    session.submitWidgetValue(suggestion.value, displayText: suggestion.label, recipeAttachment: nil)
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
        if message.isToolStatusRow || message.isProcessingPlaceholder {
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
        if !isUser, message.isToolStatusRow, let toolName = message.metadata?.toolStatus?.toolName {
            AssistantToolStatusRow(toolName: toolName)
                .accessibilityIdentifier("assistant_message_\(message.id)")
        } else if !isUser, message.isProcessingPlaceholder {
            AssistantProcessingRow()
                .accessibilityIdentifier("assistant_message_\(message.id)")
        } else {
            assistantReplyOrUserBubble(for: message, isLast: isLast, isUser: isUser, lookups: lookups)
        }
    }

    @ViewBuilder
    private func assistantReplyOrUserBubble(
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
                            .appBodySelectable()
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
            } else {
                AssistantMarkdownText(content: message.text)
            }

            AssistantMessageFooter(
                message: message,
                isLastMessage: isLast,
                isSending: session.isSending,
                onWidgetSubmit: { value, displayText, attachment in
                    session.submitWidgetValue(value, displayText: displayText, recipeAttachment: attachment)
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
}

/// Toolbar host without `@Environment` — iOS 26 fallback env during sheet dismiss.
private struct AssistantSheetToolbarHost<Content: View>: View {
    let onShowHistory: () -> Void
    let onStartNewChat: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: onShowHistory) {
                        AppToolbarStyle.iconOnly(systemName: "clock.arrow.circlepath")
                    }
                    .appToolbarIconButton()
                    .accessibilityLabel(Text("assistant.threads-title"))
                    .accessibilityIdentifier(AccessibilityIdentifiers.assistantHistoryButton)

                    Button(action: onStartNewChat) {
                        AppToolbarStyle.iconOnly(systemName: "plus")
                    }
                    .appToolbarIconButton()
                    .accessibilityLabel(Text("assistant.new-chat"))
                    .accessibilityIdentifier(AccessibilityIdentifiers.assistantNewThreadButton)
                }
            }
    }
}

/// Spec 081 (T033) — the panel bar (prototype `.insp-bar`): «Ассистент» at the leading
/// edge, [history, new chat] and × at the trailing one. The history list is a popover
/// from its button (FR-020). No `@Environment` objects, as in `AssistantSheetToolbarHost`.
private struct AssistantInspectorToolbarHost<History: View, Content: View>: View {
    @Binding var isHistoryPresented: Bool
    let onStartNewChat: () -> Void
    let onClose: () -> Void
    @ViewBuilder let history: () -> History
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            titledContent
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        historyButton
                        newChatButton
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        closeButton
                    }
                }
        } else {
            titledContent
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        historyButton
                        newChatButton
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        closeButton
                    }
                }
        }
    }

    private var titledContent: some View {
        content()
            .toolbarTitleDisplayMode(.inlineLarge)
    }

    private var historyButton: some View {
        Button {
            isHistoryPresented = true
        } label: {
            AppToolbarStyle.iconOnly(systemName: "clock.arrow.circlepath")
        }
        .appToolbarIconButton()
        .accessibilityLabel(Text("assistant.threads-title"))
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantHistoryButton)
        .adaptivePopover(isPresented: $isHistoryPresented, content: history)
        // A bar item may get a fallback environment (`.phone`, a sheet); the panel
        // exists only in a wide window.
        .environment(\.appLayoutMode, .padRegular)
    }

    private var newChatButton: some View {
        Button(action: onStartNewChat) {
            AppToolbarStyle.iconOnly(systemName: "plus")
        }
        .appToolbarIconButton()
        .accessibilityLabel(Text("assistant.new-chat"))
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantNewThreadButton)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            AppToolbarStyle.iconOnly(systemName: "xmark")
        }
        .appToolbarIconButton()
        .accessibilityLabel(Text("assistant.close"))
        .accessibilityIdentifier(AccessibilityIdentifiers.ipadAssistantInspectorCloseButton)
    }
}
