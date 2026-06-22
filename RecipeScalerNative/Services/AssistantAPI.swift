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
    case error(ServerErrorCode)
}

// MARK: - API

enum AssistantAPI {
    /// `POST /api/assistant/threads` body `{title?}` → thread.
    static func createThread(title: String? = nil, language: String? = nil) async throws -> AssistantThreadDTO {
        struct Body: Encodable { let title: String? }
        let response: APIResponse<AssistantThreadDTO> = try await APIClient.shared.requestJSON(
            path: "/api/assistant/threads",
            method: "POST",
            body: Body(title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty),
            extraHeaders: languageHeaders(language)
        )
        return try APIClient.unwrapResponse(response, fallback: .assistantThreadsCreateFailed)
    }

    /// `GET /api/assistant/threads` → threads ordered by `lastMessageAt DESC`.
    static func listThreads(language: String? = nil) async throws -> [AssistantThreadDTO] {
        let response: APIResponse<[AssistantThreadDTO]> = try await APIClient.shared.requestJSON(
            path: "/api/assistant/threads",
            method: "GET",
            extraHeaders: languageHeaders(language)
        )
        return try APIClient.unwrapResponse(response, fallback: .assistantThreadsListFailed)
    }

    /// `GET /api/assistant/threads/:id/messages` → messages oldest-first.
    static func getMessages(threadId: String, language: String? = nil) async throws -> [AssistantMessageDTO] {
        let response: APIResponse<[AssistantMessageDTO]> = try await APIClient.shared.requestJSON(
            path: "/api/assistant/threads/\(threadId)/messages",
            method: "GET",
            extraHeaders: languageHeaders(language)
        )
        return try APIClient.unwrapResponse(response, fallback: .assistantMessagesLoadFailed)
    }

    /// `DELETE /api/assistant/threads/:id`.
    static func deleteThread(threadId: String, language: String? = nil) async throws {
        struct DeletedPayload: Decodable { let deletedThreadId: String? }
        let response: APIResponse<DeletedPayload> = try await APIClient.shared.requestJSON(
            path: "/api/assistant/threads/\(threadId)",
            method: "DELETE",
            extraHeaders: languageHeaders(language)
        )
        guard response.success else {
            let code = ServerErrorCode.from(
                serverValue: response.error,
                fallback: .assistantThreadsDeleteFailed
            )
            throw APIError.serverError(code: code)
        }
    }

    /// `POST /api/assistant/threads/:id/respond-stream` — NDJSON stream.
    ///
    /// `message` must be 1..8000 chars (server trims + validates). `attachedRecipeIds`
    /// is up to 10 UUIDv4 strings (server rejects on more / non-UUID).
    static func stream(
        threadId: String,
        message: String,
        attachedRecipeIds: [String] = [],
        language: String? = nil
    ) async throws -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw APIError.serverError(code: .assistantMessageEmpty)
        }
        guard trimmedMessage.count <= 8000 else {
            throw APIError.serverError(code: .assistantMessageTooLong)
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
            headers: languageHeaders(language)
        )
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

        return AsyncThrowingStream { continuation in
            let task = Task {
                defer { continuation.finish() }
                do {
                    let (bytes, response) = try await AppURLSession.shared.bytes(for: request)
                    let http = response as? HTTPURLResponse
                    let status = http?.statusCode ?? -1
                    if !(200...299).contains(status) {
                        var serverCode: ServerErrorCode? = nil
                        for try await line in bytes.lines {
                            if let evt = parseLine(line),
                               case .error(let code) = evt {
                                serverCode = code
                                break
                            }
                        }
                        if let code = serverCode {
                            throw APIError.serverError(code: code)
                        }
                        throw APIError.httpError(statusCode: status)
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { return }
                        if let event = parseLine(line) {
                            continuation.yield(event)
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
            let code: ServerErrorCode
            switch payload.error {
            case "audio_too_long":
                code = .assistantVoiceErrorTooLong
            case "transcription_not_configured", "transcription_failed":
                code = .assistantVoiceErrorTranscription
            default:
                code = ServerErrorCode.from(
                    serverValue: payload.error,
                    fallback: .assistantVoiceErrorTranscription
                )
            }
            throw APIError.serverError(code: code)
        }
        return text
    }

    // MARK: - Helpers

    private static func languageHeaders(_ language: String?) -> [String: String] {
        guard let language else { return [:] }
        return ["X-App-Language": language]
    }

    /// Parses one NDJSON line into a stream event. Ignores malformed / unknown payloads.
    private static func parseLine(_ line: String) -> AssistantStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
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
            let final: AssistantStreamFinalData?
            if let dataDict = json["data"] as? [String: Any],
               let innerData = try? JSONSerialization.data(withJSONObject: dataDict) {
                final = try? JSONDecoder().decode(AssistantStreamFinalData.self, from: innerData)
            } else {
                final = try? JSONDecoder().decode(AssistantStreamFinalData.self, from: data)
            }
            guard let final else {
                return nil
            }
            return .final(final)
        case "error":
            let raw = (json["message"] as? String) ?? ServerErrorCode.assistantErrorUnavailable.rawValue
            let code = ServerErrorCode.from(
                serverValue: raw,
                fallback: .assistantErrorUnavailable
            )
            return .error(code)
        default:
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
