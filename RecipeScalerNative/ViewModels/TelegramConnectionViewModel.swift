//
//  TelegramConnectionViewModel.swift
//  RecipeScalerNative
//
//  Review 2026.09.04 №18 — network orchestration extracted from
//  `TelegramConnectionView` (struct Views cannot own polling tasks or be
//  unit-tested without host synchronization). Pattern: `AccountSettingsViewModel`.
//

import Foundation
import Observation
import RecipeScalerCore

@MainActor
@Observable
final class TelegramConnectionViewModel {
    /// Poll cadence while a connection code is outstanding (web parity).
    static let statusPollIntervalSeconds: UInt64 = 3

    private(set) var isConnected = false
    private(set) var telegramUsername: String?
    private(set) var isLoading = false
    private(set) var connectionCode: String?
    private(set) var instructions: String?
    private(set) var errorMessage: String?

    private var pollTask: Task<Void, Never>?

    /// Auth gate for the status probe — injectable seam (the view used to
    /// read `AuthService.shared.userId` directly in a production method).
    var hasAuthenticatedUser: () -> Bool = { AuthService.shared.userId != nil }

    private let api: TelegramAPI.Type

    init(api: TelegramAPI.Type = TelegramAPI.self) {
        self.api = api
    }

    // No deinit pollTask cancel: `deinit` is nonisolated and `pollTask` is
    // main-actor-isolated. The poll loop holds `self` weakly and exits on its
    // own; `onDisappear` → `stopPolling()` is the supported teardown path.

    func refreshStatus() async {
        guard hasAuthenticatedUser() else { return }
        do {
            let status = try await api.status()
            applyStatus(status)
        } catch {
            // Match web: status errors are non-fatal on initial load.
        }
    }

    func connect(isOnline: Bool) async {
        guard isOnline else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await api.connect()
            connectionCode = result.code
            instructions = result.instructions
            restartPolling(if: true, isOnline: isOnline)
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }

    func disconnect(isOnline: Bool) async {
        guard isOnline else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await api.disconnect()
            isConnected = false
            telegramUsername = nil
            connectionCode = nil
            instructions = nil
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }

    /// Public hook for the view's `onChange(of: connectionCode)` — restarts
    /// the poll loop when a fresh code appears for a disconnected user.
    func handleConnectionCodeChange(isOnline: Bool) {
        restartPolling(if: connectionCode != nil && !isConnected, isOnline: isOnline)
    }

    /// Clears the code/instructions once connected (view's
    /// `onChange(of: isConnected)` companion).
    func handleConnected() {
        connectionCode = nil
        instructions = nil
        stopPolling()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Private

    private func applyStatus(_ status: TelegramConnectionStatusDTO) {
        isConnected = status.connected
        telegramUsername = status.telegramUsername
        if status.connected {
            connectionCode = nil
            instructions = nil
        }
    }

    private func restartPolling(if shouldPoll: Bool, isOnline: Bool) {
        stopPolling()
        guard shouldPoll, isOnline, !isConnected else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.statusPollIntervalSeconds * 1_000_000_000)
                guard let self, !Task.isCancelled else { break }
                guard self.connectionCode != nil, !self.isConnected else { break }
                do {
                    let status = try await self.api.status()
                    guard !Task.isCancelled else { break }
                    self.applyStatus(status)
                    if status.connected { break }
                } catch {
                    // Keep polling until connected or code cleared.
                }
            }
        }
    }
}
