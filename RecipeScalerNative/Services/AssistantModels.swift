//
//  AssistantModels.swift
//  RecipeScalerNative
//
//  Server contract mirrors `recipe-scaler-web/recipe-scaler/src/services/assistant-api.ts` (lines 3–119).
//  Keep field names and shapes in sync with the web client.
//

import Foundation

// MARK: - Widgets

struct AssistantWidgetOption: Decodable, Identifiable, Hashable, Sendable {
    let label: String
    let value: String
    var id: String { value }
}

enum AssistantInteractiveWidget: Decodable, Sendable, Identifiable {
    case quickReplies(options: [AssistantWidgetOption])
    case select(options: [AssistantWidgetOption])
    case numberInput(NumberInput)

    enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "quick_replies":
            let container = try decoder.singleValueContainer()
            self = .quickReplies(options: try container.decode(Root.self).options)
        case "select":
            let container = try decoder.singleValueContainer()
            self = .select(options: try container.decode(Root.self).options)
        case "number_input":
            let container = try decoder.singleValueContainer()
            self = .numberInput(try container.decode(NumberInput.self))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: c,
                debugDescription: "Unknown assistant widget type: \(type)"
            )
        }
    }

    /// Stable id so SwiftUI `ForEach` / `.id()` can dedupe; type discrimination is enough at the call site.
    var id: String {
        switch self {
        case .quickReplies: return "quick_replies"
        case .select: return "select"
        case .numberInput: return "number_input"
        }
    }

    private struct Root: Decodable {
        let options: [AssistantWidgetOption]
    }

    struct NumberInput: Decodable, Sendable {
        let min: Double?
        let max: Double?
        let step: Double?
        let unit: String?
        let defaultValue: Double?
    }
}

// MARK: - Attachments

struct AssistantRecipeAttachment: Decodable, Sendable, Identifiable, Hashable {
    let recipeId: String
    let recipeName: String?
    let recipeColor: String?

    var id: String { recipeId }
}

// MARK: - Pending action (server-synthesized confirmation gate for destructive tools)

enum AssistantPendingActionStatus: String, Decodable, Sendable {
    case pending, confirmed, cancelled, consumed, expired
}

/// `toolArgs` is a free-form JSON object server-side. We keep it opaque (Data) and let the
/// caller decide whether to decode further.
struct AssistantPendingAction: Decodable, Sendable {
    let id: String
    let status: AssistantPendingActionStatus
    let toolName: String
    let targetLabel: String?
    let message: String?
    let confirmLabel: String?
    let cancelLabel: String?
    let confirmValue: String
    let cancelValue: String
    let createdAt: String
    let expiresAt: String
}

/// Mirrors web `AssistantActionResolution` (`recipe-scaler/src/services/assistant-api.ts`).
/// Server attaches it to the user message that resolves a pending action so the client can
/// render a friendly label (e.g. "Удалить") instead of the raw `confirmValue`/`cancelValue`.
struct AssistantActionResolution: Decodable, Sendable {
    let pendingActionId: String
    let disposition: String
    let source: String
    let createdAt: String
}

// MARK: - Follow-up suggestions

struct AssistantFollowUpSuggestion: Decodable, Identifiable, Hashable, Sendable {
    let label: String
    let value: String
    var id: String { value }
}

// MARK: - UI message model

/// Local in-memory message consumed by `AssistantSheet` and `AssistantMessageFooter`.
/// `id` is stable within a single sheet session (UUID for optimistic rows, server id
/// once `final` lands). `text` is mutated in place during streaming.
struct AssistantMessage: Identifiable {
    var id: String
    var role: String
    var text: String
    var isStreaming: Bool
    var metadata: AssistantMessageMetadata?
    var createdAt: Date

    static func optimisticToolStatus(toolName: String) -> AssistantMessage {
        AssistantMessage(
            id: "optimistic-tool-status-\(UUID().uuidString)",
            role: "assistant",
            text: "",
            isStreaming: false,
            metadata: .toolStatusOnly(toolName: toolName),
            createdAt: Date()
        )
    }

