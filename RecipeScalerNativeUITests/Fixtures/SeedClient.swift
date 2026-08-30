import Foundation

/// REST-driven seeding for E2E tests.
///
/// Web parity: `tests/e2e/fixtures/recipe-api.ts`, `timer-api.ts`,
/// `shopping-list add_to_shopping_list`. Uses the same public API as the SPA
/// so seeded data appears in the UI after the next collection sync.
///
/// Auth is injected via `init(user:)` (no singleton dependency) — see review
/// finding Critical #2.
final class SeedClient {
    private let base = E2EConfig.apiBaseURL
    private let user: DebugUser
    private let session: URLSession

    init(user: DebugUser) {
        self.user = user
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = E2EConfig.requestTimeout
        session = URLSession(configuration: config)
    }

    // MARK: - Recipes

    struct CreatedRecipe {
        let id: String
        let name: String
    }

    /// Create an empty recipe via `POST /api/recipes`, optionally followed by
    /// `POST /api/recipes/:id/ingredients/bulk` if `ingredients` is non-empty.
    func createRecipe(
        name: String,
        ingredients: [SeedIngredient] = []
    ) async throws -> CreatedRecipe {
        let url = base.appendingPathComponent("/api/recipes")
        let body = try JSONEncoder().encode(["name": name])
        let (data, resp) = try await post(url: url, body: body)
        try ensureOK(resp, url, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let success = json?["success"] as? Bool, success,
            let dataDict = json?["data"] as? [String: Any],
            let recipe = dataDict["recipe"] as? [String: Any],
            let id = recipe["id"] as? String
        else {
            throw E2EError.unexpectedStatus("POST /api/recipes malformed body", 0)
        }

        let resolvedName = (recipe["name"] as? String) ?? name

        if !ingredients.isEmpty {
            try await addIngredients(recipeId: id, ingredients: ingredients)
        }
        return CreatedRecipe(id: id, name: resolvedName)
    }

    /// Bulk-add ingredients to an existing recipe (web parity).
    func addIngredients(recipeId: String, ingredients: [SeedIngredient]) async throws {
        validateId(recipeId, kind: "recipe")
        let url = base.appendingPathComponent("/api/recipes/\(recipeId)/ingredients/bulk")
        let payload: [[String: Any]] = ingredients.enumerated().map { idx, ing in
            var entry: [String: Any] = [
                "name": ing.name,
                "unit": ing.unit,
                "order": idx,
            ]
            // Explicit Any-typed value avoids "expression implicitly coerced from
            // 'Any?' to 'Any'" warning.
            let amountValue: Any = ing.originalAmount ?? NSNull()
            entry["original_amount"] = amountValue
            return entry
        }
        let body = try JSONSerialization.data(
            withJSONObject: ["ingredients": payload]
        )
        let (data, resp) = try await post(url: url, body: body)
        try ensureOK(resp, url, data: data)
    }

    // MARK: - Shopping list

    /// Add free-text items to the shopping list.
    func addShoppingItems(_ labels: [String]) async throws {
        let url = base.appendingPathComponent("/api/shopping-list/items")
        let body = try JSONEncoder().encode(["items": labels])
        let (data, resp) = try await post(url: url, body: body)
        try ensureOK(resp, url, data: data)
    }

    /// Add all ingredients from a recipe (scaled) to the shopping list.
    func addRecipeToShoppingList(recipeId: String, targetServings: Int? = nil) async throws {
        validateId(recipeId, kind: "recipe")
        var url = base.appendingPathComponent("/api/shopping-list/from-recipe/\(recipeId)")
        if let servings = targetServings {
            url.append(queryItems: [URLQueryItem(name: "servings", value: String(servings))])
        }
        let (data, resp) = try await post(url: url, body: Data())
        try ensureOK(resp, url, data: data)
    }

    // MARK: - Collections

    struct CreatedCollection {
        let id: String
        let name: String
    }

    /// Create a new collection folder.
    func createCollection(name: String) async throws -> CreatedCollection {
        let url = base.appendingPathComponent("/api/collections")
        let body = try JSONEncoder().encode(["name": name])
        let (data, resp) = try await post(url: url, body: body)
        try ensureOK(resp, url, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let success = json?["success"] as? Bool, success,
            let id = json?["collection_id"] as? String
        else {
            throw E2EError.unexpectedStatus("POST /api/collections malformed body", 0)
        }
        return CreatedCollection(id: id, name: name)
    }

    // MARK: - Timers

    /// Start a custom timer via the v1 sync wire (web parity: `seedRunningTimer`).
    func startTimer(name: String, durationSec: Int) async throws -> String {
        let timerId = "e2e_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6))"
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let endTime = now + durationSec * 1000

        let payload: [String: Any] = [
            "deviceId": "e2e-seed",
            "events": [
                [
                    "type": "timer_created",
                    "timerId": timerId,
                    "timestamp": now,
                    "data": [
                        "name": name,
                        "duration": durationSec,
                        "isRunning": true,
                        "endTime": endTime,
                    ] as [String: Any],
                ],
                [
                    "type": "timer_started",
                    "timerId": timerId,
                    "timestamp": now,
                    "data": ["startedAt": now, "endTime": endTime] as [String: Any],
                ],
            ],
        ]
        let url = base.appendingPathComponent("/api/v1/timers/sync")
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await post(url: url, body: body)
        try ensureOK(resp, url, data: data)
        return timerId
    }

    // MARK: - Follow / Feed (072)

    /// `POST /api/v1/users/:username/follow` — idempotent subscribe.
    func follow(username: String) async throws {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let url = base.appendingPathComponent("/api/v1/users/\(encoded)/follow")
        let (data, resp) = try await post(url: url, body: Data())
        try ensureOK(resp, url, data: data)
    }

    /// `GET /api/v1/feed/badge` → `has_new`.
    func fetchFeedBadgeHasNew() async throws -> Bool {
        let url = base.appendingPathComponent("/api/v1/feed/badge")
        let (data, resp) = try await get(url: url)
        try ensureOK(resp, url, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let success = json?["success"] as? Bool, success,
            let dataDict = json?["data"] as? [String: Any],
            let hasNew = dataDict["has_new"] as? Bool
        else {
            throw E2EError.unexpectedStatus("GET /api/v1/feed/badge malformed body", 0)
        }
        return hasNew
    }

    /// Usernames from the Discover home payload (`GET /api/discover/collections`).
    func discoveryProfileUsernames() async throws -> [String] {
        let url = base.appendingPathComponent("/api/discover/collections")
        let (data, resp) = try await get(url: url)
        try ensureOK(resp, url, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let success = json?["success"] as? Bool, success,
            let dataDict = json?["data"] as? [String: Any],
            let profiles = dataDict["profiles"] as? [[String: Any]]
        else {
            throw E2EError.unexpectedStatus("GET /api/discover/collections malformed body", 0)
        }
        return profiles.compactMap { $0["username"] as? String }.filter { !$0.isEmpty }
    }

    // MARK: - HTTP primitives

    /// Crash loudly if `id` is not a UUID-shaped string before interpolating
    /// into a URL path. `appendingPathComponent` does not percent-encode, so a
    /// value like `../../v1/timers` would silently mutate the request target
    /// (path traversal). Today the only callers are trusted UUIDs from our
    /// own API responses, but this guard keeps the contract explicit. See
    /// review finding High business #9.
    private func validateId(_ id: String, kind: String) {
        // Standard UUID (8-4-4-4-12 hex, 36 chars total with hyphens).
        let pattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        guard id.range(of: pattern, options: .regularExpression) != nil else {
            preconditionFailure(
                "Invalid \(kind) id: '\(id)' — expected UUID shape. Refusing to interpolate into URL."
            )
        }
    }

    private func post(url: URL, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in try user.authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        return (data, try unwrapHTTP(resp))
    }

    private func get(url: URL) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in try user.authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        return (data, try unwrapHTTP(resp))
    }

    private func unwrapHTTP(_ resp: URLResponse) throws -> HTTPURLResponse {
        guard let http = resp as? HTTPURLResponse else { throw E2EError.nonHTTPResponse }
        return http
    }

    private func ensureOK(_ resp: HTTPURLResponse, _ url: URL, data: Data? = nil) throws {
        guard (200..<300).contains(resp.statusCode) else {
            var msg = "POST \(url.path) → \(resp.statusCode)"
            if let data, let body = String(data: data, encoding: .utf8), !body.isEmpty {
                msg += ": \(body.prefix(300))"
            }
            throw E2EError.unexpectedStatus(msg, resp.statusCode)
        }
    }
}
