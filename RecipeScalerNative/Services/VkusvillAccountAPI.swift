//
//  VkusvillAccountAPI.swift
//  RecipeScalerNative
//
//  Spec 083: вход в аккаунт Вкусвилла. OAuth ведёт сервер (confidential
//  client + PKCE); приложение только открывает authorize URL и пересылает
//  `code`/`state` из callback обратно на сервер.
//

import Foundation
import RecipeScalerCore

/// `GET /api/v1/vkusvill/connection` (spec 083).
struct VkusvillConnectionDTO: Decodable, Equatable {
    enum Status: String, Decodable {
        case active
        case reconnectRequired = "reconnect_required"
    }

    /// На сервере настроены OAuth-ключи; `false` — строки входа скрыты.
    let available: Bool
    let connected: Bool
    let status: Status?
    let scopes: [String]
    let connectedAt: String?
    /// Последний `meta.personalized` из поиска с токеном; `false` — во Вкусвилле не выбран адрес.
    let personalized: Bool?

    enum CodingKeys: String, CodingKey {
        case available, connected, status, scopes, personalized
        case connectedAt = "connected_at"
    }

    var connectedDate: Date? {
        connectedAt.flatMap(DiscoverDateParser.parse)
    }

    /// Состояние после выхода: так же выглядит ответ `DELETE /connection`.
    var signedOut: VkusvillConnectionDTO {
        VkusvillConnectionDTO(
            available: available,
            connected: false,
            status: nil,
            scopes: [],
            connectedAt: nil,
            personalized: nil
        )
    }
}

/// Коды ошибок `/api/v1/vkusvill/*`, которые различает UI. Сервер кладёт
/// машинный код в `code`, а `error` — английский текст для логов.
enum VkusvillAccountError: Error, Equatable {
    /// `invalid_state` / `invalid_grant`: вход истёк или код уже использован.
    case signInExpired
    /// `vkusvill_unavailable`: Вкусвилл не ответил на обмен кода.
    case vkusvillUnavailable
    /// `vkusvill_not_configured`: на сервере нет OAuth-ключей.
    case notConfigured
    /// Остальные ответы сервера.
    case server(statusCode: Int)
}

/// Ответ Вкусвилла, пересланный сервером в `<scheme>://vkusvill-oauth?…`.
enum VkusvillOAuthCallback: Equatable {
    case code(code: String, state: String)
    /// `error=access_denied`: пользователь отказался на странице Вкусвилла.
    case denied
    case failed

    static let host = "vkusvill-oauth"

    static func parse(_ url: URL) -> VkusvillOAuthCallback {
        guard url.host == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return .failed
        }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        if let error = value("error") {
            return error == "access_denied" ? .denied : .failed
        }
        guard let code = value("code"), let state = value("state") else {
            return .failed
        }
        return .code(code: code, state: state)
    }
}

enum VkusvillAccountAPI {
    static func fetchConnection() async throws -> VkusvillConnectionDTO {
        try await request(path: "/api/v1/vkusvill/connection")
    }

    /// Authorize URL Вкусвилла; сервер вернёт пользователя в `DeepLinkURL.baseScheme`.
    static func startSignIn() async throws -> URL {
        struct Body: Encodable {
            let client = "native"
            let native_scheme = DeepLinkURL.baseScheme
        }
        struct StartDTO: Decodable {
            let authorize_url: String
        }
        let dto: StartDTO = try await request(path: "/api/v1/vkusvill/oauth/start", method: "POST", body: Body())
        guard let url = URL(string: dto.authorize_url) else {
            throw APIError.invalidResponse
        }
        return url
    }

    static func completeSignIn(code: String, state: String) async throws -> VkusvillConnectionDTO {
        struct Body: Encodable {
            let code: String
            let state: String
        }
        return try await request(
            path: "/api/v1/vkusvill/oauth/complete",
            method: "POST",
            body: Body(code: code, state: state)
        )
    }

    static func signOut() async throws -> VkusvillConnectionDTO {
        try await request(path: "/api/v1/vkusvill/connection", method: "DELETE")
    }

    // MARK: - Private

    private struct Envelope<T: Decodable>: Decodable {
        let success: Bool
        let data: T?
        let code: String?
    }

    /// `APIClient.requestJSON` читает только `error`, поэтому разбираем `code` сами.
    private static func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> T {
        let bodyData = try body.map { try JSONEncoder().encode($0) }
        let request = try APIClient.shared.buildRequest(path: path, method: method, body: bodyData)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data)
        guard (200...299).contains(http.statusCode) else {
            APIClient.shared.notifyUnauthorizedIfNeeded(statusCode: http.statusCode)
            throw error(code: envelope?.code, statusCode: http.statusCode)
        }
        guard let envelope, envelope.success, let value = envelope.data else {
            throw APIError.invalidResponse
        }
        return value
    }

    static func error(code: String?, statusCode: Int) -> Error {
        switch code {
        case "invalid_state", "invalid_grant":
            return VkusvillAccountError.signInExpired
        case "vkusvill_unavailable":
            return VkusvillAccountError.vkusvillUnavailable
        case "vkusvill_not_configured":
            return VkusvillAccountError.notConfigured
        default:
            return statusCode == 401 ? APIError.unauthorized : VkusvillAccountError.server(statusCode: statusCode)
        }
    }
}
