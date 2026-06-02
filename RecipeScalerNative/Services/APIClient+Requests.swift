//
//  APIClient+Requests.swift
//  RecipeScalerNative
//

import Foundation

extension APIClient {
    func requestJSON<T: Decodable>(
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
            throw APIError.httpError(statusCode: http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(APIResponse<T>.self, from: data)
    }

    func uploadMultipart(
        path: String,
        fieldName: String,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try buildRequest(
            path: path,
            method: "POST",
            body: nil,
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
        )
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.httpError(statusCode: code)
        }
        return data
    }
}

private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        encode = value.encode
    }
    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}