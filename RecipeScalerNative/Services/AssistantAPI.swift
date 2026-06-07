//
//  AssistantAPI.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

struct AssistantThreadDTO: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
}

struct AssistantThreadsResponse: Decodable, Sendable {
    let threads: [AssistantThreadDTO]
}

struct AssistantStreamFinal: Decodable, Sendable {
    struct Message: Decodable, Sendable {
        let content: String?
    }
    let message: Message?
}

@MainActor
enum AssistantAPI {
    static func createThread(title: String = "Chat") async throws -> AssistantThreadDTO {
        struct Body: Encodable { let title: String }
        let response: APIResponse<AssistantThreadDTO> = try await APIClient.shared.requestJSON(
            path: "/api/assistant/threads",
            method: "POST",
            body: Body(title: title)
        )
        guard response.success, let data = response.data else {
            throw APIError.serverError(message: response.error ?? "Thread create failed")
        }
        return data
    }

    /// Minimal streaming: reads NDJSON lines until `final` event.
    static func streamResponse(threadId: String, message: String) async throws -> String {
        struct Body: Encodable { let message: String }
        let body = try JSONEncoder().encode(Body(message: message))
        var request = try APIClient.shared.buildRequest(
            path: "/api/assistant/threads/\(threadId)/respond-stream",
            method: "POST",
            body: body
        )
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        var accumulated = ""
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            if type == "text-delta", let delta = json["delta"] as? String {
                accumulated += delta
            }
            if type == "final" {
                if let finalData = try? JSONSerialization.data(withJSONObject: json),
                   let final = try? JSONDecoder().decode(AssistantStreamFinal.self, from: finalData),
                   let content = final.message?.content, !content.isEmpty {
                    return content
                }
                return accumulated
            }
        }
        return accumulated
    }
}