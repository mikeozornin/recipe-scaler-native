//
//  AssistantAPI.swift
//  RecipeScalerNative
//
//  Server contract: `recipe-scaler-web/recipe-scaler/src/services/assistant-api.ts`
//  Stream events + metadata: `server/src/routes/assistant.ts` + `server/src/types/assistant.ts`.
//

import Foundation
import RecipeScalerCore

// MARK: - Threads (REST)

struct AssistantThreadDTO: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let title: String?
    let createdAt: String
    let updatedAt: String
    let lastMessageAt: String?
}

struct AssistantMessageDTO: Decodable, Identifiable, Sendable {
    let id: String
    let threadId: String
    let role: String
    let content: String
    let metadata: AssistantMessageMetadata?
    let createdAt: String
    let updatedAt: String
}

// MARK: - Stream event types

enum AssistantStreamEvent: Sendable {
    case textStart
    case textDelta(String)
    case toolStart(toolName: String, toolCallId: String)
    case final(AssistantStreamFinalData)
    case error(String)
}

// MARK: - API

@MainActor
enum AssistantAPI {
    /// `POST /api/assistant/threads` body `{title?}` → thread.
    static func createThread(title: String? = nil) async throws -> AssistantThreadDTO {
        struct Body: Encodable { let title: String? }
        let response: APIResponse<AssistantThreadDTO> = try await APIClient.shared.requestJSON(
            path: "/api/assistant/threads",
            method: "POST",
            body: Body(title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty),
            extraHeaders: languageHeader()
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "assistant.threads.create.failed")
        }
        return data
    }

    /// `GET /api/assistant/threads` → threads ordered by `lastMessageAt DESC`.
    static func listThreads() async throws -> [AssistantThreadDTO] {
        let response: APIResponse<[AssistantThreadDTO]> = try await APIClient.shared.requestJSON(
            path: "/api/assistant/threads",
            method: "GET",
            extraHeaders: languageHeader()
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "assistant.threads.list.failed")
        }
        return data
    }

    /// `GET /api/assistant/threads/:id/messages` → messages oldest-first.
    static func getMessages(threadId: String) async throws -> [AssistantMessageDTO] {
        let response: APIResponse<[AssistantMessageDTO]> = try await APIClient.shared.requestJSON(
            path: "/api/assistant/threads/\(threadId)/messages",
            method: "GET",
            extraHeaders: languageHeader()
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "assistant.messages.load.failed")
        }
        return data
    }

    /// `DELETE /api/assistant/threads/:id`.
    static func deleteThread(threadId: String) async throws {
        struct DeletedPayload: Decodable { let deletedThreadId: String? }
        let response: APIResponse<DeletedPayload> = try await APIClient.shared.requestJSON(
            path: "/api/assistant/threads/\(threadId)",
            method: "DELETE",
            extraHeaders: languageHeader()
        )
        guard response.success else {
            throw APIError.serverError(message: response.error ?? "assistant.threads.delete.failed")
        }
    }

    /// `POST /api/assistant/threads/:id/respond-stream` — NDJSON stream.
    ///
    /// `message` must be 1..8000 chars (server trims + validates). `attachedRecipeIds`
    /// is up to 10 UUIDv4 strings (server rejects on more / non-UUID).
    static func stream(
        threadId: String,
        message: String,
        attachedRecipeIds: [String] = []
    ) async throws -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw APIError.serverError(message: "assistant.message.empty")
        }
        guard trimmedMessage.count <= 8000 else {
            throw APIError.serverError(message: "assistant.message.too-long")
        }
        let limitedAttachments = Array(attachedRecipeIds.prefix(10))

        struct Body: Encodable {
            let message: String
            let attachedRecipeIds: [String]
        }
        let body = try JSONEncoder().encode(
            Body(message: trimmedMessage, attachedRecipeIds: limitedAttachments)
        )
        var request = try APIClient.shared.buildRequest(
            path: "/api/assistant/threads/\(threadId)/respond-stream",
            method: "POST",
            body: body,
            headers: languageHeader()
        )
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

        return AsyncThrowingStream { continuation in
            let task = Task {
                defer { continuation.finish() }
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let http = response as? HTTPURLResponse
                    let status = http?.statusCode ?? -1
                    if !(200...299).contains(status) {
                        // Server may still emit an `error` line in the body even on non-2xx.
                        var serverMessage: String? = nil
                        for try await line in bytes.lines {
                            if let evt = parseLine(line),
                               case .error(let msg) = evt {
                                serverMessage = msg
                                break
                            }
                        }
                        throw APIError.httpError(
                            statusCode: status,
                            message: serverMessage ?? "assistant.stream.http-error"
                        )
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { return }
                        if let event = parseLine(line) {
                            continuation.yield(event)
                            // Termination events don't close the stream from URLSession.bytes,
                            // but we finish the continuation to mirror web client behavior.
                            switch event {
                            case .final, .error:
                                return
                            default:
                                continue
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// `POST /api/assistant/transcribe` (multipart, field `file`) → `{ text }`.
    static func transcribe(audioData: Data, mimeType: String, fileName: String = "voice.m4a") async throws -> String {
        let raw = try await APIClient.shared.uploadMultipart(
            path: "/api/assistant/transcribe",
            fieldName: "file",
            files: [(fileName, audioData, mimeType)]
        )
        struct Payload: Decodable {
            let success: Bool
            let data: Data?
            let error: String?
            struct Data: Decodable { let text: String }
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: raw)
        } catch {
            throw APIError.decodingError(error)
        }
        guard payload.success, let text = payload.data?.text else {
            let messageKey: String
            switch payload.error {
            case "audio_too_long":
                messageKey = "assistant.voice-error.too-long"
            case "transcription_not_configured", "transcription_failed":
                messageKey = "assistant.voice-error.transcription"
            default:
                messageKey = payload.error ?? "assistant.voice-error.transcription"
            }
            throw APIError.serverError(message: messageKey)
        }
        return text
    }

    // MARK: - Helpers

    private static func languageHeader() -> [String: String] {
        ["X-App-Language": AppLanguagePreference.current.rawValue]
    }

    /// Parses one NDJSON line into a stream event. Ignores malformed / unknown payloads.
    private static func parseLine(_ line: String) -> AssistantStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            // #region agent log
            AssistantPendingActionDebugTrace.write(
                hypothesisId: "H4",
                location: "AssistantAPI.parseLine:malformedOrNoType",
                message: "NDJSON line could not be parsed as {type: ...}",
                data: [
                    "raw_head": String(trimmed.prefix(300)),
                    "raw_len": String(trimmed.count)
                ]
            )
            // #endregion
            return nil
        }
        switch type {
        case "text-start":
            return .textStart
        case "text-delta":
            return (json["delta"] as? String).map { .textDelta($0) }
        case "tool-start":
            if let toolName = json["toolName"] as? String,
               let toolCallId = json["toolCallId"] as? String {
                return .toolStart(toolName: toolName, toolCallId: toolCallId)
            }
            return nil
        case "final":
            // #region agent log
            // Capture the raw shape BEFORE attempting typed decoding so we can see exactly what
            // the server sent (vs what AssistantStreamFinalData kept after decoding).
            let dataField = json["data"]
            let dataDict = dataField as? [String: Any]
            let am = dataDict?["assistantMessage"] as? [String: Any]
            let amMeta = am?["metadata"] as? [String: Any]
            AssistantPendingActionDebugTrace.write(
                hypothesisId: "H4",
                location: "AssistantAPI.parseLine:final",
                message: "received 'final' line — raw shape inspection",
                data: [
                    "raw_head": String(trimmed.prefix(500)),
                    "raw_len": String(trimmed.count),
                    "has_data_key": (dataField != nil).description,
                    "data_keys": dataDict?.keys.sorted().joined(separator: ",") ?? "not_a_dict",
                    "data_has_thread": (dataDict?["thread"] != nil).description,
                    "data_has_userMessage": (dataDict?["userMessage"] != nil).description,
                    "data_has_assistantMessage": (dataDict?["assistantMessage"] != nil).description,
                    "data_assistantMessage_keys": am?.keys.sorted().joined(separator: ",") ?? "nil_or_not_dict",
                    "data_assistantMessage_metadata_keys": amMeta?.keys.sorted().joined(separator: ",") ?? "nil_or_not_dict"
                ]
            )
            // #endregion
            // The server emits `{"type":"final","data":{...}}`. We must decode the *inner* `data`
            // object as AssistantStreamFinalData — NOT the whole envelope (which would decode to
            // all-nil optionals silently).
            let final: AssistantStreamFinalData?
            if let dataDict,
               let innerData = try? JSONSerialization.data(withJSONObject: dataDict) {
                final = try? JSONDecoder().decode(AssistantStreamFinalData.self, from: innerData)
            } else {
                // Fallback: try decoding the whole line as-is (legacy behaviour, will yield nil
                // fields if server ever wraps the data again).
                final = try? JSONDecoder().decode(AssistantStreamFinalData.self, from: data)
            }
            guard let final else {
                // #region agent log
                AssistantPendingActionDebugTrace.write(
                    hypothesisId: "H4",
                    location: "AssistantAPI.parseLine:final:decodeFailed",
                    message: "AssistantStreamFinalData decode failed — returning nil event (ignored)",
                    data: ["raw_head": String(trimmed.prefix(500))]
                )
                // #endregion
                return nil
            }
            // #region agent log
            AssistantPendingActionDebugTrace.write(
                hypothesisId: "H4",
                location: "AssistantAPI.parseLine:final:decodeOk",
                message: "AssistantStreamFinalData decoded",
                data: [
                    "has_thread": (final.thread != nil).description,
                    "has_userMessage": (final.userMessage != nil).description,
                    "userMessage_has_metadata": (final.userMessage?.metadata != nil).description,
                    "userMessage_has_actionResolution": (final.userMessage?.metadata?.actionResolution != nil).description,
                    "has_assistantMessage": (final.assistantMessage != nil).description,
                    "assistantMessage_id": final.assistantMessage?.id ?? "nil",
                    "assistantMessage_content_len": String(final.assistantMessage?.content?.count ?? -1),
                    "assistantMessage_has_metadata": (final.assistantMessage?.metadata != nil).description
                ]
            )
            // #endregion
            return .final(final)
        case "error":
            let message = (json["message"] as? String) ?? "assistant.error-unavailable"
            // #region agent log
            AssistantPendingActionDebugTrace.write(
                hypothesisId: "H4",
                location: "AssistantAPI.parseLine:error",
                message: "received 'error' line from server",
                data: ["server_message": message]
            )
            // #endregion
            return .error(message)
        default:
            // #region agent log
            AssistantPendingActionDebugTrace.write(
                hypothesisId: "H4",
                location: "AssistantAPI.parseLine:unknownType",
                message: "unknown event type",
                data: ["type": type, "raw_head": String(trimmed.prefix(200))]
            )
            // #endregion
            return nil
        }
    }
}

// MARK: - APIError helper

extension APIError {
    /// The project's `APIError.httpError` only takes statusCode; this builds a descriptive
    /// variant for stream failures that also have a server-side message.
    static func httpError(statusCode: Int, message: String) -> APIError {
        return .serverError(message: "\(message) [HTTP \(statusCode)]")
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
