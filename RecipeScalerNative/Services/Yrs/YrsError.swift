import Foundation
import YrsC

/// Errors for yrs (CRDT) operations.
///
/// The associated `context` value is preserved for diagnostic logging only —
/// it is never interpolated into `errorDescription`, which always returns a
/// localized user-facing message via `Bundle.currentLocalizedString`.
enum YrsError: Error, LocalizedError {
    case nullPointer(context: String)
    case applyFailed(context: String)
    case transactionError(context: String)

    var errorDescription: String? {
        switch self {
        case .nullPointer:
            return Bundle.currentLocalizedString("yrs.error.technical")
        case .applyFailed:
            return Bundle.currentLocalizedString("yrs.error.apply-failed")
        case .transactionError:
            return Bundle.currentLocalizedString("yrs.error.transaction")
        }
    }

    /// Diagnostic context for logging (never shown to the user).
    var debugContext: String {
        switch self {
        case .nullPointer(let ctx),
             .applyFailed(let ctx),
             .transactionError(let ctx):
            return ctx
        }
    }

    /// User-facing message for view-layer consumption (idiomatic alongside
    /// `APIError.userFacingMessage()` and `AuthError.userFacingMessage()`).
    func userFacingMessage() -> String {
        errorDescription ?? Bundle.currentLocalizedString("yrs.error.technical")
    }
}
