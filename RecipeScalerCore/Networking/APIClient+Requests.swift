//
//  APIClient+Requests.swift
//  RecipeScalerCore
//

import Foundation

extension APIClient {
    public func requestJSON<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> APIResponse<T> {
        var bodyData: Data?
        if let body {
            bodyData = try JSONEncoder().encode(AnyEncodable(body))
        }
        let request = try buildRequest(path: path, method: method, body: bodyData, headers: extraHeaders)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            notifyUnauthorizedIfNeeded(statusCode: http.statusCode)
            throw Self.mapHTTPFailure(statusCode: http.statusCode, data: data)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(APIResponse<T>.self, from: data)
    }

    public func uploadMultipart(
        path: String,
        fieldName: String,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> Data {
        try await uploadMultipart(
            path: path,
            fieldName: fieldName,
            files: [(fileName: fileName, data: fileData, mimeType: mimeType)]
        )
    }

    /// Upload multiple files under the same form field name (e.g. `images[]`).
    /// Mirrors the web `formData.append('images', file)` loop in `recipe-import-api.ts`.
    public func uploadMultipart(
        path: String,
        fieldName: String,
        files: [(fileName: String, data: Data, mimeType: String)]
    ) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try buildRequest(
            path: path,
            method: "POST",
            body: nil,
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
        )
        var body = Data()
        let crlf = "\r\n"
        let boundaryLine = "--\(boundary)\r\n".data(using: .utf8)!
        for file in files {
            body.append(boundaryLine)
            body.append(
                "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(file.fileName)\"\r\n"
                    .data(using: .utf8)!
            )
            body.append("Content-Type: \(file.mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(file.data)
            body.append(crlf.data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            notifyUnauthorizedIfNeeded(statusCode: code)
            throw Self.mapHTTPFailure(statusCode: code, data: data)
        }
        return data
    }

    /// Generic decodable request — returns the decoded type directly (no `APIResponse` wrapper).
    public func performDecodable<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        let request = try buildRequest(path: path, method: method, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            notifyUnauthorizedIfNeeded(statusCode: code)
            throw APIError.httpError(statusCode: code)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Unwrap an `APIResponse<T>` into `T`, throwing `APIError.serverError` if the
    /// response is not successful or has no data. `fallback` is used when
    /// `response.error` is nil/empty or does not match a known `ServerErrorCode`.
    public static func unwrapResponse<T>(_ response: APIResponse<T>, fallback: ServerErrorCode) throws -> T {
        guard response.success, let data = response.data else {
            let code = ServerErrorCode.from(serverValue: response.error, fallback: fallback)
            throw APIError.serverError(code: code)
        }
        return data
    }

    private static func parseAPIFailureBody(_ data: Data) -> ServerErrorCode? {
        guard let message = parseAPIFailureMessage(data) else { return nil }
        return ServerErrorCode(rawValue: message)
    }

    private static func parseAPIFailureMessage(_ data: Data) -> String? {
        struct Empty: Decodable {}
        guard let json = try? JSONDecoder().decode(APIResponse<Empty>.self, from: data),
              let error = json.error, !error.isEmpty else {
            return nil
        }
        return error
    }

    /// Prefer typed / phrase-mappable server messages over bare HTTP status keys.
    private static func mapHTTPFailure(statusCode: Int, data: Data) -> APIError {
        guard let message = parseAPIFailureMessage(data) else {
            return .httpError(statusCode: statusCode)
        }
        if let code = ServerErrorCode(rawValue: message) {
            return .serverError(code: code)
        }
        return .upstreamMessage(message)
    }
}

public struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    public init<T: Encodable>(_ value: T) {
        encode = value.encode
    }
    public func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