    var isToolStatusRow: Bool {
        metadata?.toolStatus != nil
    }

    var isProcessingPlaceholder: Bool {
        role == "assistant"
            && isStreaming
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isToolStatusRow
    }

    static func isOptimisticID(_ id: String) -> Bool {
        id.hasPrefix("optimistic-")
    }
}

enum AssistantISO8601 {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        withFractionalSeconds.date(from: string) ?? withoutFractionalSeconds.date(from: string)
    }
}

// MARK: - Tool status (client-only UI metadata; web parity spec 073)

struct AssistantToolStatus: Sendable, Hashable {
    let toolName: String
}

// MARK: - Message metadata (subset of the web `AssistantMessageMetadata` that iOS consumes)

struct AssistantMessageMetadata: Decodable, Sendable {
    let attachments: [AssistantRecipeAttachment]?
    let interactiveWidget: AssistantInteractiveWidget?
    let pendingAction: AssistantPendingAction?
    let actionResolution: AssistantActionResolution?
    let followUpSuggestions: [AssistantFollowUpSuggestion]?
    /// Client-only; never sent by server. Mirrors web `metadata.toolStatus`.
    var toolStatus: AssistantToolStatus?

    enum CodingKeys: String, CodingKey {
        case attachments
        case interactiveWidget
        case pendingAction
        case actionResolution
        case followUpSuggestions
    }

    init(
        attachments: [AssistantRecipeAttachment]? = nil,
        interactiveWidget: AssistantInteractiveWidget? = nil,
        pendingAction: AssistantPendingAction? = nil,
        actionResolution: AssistantActionResolution? = nil,
        followUpSuggestions: [AssistantFollowUpSuggestion]? = nil,
        toolStatus: AssistantToolStatus? = nil
    ) {
        self.attachments = attachments
        self.interactiveWidget = interactiveWidget
        self.pendingAction = pendingAction
        self.actionResolution = actionResolution
        self.followUpSuggestions = followUpSuggestions
        self.toolStatus = toolStatus
    }

    static func toolStatusOnly(toolName: String) -> AssistantMessageMetadata {
        AssistantMessageMetadata(toolStatus: AssistantToolStatus(toolName: toolName))
    }
}

// MARK: - Stream final payload

/// Minimal shape of `final.data.assistantMessage` used by P1 streaming (content + optional metadata).
struct AssistantStreamFinalMessage: Decodable, Sendable {
    let id: String?
    let content: String?
    let metadata: AssistantMessageMetadata?
    let createdAt: String?
}

struct AssistantStreamFinalData: Decodable, Sendable {
    struct Thread: Decodable, Sendable {
        let id: String
        let title: String?
    }

    struct MessageRef: Decodable, Sendable {
        let id: String?
        let content: String?
        let metadata: AssistantMessageMetadata?
        let createdAt: String?
    }

    let thread: Thread?
    let userMessage: MessageRef?
    let assistantMessage: AssistantStreamFinalMessage?
}

// MARK: - Recipe context (assistant quick-attach)

/// Tracks the recipe detail screen currently visible — used for assistant context quick-attach.
@MainActor
@Observable
final class AssistantRecipeContext {
    /// Shim: returns `AppContainer.shared.assistantRecipeContext` when the
    /// container is constructed, otherwise a stand-alone instance.
    static var shared: AssistantRecipeContext {
        if let container = AppContainer.shared {
            return container.assistantRecipeContext
        }
        return Standalone
    }

    private static let Standalone = AssistantRecipeContext()

    private(set) var visibleRecipeId: String?
    var isAssistantSheetOpen = false

    init() {}

    func setVisibleRecipeId(_ recipeId: String) {
        visibleRecipeId = recipeId
    }

    func clearVisibleRecipeId(_ recipeId: String) {
        if visibleRecipeId == recipeId {
            visibleRecipeId = nil
        }
    }
}
