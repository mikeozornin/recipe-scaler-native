//
//  AliceConnectionViewModel.swift
//  RecipeScalerNative
//
//  Web spec 066 (US11): «Профиль» → «Алиса» → «Подключить» issues an 8-digit
//  code the user types on the «Книга рецептов» sign-in page or says to Alice.
//  Web parity: `recipe-scaler/src/components/alice-connection.tsx`.
//  Pattern: `TelegramConnectionViewModel` (polling) + `VkusvillAccountViewModel`
//  (closure providers, epoch guard).
//

import Foundation
import Observation
import RecipeScalerCore

@MainActor
@Observable
final class AliceConnectionViewModel {
    /// Poll cadence while a code is shown, so the row flips to «Подключена»
    /// once the user finishes linking on the Yandex side (web parity: 3 s).
    static let statusPollInterval: Duration = .seconds(3)

    private(set) var isConnected = false
    private(set) var isLoading = false
    private(set) var connectionCode: String?
    private(set) var errorMessage: String?

    /// Bumped by every successful mutation, so a status GET that started
    /// earlier cannot overwrite the newer state when it lands.
    private var epoch = 0
    private var pollTask: Task<Void, Never>?

    var hasAuthenticatedUser: () -> Bool = { AuthService.shared.userId != nil }
    var fetchStatusProvider: () async throws -> AliceConnectionStatusDTO = { try await AliceAPI.status() }
    var connectProvider: () async throws -> AliceConnectionCodeDTO = { try await AliceAPI.connect() }
    var disconnectProvider: () async throws -> Void = { try await AliceAPI.disconnect() }
    var pollInterval: Duration = AliceConnectionViewModel.statusPollInterval

    // No deinit cancel: `deinit` is nonisolated and `pollTask` is main-actor
    // isolated. The poll loop holds `self` weakly; `onDisappear` → `stopPolling()`.

    func refreshStatus(isOnline: Bool) async {
        guard isOnline, hasAuthenticatedUser() else { return }
        let startedEpoch = epoch
        do {
            let status = try await fetchStatusProvider()
            guard startedEpoch == epoch else { return }
            applyStatus(status)
        } catch {
            // Web parity: a failed status probe keeps the current state silently.
        }
    }

    /// Issues a fresh code; also backs the «new code» action (the old code
    /// stays valid on the server until its TTL or first use).
    func connect(isOnline: Bool) async {
        guard isOnline, hasAuthenticatedUser(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await connectProvider()
            epoch += 1
            connectionCode = result.code
            startPolling()
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }

    func disconnect(isOnline: Bool) async {
        guard isOnline, hasAuthenticatedUser(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await disconnectProvider()
            epoch += 1
            isConnected = false
            connectionCode = nil
            stopPolling()
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }

    /// Restarts the poll loop after the view reappears with a code still shown.
    func resumePollingIfNeeded() {
        guard pollTask == nil, connectionCode != nil, !isConnected else { return }
        startPolling()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Private

    private func applyStatus(_ status: AliceConnectionStatusDTO) {
        isConnected = status.connected
        if status.connected {
            connectionCode = nil
            stopPolling()
        }
    }

    private func startPolling() {
        stopPolling()
        guard connectionCode != nil, !isConnected else { return }
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                guard self.connectionCode != nil, !self.isConnected else { return }
                let startedEpoch = self.epoch
                do {
                    let status = try await self.fetchStatusProvider()
                    guard !Task.isCancelled, startedEpoch == self.epoch else { continue }
                    if status.connected {
                        self.isConnected = true
                        self.connectionCode = nil
                        self.pollTask = nil
                        return
                    }
                } catch {
                    // Keep polling until connected or the code is cleared.
                }
            }
        }
    }
}
