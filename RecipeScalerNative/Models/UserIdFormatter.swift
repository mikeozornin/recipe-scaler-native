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
}
