import Foundation
import RecipeScalerCore

enum FeedbackAttachmentLimits {
    static let maxFiles = 5
    static let maxBytesPerFile = 10_000_000
    static let maxMessageLength = 4000

    static func remainingSlots(currentCount: Int) -> Int {
        max(0, maxFiles - currentCount)
    }

    static func canAccept(fileCount: Int, additional: Int) -> Bool {
        remainingSlots(currentCount: fileCount) >= additional
    }

    static func isFileTooLarge(_ byteCount: Int) -> Bool {
        byteCount > maxBytesPerFile
    }

    static func trimmedMessage(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canSend(message: String) -> Bool {
        let trimmed = trimmedMessage(message)
        return !trimmed.isEmpty && trimmed.count <= maxMessageLength
    }
}

struct FeedbackAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let fileName: String
    let mimeType: String
    let data: Data

    var byteCount: Int { data.count }

    init(id: UUID = UUID(), fileName: String, mimeType: String, data: Data) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }
}

@MainActor
@Observable
final class AccountFeedbackModel {
    var message = ""
    var attachments: [FeedbackAttachment] = []
    var isSubmitting = false
    var errorMessage: String?
    private(set) var submitGeneration = 0

    var submitHandler: (String, [FeedbackAttachment]) async throws -> Void = { message, files in
        try await AccountAPI.submitFeedback(
            message: message,
            files: files.map { ($0.fileName, $0.data, $0.mimeType) }
        )
    }

    var canSend: Bool {
        FeedbackAttachmentLimits.canSend(message: message) && !isSubmitting
    }

    var remainingSlots: Int {
        FeedbackAttachmentLimits.remainingSlots(currentCount: attachments.count)
    }

    func bumpGeneration() {
        submitGeneration += 1
    }

    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    @discardableResult
    func addAttachments(_ incoming: [FeedbackAttachment]) -> String? {
        var accepted: [FeedbackAttachment] = []
        for item in incoming {
            if FeedbackAttachmentLimits.isFileTooLarge(item.byteCount) {
                return "account.feedback.too-large"
            }
            if !FeedbackAttachmentLimits.canAccept(
                fileCount: attachments.count + accepted.count,
                additional: 1
            ) {
                return "account.feedback.max-files"
            }
            accepted.append(item)
        }
        attachments.append(contentsOf: accepted)
        return nil
    }

    func submit(isOnline: Bool, isAuthenticated: Bool) async -> Bool {
        errorMessage = nil
        guard isAuthenticated, isOnline else { return false }
        let trimmed = FeedbackAttachmentLimits.trimmedMessage(message)
        guard FeedbackAttachmentLimits.canSend(message: trimmed) else { return false }
        guard !isSubmitting else { return false }

        isSubmitting = true
        let generation = submitGeneration
        let snapshot = attachments
        defer { isSubmitting = false }

        do {
            try await submitHandler(trimmed, snapshot)
            guard generation == submitGeneration else { return false }
            message = ""
            attachments = []
            return true
        } catch {
            guard generation == submitGeneration else { return false }
            let text = UserFacingAPIError.message(for: error)
            errorMessage = text.isEmpty ? Bundle.currentLocalizedString("account.feedback.send-failed") : text
            return false
        }
    }
}
