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
    let id: String
    var role: String
    var text: String
    var isStreaming: Bool
    var metadata: AssistantMessageMetadata?
}

// MARK: - Message metadata (subset of the web `AssistantMessageMetadata` that iOS consumes)

struct AssistantMessageMetadata: Decodable, Sendable {
    let attachments: [AssistantRecipeAttachment]?
    let interactiveWidget: AssistantInteractiveWidget?
    let pendingAction: AssistantPendingAction?
    let followUpSuggestions: [AssistantFollowUpSuggestion]?
}

// MARK: - Stream final payload

/// Minimal shape of `final.data.assistantMessage` used by P1 streaming (content + optional metadata).
struct AssistantStreamFinalMessage: Decodable, Sendable {
    let content: String?
    let metadata: AssistantMessageMetadata?
}

struct AssistantStreamFinalData: Decodable, Sendable {
    struct Thread: Decodable, Sendable {
        let id: String
        let title: String?
    }

    struct MessageRef: Decodable, Sendable {
        let id: String?
        let content: String?
    }

    let thread: Thread?
    let userMessage: MessageRef?
    let assistantMessage: AssistantStreamFinalMessage?
}
