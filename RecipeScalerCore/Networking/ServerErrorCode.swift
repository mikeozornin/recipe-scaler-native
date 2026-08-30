//
//  ServerErrorCode.swift
//  RecipeScalerCore
//
//  Typed catalog of server-supplied error dot-keys.
//  Replaces the previous `String`-based `APIError.serverError(message:)` flow,
//  which required runtime string-prefix sniffing (`DotKeyLocalizer`) and could
//  leak raw English server messages into the UI when the contract was violated.
//
//  Contract: specs/031-error-i18n/server-error-keys.md
//

import Foundation

/// Typed catalog of all dot-keys the server may return in `APIResponse.error`.
///
/// - Throws-sites build instances from `response.error` via `from(serverValue:fallback:)`.
///   Unknown / legacy English strings collapse into the provided `fallback` code,
///   guaranteeing that only valid dot-keys reach the view layer.
/// - View layer resolves via `Bundle.currentLocalizedString(code.rawValue)`
///   without any prefix-sniffing.
public enum ServerErrorCode: String, Sendable, Equatable, CaseIterable {
    // auth.*
    case authRegisterFailed = "auth.register.failed"
    case authLoginFailed = "auth.login.failed"
    case authErrorInvalidSeed = "auth.error.invalid-seed"
    case authErrorApiGeneric = "auth.error.api-generic"

    // account.*
    case accountProfileLoadFailed = "account.profile.load-failed"
    case accountSharingLoadFailed = "account.sharing.load-failed"
    case accountSharingUpdateFailed = "account.sharing.update-failed"
    case accountSettingsLoadFailed = "account.settings.load-failed"
    case accountFeedbackSendFailed = "account.feedback.send-failed"
    case accountFeedbackRateLimited = "account.feedback.rate-limited"
    case accountFeedbackInvalid = "account.feedback.invalid"
    case accountFeedbackTooLarge = "account.feedback.too-large"

    // discover.*
    case discoverFetchFailed = "discover.fetch-failed"
    case discoverCollectionFailed = "discover.collection-failed"
    case discoverRecipeFailed = "discover.recipe-failed"
    case discoverCloneFailed = "discover.clone-failed"
    case discoverPublicRecipeFailed = "discover.public-recipe-failed"
    case discoverCopyFailed = "discover.copy-failed"
    case discoverPublicProfileFailed = "discover.public-profile-failed"

    // follow.* (spec 072)
    case followUserNotFound = "follow.user-not-found"
    case followSelfNotAllowed = "follow.self-not-allowed"
    case followTooManyFollows = "follow.too-many-follows"
    case followRateLimited = "follow.rate-limited"
    case followNotFollowing = "follow.not-following"

    // recipe.*
    case recipeImportNoImages = "recipe.import.no-images"
    case recipeImportFailed = "recipe.import.failed"
    case recipeImageUploadFailed = "recipe.image.upload-failed"
    case recipeImageDeleteFailed = "recipe.image.delete-failed"

    // sharing.*
    case sharingUpdateFailed = "sharing.update-failed"

    // telegram.*
    case telegramFailedToGetCode = "telegram.failed-to-get-code"
    case telegramStatusFailed = "telegram.status-failed"
    case telegramFailedToDisconnect = "telegram.failed-to-disconnect"

    // assistant.*
    case assistantThreadsCreateFailed = "assistant.threads.create.failed"
    case assistantThreadsListFailed = "assistant.threads.list.failed"
    case assistantMessagesLoadFailed = "assistant.messages.load.failed"
    case assistantThreadsDeleteFailed = "assistant.threads.delete.failed"
    case assistantMessageEmpty = "assistant.message.empty"
    case assistantMessageTooLong = "assistant.message.too-long"
    case assistantStreamHttpError = "assistant.stream.http-error"
    case assistantVoiceErrorTooLong = "assistant.voice-error.too-long"
    case assistantVoiceErrorTranscription = "assistant.voice-error.transcription"
    case assistantErrorUnavailable = "assistant.error-unavailable"

    // api.* generic fallbacks (used when the server response cannot be matched
    // to a domain-specific code, or as endpoint defaults).
    case apiErrorServerGeneric = "api.error.server-generic"

    /// Resolve a server-supplied string into a typed code.
    ///
    /// - If `serverValue` is `nil`/empty or does not match any known dot-key,
    ///   `fallback` is returned. This guarantees the caller never has to deal
    ///   with a raw `String` of unknown shape.
    public static func from(serverValue: String?, fallback: ServerErrorCode) -> ServerErrorCode {
        guard let serverValue,
              !serverValue.isEmpty,
              let code = ServerErrorCode(rawValue: serverValue) else {
            return fallback
        }
        return code
    }
}
