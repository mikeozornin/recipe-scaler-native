import Foundation

/// Formats a userId for display in the UI.
/// Format: first 3 chars + "·" (middle dot) + last 3 chars.
/// Matches the web implementation.
///
/// Example: "550e8400-e29b-41d4-a716-446655440000" -> "550·000"
enum UserIdFormatter {
    static func format(_ userId: String) -> String {
        guard userId.count >= 6 else { return userId }
        let start = userId.prefix(3)
        let end = userId.suffix(3)
        return "\(start)·\(end)"
    }

    /// Redacted form for logs. Format: "<user:cfcd83>" (first 6 chars).
    /// Use this everywhere userId would otherwise be written to a log.
    static func redact(_ userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return "<user:nil>" }
        return "<user:\(String(userId.prefix(6)))>"
    }

    /// Redact the userId prefix in a docKey/collectionKey/shoppingKey string.
    /// "cfcd839f-...:recipe:abc-123" -> "<user:cfcd83>:recipe:abc-123"
    static func redactDocKey(_ docKey: String) -> String {
        guard let colonIndex = docKey.firstIndex(of: ":") else { return "<unknown>" }
        let userIdPart = String(docKey[..<colonIndex])
        let rest = String(docKey[colonIndex...])
        return "\(redact(userIdPart))\(rest)"
    }
}
