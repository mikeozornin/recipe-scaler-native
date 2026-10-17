//
//  VkusvillAccountViewModel.swift
//  RecipeScalerNative
//
//  Spec 083: строки «Войти / Выйти» под тоглом Вкусвилла (072) в профиле.
//  Pattern: `TelegramConnectionViewModel`; сетевые seams — как у `VkusvillSettingsStore`.
//

import AuthenticationServices
import Foundation
import Observation
import RecipeScalerCore

@MainActor
@Observable
final class VkusvillAccountViewModel {
    private(set) var connection: VkusvillConnectionDTO?
    private(set) var isLoading = false
    /// Идёт вход или выход: обе кнопки неактивны.
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    /// Строки входа видны, пока статус не загружен или сервер настроен.
    var isAvailable: Bool { connection?.available ?? true }
    var isConnected: Bool { connection?.connected == true }
    var needsReconnect: Bool { isConnected && connection?.status == .reconnectRequired }
    var hasNoDeliveryAddress: Bool { isConnected && !needsReconnect && connection?.personalized == false }

    /// Bumped by every applied result so a status GET started before a
    /// sign-in/sign-out can never overwrite its outcome.
    private var epoch = 0

    var hasAuthenticatedUser: () -> Bool = { AuthService.shared.userId != nil }
    var fetchConnectionProvider: () async throws -> VkusvillConnectionDTO = {
        try await VkusvillAccountAPI.fetchConnection()
    }
    var startSignInProvider: () async throws -> URL = {
        try await VkusvillAccountAPI.startSignIn()
    }
    var completeSignInProvider: (_ code: String, _ state: String) async throws -> VkusvillConnectionDTO = { code, state in
        try await VkusvillAccountAPI.completeSignIn(code: code, state: state)
    }
    var signOutProvider: () async throws -> VkusvillConnectionDTO = {
        try await VkusvillAccountAPI.signOut()
    }

    func refresh(isOnline: Bool) async {
        guard isOnline, hasAuthenticatedUser() else { return }
        epoch &+= 1
        let requestEpoch = epoch
        isLoading = true
        defer {
            if requestEpoch == epoch {
                isLoading = false
            }
        }
        do {
            let value = try await fetchConnectionProvider()
            guard !Task.isCancelled, requestEpoch == epoch else { return }
            connection = value
        } catch {
            // Как у Telegram: ошибка статуса не показывается, кнопка входа остаётся.
        }
    }

    /// `authenticate` открывает authorize URL во Вкусвилле и возвращает callback URL.
    func signIn(isOnline: Bool, authenticate: (URL) async throws -> URL) async {
        guard isOnline, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let authorizeURL = try await startSignInProvider()
            let callbackURL = try await authenticate(authorizeURL)
            switch VkusvillOAuthCallback.parse(callbackURL) {
            case .denied:
                return
            case .failed:
                errorMessage = Bundle.currentLocalizedString("vkusvill.account.error.sign-in-failed")
            case let .code(code, state):
                apply(try await completeSignInProvider(code, state))
            }
        } catch {
            guard !Self.isUserCancellation(error) else { return }
            errorMessage = Self.signInMessage(for: error)
        }
    }

    func signOut(isOnline: Bool) async {
        guard isOnline, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            apply(try await signOutProvider())
        } catch {
            errorMessage = UserFacingAPIError.isTransientNetworkError(error)
                ? Bundle.currentLocalizedString("account.error.unreachable")
                : Bundle.currentLocalizedString("vkusvill.account.error.sign-out-failed")
        }
    }

    /// Выключение тогла выходит из аккаунта на сервере (`PUT /api/settings`);
    /// здесь только убираем устаревшее состояние. Если PUT не прошёл, тогл
    /// откатится и следующий `refresh` вернёт настоящий статус.
    func handleToggleChange(enabled: Bool) {
        guard !enabled else { return }
        errorMessage = nil
        if let connection, connection.connected {
            apply(connection.signedOut)
        }
    }

    // MARK: - Private

    private func apply(_ value: VkusvillConnectionDTO) {
        epoch &+= 1
        connection = value
        isLoading = false
    }

    static func isUserCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let sessionError = error as? ASWebAuthenticationSessionError {
            return sessionError.code == .canceledLogin
        }
        return false
    }

    static func signInMessage(for error: Error) -> String {
        switch error as? VkusvillAccountError {
        case .signInExpired:
            return Bundle.currentLocalizedString("vkusvill.account.error.sign-in-expired")
        case .vkusvillUnavailable:
            return Bundle.currentLocalizedString("vkusvill.account.error.unavailable")
        case .notConfigured:
            return Bundle.currentLocalizedString("vkusvill.account.error.not-configured")
        case .server, nil:
            if UserFacingAPIError.isTransientNetworkError(error) {
                return Bundle.currentLocalizedString("account.error.unreachable")
            }
            return Bundle.currentLocalizedString("vkusvill.account.error.sign-in-failed")
        }
    }
}
