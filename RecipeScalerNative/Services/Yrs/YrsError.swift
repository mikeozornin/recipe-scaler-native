import Foundation
import YrsC

/// Custom errors for yrs operations.
enum YrsError: Error, LocalizedError {
    case nullPointer(context: String)
    case applyFailed(context: String)
    case transactionError(context: String)
    case invalidState(context: String)
    case corruptedState(docKey: String)

    var errorDescription: String? {
        switch self {
        case .nullPointer(let ctx):
            return "Yrs null pointer: \(ctx)"
        case .applyFailed(let ctx):
            return "Yrs apply failed: \(ctx)"
        case .transactionError(let ctx):
            return "Yrs transaction error: \(ctx)"
        case .invalidState(let ctx):
            return "Yrs invalid state: \(ctx)"
        case .corruptedState(let key):
            return "Yrs corrupted state for doc: \(key)"
        }
    }
}
