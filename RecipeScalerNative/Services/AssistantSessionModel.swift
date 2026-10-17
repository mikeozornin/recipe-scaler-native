//
//  AssistantSessionModel.swift
//  RecipeScalerNative
//
//  Spec 081 (T032a) — the assistant chat session, moved out of `AssistantSheet`.
//  One instance lives in `AppContainer`, so the iPad panel and the compact
//  sheet show the same chat: a size-class swap keeps the messages, the draft
//  and the in-flight stream. The logic is the former `AssistantSheet` state
//  machine, unchanged; only the lifecycle hooks are explicit now:
//
//  - `beginPresentation` — the shell opens the assistant (sheet or panel).
//    Starts like the old freshly built sheet (bootstrap, ≤60 s thread restore),
//    except the composer draft: it survives close and reopen (plan.md Р7).
//  - `viewDidAppear` — a presentation became visible. Called again by the
//    other presentation on a swap; idempotent.
//  - `close` — the shell closed the assistant: persist, cancel in-flight work
//    (the former `onDisappear`). The content stays until the next
//    `beginPresentation` so the dismissal animation keeps its content.
//  - `resetForLogout` — account-scoped teardown from the composition root.
//

import Foundation
import RecipeScalerCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Network + persistence seams of the session (live: `AssistantAPI` +
/// `AssistantSessionStore`; tests: in-memory fakes, no network).
struct AssistantSessionClient {
    var listThreads: @MainActor () async throws -> [AssistantThreadDTO]
    var createThread: @MainActor () async throws -> AssistantThreadDTO
    var getMessages: @MainActor (_ threadId: String) async throws -> [AssistantMessageDTO]
    var deleteThread: @MainActor (_ threadId: String) async throws -> Void
    var stream: @MainActor (
        _ threadId: String,
        _ message: String,
        _ attachedRecipeIds: [String]
    ) async throws -> AsyncThrowingStream<AssistantStreamEvent, Error>
    var savedThreadId: @MainActor () -> String?
    var lastOpenedAt: @MainActor () -> TimeInterval
    var persistThreadId: @MainActor (_ threadId: String?) -> Void
    var clearThreadId: @MainActor () -> Void

    static let live = AssistantSessionClient(
        listThreads: {
            try await AssistantAPI.listThreads(language: AppLanguagePreference.current.rawValue)
        },
        createThread: {
            try await AssistantAPI.createThread(language: AppLanguagePreference.current.rawValue)
        },
        getMessages: { threadId in
            try await AssistantAPI.getMessages(threadId: threadId, language: AppLanguagePreference.current.rawValue)
        },
        deleteThread: { threadId in
            try await AssistantAPI.deleteThread(threadId: threadId, language: AppLanguagePreference.current.rawValue)
        },
        stream: { threadId, message, attachedRecipeIds in
            try await AssistantAPI.stream(
                threadId: threadId,
                message: message,
                attachedRecipeIds: attachedRecipeIds,
                language: AppLanguagePreference.current.rawValue
            )
        },
        savedThreadId: { AssistantSessionStore.threadId },
        lastOpenedAt: { AssistantSessionStore.lastOpenedAt },
        persistThreadId: { threadId in AssistantSessionStore.persist(threadId: threadId) },
        clearThreadId: { AssistantSessionStore.clearThreadId() }
    )
}

@MainActor
@Observable
final class AssistantSessionModel {
    // MARK: - State read by the views

    private(set) var threadId: String?
    private(set) var threads: [AssistantThreadDTO] = []
    private(set) var messages: [AssistantMessage] = []
    var input = ""
    var attachments: [AssistantRecipeAttachment] = []
    private(set) var isSending = false
    private(set) var isBootstrapping = false
    private(set) var isLoadingThreads = false
    var loadError: String?
    private(set) var deletingThreadId: String?
    var autoStartVoice = false
    private(set) var inputPlaceholderVariantIndex = Int.random(in: 0..<AssistantInputPlaceholder.variantCount)

    // MARK: - Bookkeeping (not rendered)

    @ObservationIgnored private let client: AssistantSessionClient
    @ObservationIgnored private let isOnlineProvider: () -> Bool
    @ObservationIgnored private let collectionEntriesProvider: () -> [CollectionEntry]

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var threadsRefreshTask: Task<Void, Never>?
    /// The first bootstrap of a presentation (formerly the sheet's `.task`).
    /// Owned here, not by a view, so a panel ↔ sheet swap does not cancel it.
    @ObservationIgnored private var initialBootstrapTask: Task<Void, Never>?
    /// Reconnect bootstrap (formerly started from `.onChange(of: isOnline)`).
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var externalSendTask: Task<Void, Never>?
    @ObservationIgnored private var hasTriedSessionRestore = false
    @ObservationIgnored private var pendingExternalRequest: AssistantOpenRequest?
    @ObservationIgnored private var handledExternalRequestId: Int?
    @ObservationIgnored private var pendingShakeRequest: AssistantShakeOpenRequest?
    @ObservationIgnored private var handledShakeRequestId: Int?
    /// Spec 081 (FR-021) — this presentation opens a new chat, not the recent one (✦ on
    /// «Покупки» / «Подборки» of the iPad). Set by `beginPresentation`.
    @ObservationIgnored private var startsNewChatOnOpen = false
    /// The recipe the assistant was opened from: a new chat of this presentation starts
    /// with it attached. Set by `beginPresentation`.
    @ObservationIgnored private var presentationContextRecipeId: String?
    @ObservationIgnored private var interactionGeneration = 0
    /// Bumped by `beginPresentation`, `close` and `resetForLogout`: work that
    /// is not generation-guarded (thread delete) must not land in a later
    /// presentation.
    @ObservationIgnored private var presentationEpoch = 0
    /// Message scheduled by an external request but not yet delivered to a
    /// thread (offline / bootstrap / createThread failure). Survives
    /// offline→online transitions and is restored into the composer bubble.
    @ObservationIgnored private var undeliveredPrompt: String?
    /// Streamed text not yet applied to `pendingStreamMessageId`: deltas are applied
    /// at most every `AssistantStreamFlushThrottle.interval` instead of per token, so
    /// a long reply does not re-render the chat (and copy its text) hundreds of times.
    @ObservationIgnored private var pendingStreamText = ""
    @ObservationIgnored private var pendingStreamMessageId: String?
    @ObservationIgnored private var streamFlushThrottle = AssistantStreamFlushThrottle()
    @ObservationIgnored private var streamFlushTask: Task<Void, Never>?

    private static let newChatTimeout: TimeInterval = 60

    init(
        client: AssistantSessionClient = .live,
        isOnline: @escaping () -> Bool,
        collectionEntries: @escaping () -> [CollectionEntry]
    ) {
        self.client = client
        self.isOnlineProvider = isOnline
        self.collectionEntriesProvider = collectionEntries
    }

    private var isOnline: Bool {
        isOnlineProvider()
    }

    // MARK: - Presentation lifecycle

    /// The shell opens the assistant. Equivalent to building a fresh sheet
    /// (a closed chat reopens through the ≤60 s restore, as before), except
    /// the typed draft, which survives close and reopen (plan.md Р7).
    /// `startsNewChat`: skip the ≤60 s restore (spec 081, FR-021); the draft still stays.
    func beginPresentation(
        openRequest: AssistantOpenRequest?,
        shakeRequest: AssistantShakeOpenRequest?,
        contextRecipeId: String? = nil,
        startsNewChat: Bool = false
    ) {
        cancelAllWork()
        presentationEpoch &+= 1
        let draft = input
        resetContent()
        input = draft
        hasTriedSessionRestore = false
        handledExternalRequestId = nil
        handledShakeRequestId = nil
        pendingExternalRequest = openRequest
        pendingShakeRequest = shakeRequest
        startsNewChatOnOpen = startsNewChat
        presentationContextRecipeId = contextRecipeId
        inputPlaceholderVariantIndex = Int.random(in: 0..<AssistantInputPlaceholder.variantCount)
    }

    /// A presentation (sheet or panel) became visible. Runs again on a swap,
    /// so everything here is idempotent: the shake intent is deduplicated by
    /// id and the bootstrap starts once per presentation.
    func viewDidAppear(shakeRequest: AssistantShakeOpenRequest?) {
        receiveShakeRequest(shakeRequest)
        // The handle stays after completion: a finished bootstrap must not
        // rerun on a swap. `beginPresentation` / `close` clear it.
        guard initialBootstrapTask == nil else { return }
        initialBootstrapTask = Task { @MainActor in
            await self.bootstrapIfNeeded()
        }
    }

    /// The shell closed the assistant (the former sheet `onDisappear`).
    func close() {
        persistSession()
        cancelAllWork()
        presentationEpoch &+= 1
        undeliveredPrompt = nil
    }

    /// Logout / account switch from the composition root: nothing of the
    /// outgoing account survives, including the draft.
    func resetForLogout() {
        cancelAllWork()
        presentationEpoch &+= 1
        resetContent()
        hasTriedSessionRestore = false
        handledExternalRequestId = nil
        handledShakeRequestId = nil
        pendingExternalRequest = nil
        pendingShakeRequest = nil
        startsNewChatOnOpen = false
        presentationContextRecipeId = nil
    }

    /// Logout / account switch while a presentation is visible (the chat's
    /// `assistantSessionEpoch` observer): the same reset as `resetForLogout`,
    /// which the container has usually run already. Every in-flight task of the
    /// dead session is cancelled — the first bootstrap and the history refresh
    /// too — and its pending shake or external request is dropped, so nothing
    /// lands in the next session.
    func teardownForSessionInvalidation() {
        resetForLogout()
    }

    func handleConnectivityChange(isConnected: Bool) {
        guard isConnected else { return }
        bootstrapTask?.cancel()
        bootstrapTask = Task { @MainActor in
            await self.bootstrapIfNeeded()
        }
    }

    /// History list opened: refresh it (single-flight, see `refreshThreadsList`).
    func historyDidOpen() {
        threadsRefreshTask?.cancel()
        threadsRefreshTask = Task { await self.refreshThreadsList() }
    }

    private func cancelAllWork() {
        // Deltas already received stay in the (kept) messages, as before coalescing.
        flushStreamText()
        initialBootstrapTask?.cancel()
        initialBootstrapTask = nil
        bootstrapTask?.cancel()
        bootstrapTask = nil
        externalSendTask?.cancel()
        externalSendTask = nil
        streamTask?.cancel()
        streamTask = nil
        threadsRefreshTask?.cancel()
        threadsRefreshTask = nil
        interactionGeneration &+= 1
    }

    /// The state a freshly built sheet started with.
    private func resetContent() {
        threadId = nil
        threads = []
        messages = []
        input = ""
        attachments = []
        isSending = false
        isBootstrapping = false
        isLoadingThreads = false
        loadError = nil
        deletingThreadId = nil
        autoStartVoice = false
        undeliveredPrompt = nil
    }

    // MARK: - Bootstrap

    private func bootstrapIfNeeded() async {
        await initialize()
        guard !Task.isCancelled else {
            hasTriedSessionRestore = false
            return
        }
        if let shake = pendingShakeRequest {
            applyShakeSideEffects(shake)
        }
        scheduleExternalSendIfNeeded()
        deliverUndeliveredPromptIfReady()
    }

    /// On first appearance: load thread list, then restore recent thread (≤60s) or start empty chat.
    /// Mirrors web `buildInitialSelection` + `useAssistantChat` bootstrap.
    private func initialize() async {
        guard !hasTriedSessionRestore else { return }
        // While offline, show the offline state instead of a network bootstrap spinner.
        // `hasTriedSessionRestore` stays false so the bootstrap runs once the connection
        // comes back (see `handleConnectivityChange`).
        guard isOnline else { return }
        let generation = interactionGeneration
        hasTriedSessionRestore = true
        #if DEBUG
        if DebugLaunchOptions.screenshotAssistantFixture {
            applyScreenshotAssistantFixture()
            return
        }
        #endif
        isBootstrapping = true
        defer {
            isBootstrapping = false
        }

        do {
            let fetchedThreads = try await client.listThreads()
            guard isCurrent(generation) else { return }
            threads = fetchedThreads
        } catch {
            guard !Task.isCancelled else { return }
            loadError = UserFacingAPIError.message(for: error)
            threads = []
        }
        guard isCurrent(generation) else { return }

        if let pendingExternalRequest {
            handledExternalRequestId = pendingExternalRequest.requestId
            startNewChat(clearExternalRequest: false)
            return
        }

        if let shake = pendingShakeRequest, shake.forceNewChat {
            applyShakeSideEffects(shake)
            return
        }

        if startsNewChatOnOpen {
            startNewChat(keepsDraft: true, attachingRecipeId: presentationContextRecipeId)
            return
        }

        let now = Date().timeIntervalSince1970
        let lastOpenedAt = client.lastOpenedAt()
        if lastOpenedAt > 0,
           now - lastOpenedAt < Self.newChatTimeout,
           let savedThreadId = client.savedThreadId(),
           threads.contains(where: { $0.id == savedThreadId }) {
            guard isCurrent(generation) else { return }
            await openThread(savedThreadId)
            return
        }
        guard isCurrent(generation) else { return }
        // Automatic, not the user's «новый чат»: the draft stays (plan.md Р7).
        startNewChat(keepsDraft: true, attachingRecipeId: presentationContextRecipeId)
    }

    #if DEBUG
    private func applyScreenshotAssistantFixture() {
        let isEnglish = AppLanguagePreference.current == .en
        let isCookies = DebugLaunchOptions.screenshotAssistantTopic == "cookies"
        let stamp = AssistantISO8601.parse("2026-04-12T10:00:00.000Z") ?? Date()
        let question: String
        let reply: String
        if isCookies {
            // iPad store shot 05 sits beside «Печенье с шоколадом» / «Chocolate Cookies».
            // The composer hint is pinned to «adapt this recipe for 6 servings»: a random one may name strudel.
            inputPlaceholderVariantIndex = 4
            question = isEnglish
                ? "My cookies spread in the oven. What should I do?"
                : "Печенье растекается, что делать?"
            reply = isEnglish
                ? "Usually the dough is just too warm, and that is easy to fix.\n\n1. Chill the dough for 30-60 minutes before baking.\n2. Use butter that is soft but not melted.\n3. Check the flour: with too little, the dough runs.\n\nThen put the dough balls on a cool baking sheet, not a hot one from the last batch."
                : "Чаще всего тесто просто слишком теплое, и это легко исправить.\n\n1. Убери тесто в холодильник на 30-60 минут перед выпечкой.\n2. Масло бери мягкое, но не растопленное.\n3. Проверь муку: если ее меньше, чем в рецепте, тесто поплывет.\n\nВыкладывай шарики на холодный противень, а не на горячий после прошлой партии."
        } else {
            question = isEnglish
                ? "My sauce split. How can I save the pasta?"
                : "Соус свернулся. Как спасти пасту?"
            reply = isEnglish
                ? "Don't panic: you can usually bring the sauce back.\n\n1. Take the pan off the heat and let it rest for 20-30 seconds.\n2. Add 1-2 spoonfuls of warm pasta water and whisk quickly.\n3. If it still looks grainy, stir in a little cold butter.\n\nThen keep the sauce over low heat and do not let it boil."
                : "Спокойно: чаще всего соус можно вернуть.\n\n1. Сними сковороду с огня и дай ей постоять 20-30 секунд.\n2. Добавь 1-2 ложки теплой воды от пасты и энергично размешай.\n3. Если соус все еще зернистый, вмешай немного холодного сливочного масла.\n\nДальше держи соус на слабом огне и не давай ему кипеть."
        }
        threadId = "about-assistant-thread"
        messages = [
            AssistantMessage(
                id: "about-assistant-user-message",
                role: "user",
                text: question,
                isStreaming: false,
                metadata: nil,
                createdAt: stamp
            ),
            AssistantMessage(
                id: "about-assistant-reply",
                role: "assistant",
                text: reply,
                isStreaming: false,
                metadata: nil,
                createdAt: stamp
            ),
        ]
    }
    #endif

    // MARK: - Threads

    /// `keepsDraft`: an automatic new chat (bootstrap, a vanished thread)
    /// keeps the typed text; the user's «новый чат» and external intents clear it.
    /// `attachingRecipeId`: the recipe the chat starts from, attached by default.
    func startNewChat(
        clearExternalRequest: Bool = true,
        keepsDraft: Bool = false,
        attachingRecipeId: String? = nil
    ) {
        interactionGeneration &+= 1
        isSending = false
        externalSendTask?.cancel()
        externalSendTask = nil
        streamTask?.cancel()
        streamTask = nil
        discardStreamText()
        threadId = nil
        messages = []
        if !keepsDraft {
            input = ""
        }
        attachments = []
        if let attachingRecipeId {
            autoAttachRecipe(attachingRecipeId)
        }
        if clearExternalRequest {
            pendingExternalRequest = nil
        }
        client.clearThreadId()
    }

    func openThread(_ id: String) async {
        interactionGeneration &+= 1
        let generation = interactionGeneration
        isSending = false
        externalSendTask?.cancel()
        externalSendTask = nil
        streamTask?.cancel()
        streamTask = nil
        discardStreamText()
        pendingExternalRequest = nil
        threadId = id
        persistSession()
        await loadHistory(for: id, expectedGeneration: generation)
    }

    func receiveExternalRequest(_ request: AssistantOpenRequest?) {
        guard let request else { return }
        let trimmed = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, handledExternalRequestId != request.requestId else { return }
        handledExternalRequestId = request.requestId
        pendingExternalRequest = AssistantOpenRequest(requestId: request.requestId, message: trimmed)
        startNewChat(clearExternalRequest: false)
        if hasTriedSessionRestore, isOnline, !isBootstrapping {
            scheduleExternalSendIfNeeded()
        }
    }

    /// Spec 078 — queue shake intent; apply immediately once bootstrap finished.
    func receiveShakeRequest(_ request: AssistantShakeOpenRequest?) {
        guard let request else { return }
        guard handledShakeRequestId != request.requestId else { return }
        pendingShakeRequest = request
        if hasTriedSessionRestore {
            applyShakeSideEffects(request)
        }
    }

    private func applyShakeSideEffects(_ request: AssistantShakeOpenRequest) {
        guard handledShakeRequestId != request.requestId else { return }
        handledShakeRequestId = request.requestId
        if request.forceNewChat {
            startNewChat()
        }
        if let recipeId = request.attachRecipeId {
            autoAttachRecipe(recipeId)
        }
        if request.startVoiceRecording {
            autoStartVoice = true
        }
    }

    private func autoAttachRecipe(_ recipeId: String) {
        let alreadyAttached = attachments.contains {
            $0.recipeId.caseInsensitiveCompare(recipeId) == .orderedSame
        }
        guard !alreadyAttached, attachments.count < 10 else { return }
        guard let entry = collectionEntriesProvider().first(where: {
            !$0.deleted && $0.id.caseInsensitiveCompare(recipeId) == .orderedSame
        }) else { return }
        attachments.append(
            AssistantRecipeAttachment(
                recipeId: entry.id,
                recipeName: entry.name,
                recipeColor: entry.color
            )
        )
    }

    private func scheduleExternalSendIfNeeded() {
        guard !Task.isCancelled,
              isOnline,
              !isBootstrapping,
              let request = pendingExternalRequest else { return }
        externalSendTask?.cancel()
        let generation = interactionGeneration
        let requestId = request.requestId
        externalSendTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  self.isCurrent(generation),
                  let current = self.pendingExternalRequest,
                  current.requestId == requestId else { return }
            self.pendingExternalRequest = nil
            self.externalSendTask = nil
            // If the user already started a manual send (stream still in flight),
            // do NOT cancel their action to inject the autosend — park it in the
            // composer instead. Completed/cancelled streams clear `streamTask`.
            if self.isSending {
                self.input = current.message
                return
            }
            self.launchSend(
                message: current.message,
                displayText: current.message,
                expectedGeneration: generation
            )
        }
    }

    /// Delivers a prompt that could not be sent earlier (offline or failed
    /// createThread) once the sheet is usable again. A newer external request
    /// always takes precedence; the undelivered prompt then remains in the
    /// composer input for the user to send manually.
    private func deliverUndeliveredPromptIfReady() {
        guard let prompt = undeliveredPrompt else { return }
        guard isOnline, !isBootstrapping, pendingExternalRequest == nil, !isSending else { return }
        undeliveredPrompt = nil
        launchSend(message: prompt, displayText: prompt)
    }

    func launchSend(
        message: String? = nil,
        displayText: String? = nil,
        expectedGeneration: Int? = nil
    ) {
        // New manual/queued send supersedes any still-pending stream task. The
        // deferred-autosend path guards itself BEFORE calling this (parks the
        // prompt when a stream is in flight), so cancel here only ever replaces
        // a superseded or completed stream.
        let generation = expectedGeneration ?? interactionGeneration
        streamTask?.cancel()
        streamTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            await self.send(
                message: message,
                displayText: displayText,
                expectedGeneration: generation
            )
        }
    }

    private func isCurrent(_ generation: Int?) -> Bool {
        !Task.isCancelled && (generation == nil || generation == interactionGeneration)
    }

    private func ensureThread(expectedGeneration: Int? = nil) async {
        guard threadId == nil, isCurrent(expectedGeneration) else { return }
        do {
            let thread = try await client.createThread()
            guard isCurrent(expectedGeneration) else { return }
            threadId = thread.id
            threads.insert(thread, at: 0)
            persistSession()
        } catch {
            guard isCurrent(expectedGeneration) else { return }
            loadError = UserFacingAPIError.message(for: error)
        }
    }

    private func refreshThreadsList() async {
        // Thread creation mutates `threads` locally; a refresh that started
        // earlier and resolves later would still hold a pre-creation snapshot.
        // Single-flight guard: the merge applies only while this is still the
        // newest refresh task (`threadsRefreshTask === currentTask`); a newer
        // refresh replaces the token, invalidating ours. The merge also
        // preserves threads created locally after this refresh began.
        let generation = interactionGeneration
        let currentTask = threadsRefreshTask
        let initialThreadIds = Set(threads.map(\.id))
        if threads.isEmpty {
            isLoadingThreads = true
        }
        defer {
            if generation == interactionGeneration,
               threadsRefreshTask == nil || threadsRefreshTask == currentTask {
                isLoadingThreads = false
            }
        }
        do {
            let fetchedThreads = try await client.listThreads()
            guard isCurrent(generation),
                  threadsRefreshTask == currentTask else { return }

            let fetchedThreadIds = Set(fetchedThreads.map(\.id))
            let activeThread = threadId.flatMap { activeId in
                threads.first { $0.id == activeId }
            }
            let locallyCreatedThreads = threads.filter {
                !initialThreadIds.contains($0.id) && !fetchedThreadIds.contains($0.id)
            }
            var mergedThreads = fetchedThreads
            if let activeThread {
                if let index = mergedThreads.firstIndex(where: { $0.id == activeThread.id }) {
                    mergedThreads[index] = activeThread
                } else {
                    mergedThreads.insert(activeThread, at: 0)
                }
            }
            for thread in locallyCreatedThreads where !mergedThreads.contains(where: { $0.id == thread.id }) {
                mergedThreads.insert(thread, at: 0)
            }
            threads = mergedThreads
        } catch {
            guard isCurrent(generation),
                  threadsRefreshTask == currentTask else { return }
            loadError = UserFacingAPIError.message(for: error)
        }
    }

    func deleteThread(_ id: String) async {
        let epoch = presentationEpoch
        deletingThreadId = id
        do {
            try await client.deleteThread(id)
            guard presentationEpoch == epoch else { return }
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
            guard presentationEpoch == epoch else { return }
            deletingThreadId = nil
            loadError = UserFacingAPIError.message(for: error)
        }
    }

    private func loadHistory(for id: String, expectedGeneration: Int? = nil) async {
        guard isCurrent(expectedGeneration), threadId == id else { return }
        do {
            let history = try await client.getMessages(id)
            guard isCurrent(expectedGeneration), threadId == id else { return }
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
            guard isCurrent(expectedGeneration), threadId == id else { return }
            loadError = UserFacingAPIError.message(for: error)
            if threadId == id {
                threads.removeAll { $0.id == id }
                startNewChat(keepsDraft: true)
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
    private func send(
        message: String? = nil,
        displayText: String? = nil,
        expectedGeneration: Int? = nil
    ) async {
        let generation = expectedGeneration ?? interactionGeneration
        guard isCurrent(generation) else { return }

        let sourceText = message ?? input
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Web requires non-empty text even with attachments (assistant-composer.tsx:388-394).
        guard !trimmedText.isEmpty else { return }

        if !isOnline {
            // Keep the prompt instead of silently dropping it: store it so the
            // reconnect path can deliver it, and surface it back in the composer.
            undeliveredPrompt = trimmedText
            input = bubbleRestoreText(for: message, displayText: displayText) ?? trimmedText
            return
        }

        await ensureThread(expectedGeneration: generation)
        guard isCurrent(generation), let threadId else {
            // createThread failed — keep the prompt for retry instead of losing it.
            undeliveredPrompt = trimmedText
            input = bubbleRestoreText(for: message, displayText: displayText) ?? trimmedText
            return
        }

        let snapshotAttachments = message == nil ? attachments : []
        let attachedIds = snapshotAttachments.compactMap {
            UUID(uuidString: $0.recipeId)?.uuidString.lowercased()
        }
        let bubbleText = displayText ?? trimmedText

        input = ""
        attachments = []
        isSending = true
        defer {
            if generation == interactionGeneration {
                isSending = false
            }
        }

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
                displayText: bubbleText,
                generation: generation
            )
        } catch {
            guard isCurrent(generation) else { return }
            removeAllOptimisticMessages()
            input = bubbleRestoreText(for: message, displayText: displayText) ?? bubbleText
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
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
        }
    }

    /// External autosends pass `message != nil`; their prompt must return to the
    /// composer verbatim. Manual composer sends restore the raw typed text.
    private func bubbleRestoreText(for message: String?, displayText: String?) -> String? {
        guard message != nil else { return nil }
        return displayText
    }

    /// Widget / follow-up submit (assistant-widget.tsx). The raw `value` goes to the server;
    /// `displayText` (optional) overrides what we render in the user bubble (e.g. for follow-ups
    /// where `value` is a verbose canned phrase).
    func submitWidgetValue(
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
        launchSend(displayText: displayText)
    }

    // MARK: - Stream

    private func consumeStream(
        threadId: String,
        message: String,
        attachedRecipeIds: [String],
        displayText: String,
        generation: Int
    ) async throws {
        guard isCurrent(generation) else { return }
        let assistantMessageId = "optimistic-assistant-\(UUID().uuidString)"
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
        guard isCurrent(generation) else { return }

        let stream = try await client.stream(threadId, message, attachedRecipeIds)
        guard isCurrent(generation) else { return }
        // Whatever way the stream ends, text it delivered lands in the message.
        defer { flushStreamText() }
        for try await event in stream {
            guard isCurrent(generation) else { return }
            if case .textDelta(let delta) = event {
                bufferStreamText(delta, messageId: assistantMessageId, generation: generation)
                continue
            }
            // Every other event applies in order after the text received before it.
            flushStreamText()
            switch event {
            case .textStart:
                updateStreamingMessage(id: assistantMessageId) { msg in
                    msg.isStreaming = true
                }
            case .textDelta:
                break
            case .toolStart(let toolName, _):
                insertOptimisticToolStatusRow(toolName: toolName, assistantMessageId: assistantMessageId)
            case .final(let data):
                applyFinal(data, optimisticAssistantId: assistantMessageId)
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                return
            case .error(let code):
                throw APIError.serverError(code: code)
            }
        }
    }

    private func insertOptimisticToolStatusRow(toolName: String, assistantMessageId: String) {
        let toolMessage = AssistantMessage.optimisticToolStatus(toolName: toolName)
        guard let assistantIndex = messages.firstIndex(where: { $0.id == assistantMessageId }) else {
            messages.append(toolMessage)
            return
        }
        let assistantMessage = messages[assistantIndex]
        messages.remove(at: assistantIndex)
        messages.append(toolMessage)
        messages.append(assistantMessage)
    }

    private func removeAllOptimisticMessages() {
        messages.removeAll { AssistantMessage.isOptimisticID($0.id) }
    }

    /// Leading edge: the first delta after a quiet interval shows at once; later ones
    /// within the interval are batched into one trailing flush.
    private func bufferStreamText(_ delta: String, messageId: String, generation: Int) {
        if pendingStreamMessageId != messageId {
            flushStreamText()
            pendingStreamMessageId = messageId
            streamFlushThrottle.reset()
        }
        pendingStreamText.append(delta)
        guard let delay = streamFlushThrottle.delayBeforeFlush(now: .now) else {
            flushStreamText()
            return
        }
        guard streamFlushTask == nil else { return }
        streamFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.streamFlushTask = nil
            guard generation == self.interactionGeneration else { return }
            self.flushStreamText()
        }
    }

    private func flushStreamText() {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        guard let messageId = pendingStreamMessageId, !pendingStreamText.isEmpty else { return }
        let text = pendingStreamText
        pendingStreamText = ""
        streamFlushThrottle.didFlush(at: .now)
        updateStreamingMessage(id: messageId) { msg in
            msg.text.append(text)
        }
    }

    /// The messages the text belonged to are being replaced.
    private func discardStreamText() {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        pendingStreamText = ""
        pendingStreamMessageId = nil
        streamFlushThrottle.reset()
    }

    private func updateStreamingMessage(id: String, _ mutate: (inout AssistantMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[index])
    }

    private func applyFinal(_ data: AssistantStreamFinalData, optimisticAssistantId: String) {
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
        client.persistThreadId(threadId)
    }

    private func stampSession() {
        persistSession()
    }
}

/// Timing for coalesced stream text: at most one UI update per `interval`.
struct AssistantStreamFlushThrottle {
    /// ~30 updates a second: smooth to the eye, a fraction of a per-token render.
    static let interval: Duration = .milliseconds(33)

    private var lastFlush: ContinuousClock.Instant?

    /// `nil` → flush now; otherwise wait this long for the trailing flush.
    func delayBeforeFlush(now: ContinuousClock.Instant) -> Duration? {
        guard let lastFlush else { return nil }
        let elapsed = now - lastFlush
        guard elapsed < Self.interval else { return nil }
        return Self.interval - elapsed
    }

    mutating func didFlush(at instant: ContinuousClock.Instant) {
        lastFlush = instant
    }

    mutating func reset() {
        lastFlush = nil
    }
}
