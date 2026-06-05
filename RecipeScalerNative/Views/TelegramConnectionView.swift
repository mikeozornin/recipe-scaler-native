//
//  TelegramConnectionView.swift
//  RecipeScalerNative
//

import SwiftUI

private let recipeScalerBotURL = URL(string: "https://t.me/RecipeScalerBot")!
private let recipeScalerBotHandle = "@RecipeScalerBot"
private let statusPollIntervalSeconds: UInt64 = 3

struct TelegramConnectionView: View {
    let isOnline: Bool
    let onStatusChange: (Bool) -> Void

    @State private var isConnected = false
    @State private var telegramUsername: String?
    @State private var isLoading = false
    @State private var connectionCode: String?
    @State private var instructions: String?
    @State private var errorMessage: String?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isOnline {
                Text("account.public-profile.offline")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .appFootnote()
                    .foregroundStyle(.secondary)
            }

            if isConnected {
                connectedContent
            } else if let connectionCode {
                codeContent(connectionCode)
            } else {
                connectButton
            }
        }
        .task(id: pollTaskKey) {
            await refreshStatus()
        }
        .onChange(of: connectionCode) { _, code in
            restartPolling(if: code != nil && !isConnected)
        }
        .onChange(of: isConnected) { _, connected in
            onStatusChange(connected)
            if connected {
                connectionCode = nil
                instructions = nil
                stopPolling()
            }
        }
        .onDisappear {
            stopPolling()
        }
    }

    private var pollTaskKey: String {
        "\(isConnected)-\(connectionCode ?? "")-\(isOnline)"
    }

    @ViewBuilder
    private var connectedContent: some View {
        Label {
            Text(connectedLabel)
                .font(AppTypography.body)
        } icon: {
            AppSymbol.image("checkmark.circle.fill")
                .foregroundStyle(.green)
        }

        Divider()

        Button(String(localized: "telegram.disconnect")) {
            Task { await disconnect() }
        }
        .disabled(isLoading || !isOnline)
        .accessibilityIdentifier(AccessibilityIdentifiers.accountTelegramDisconnect)
    }

    private var connectedLabel: String {
        var text = String(localized: "telegram.connected")
        if let username = formattedTelegramUsername {
            text += " (\(username))"
        }
        return text
    }

    private var formattedTelegramUsername: String? {
        guard let raw = telegramUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw.hasPrefix("@") ? raw : "@\(raw)"
    }

    @ViewBuilder
    private var connectButton: some View {
        Button("telegram.connect") {
            Task { await connect() }
        }
        .disabled(isLoading || !isOnline)
        .accessibilityIdentifier(AccessibilityIdentifiers.accountTelegramConnect)
    }

    @ViewBuilder
    private func codeContent(_ code: String) -> some View {
        if let instructions {
            instructionsView(instructions)
                .font(AppTypography.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack(alignment: .center, spacing: 0) {
            Text("/connect \(code)")
                .font(AppTypography.mono(AppTypography.subheadlineSize))
                .frame(maxWidth: .infinity, minHeight: AppToolbarStyle.minimumTapSide, alignment: .leading)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .textSelection(.enabled)
                .accessibilityIdentifier(AccessibilityIdentifiers.accountTelegramCode)

            codeActionButton(
                symbol: "doc.on.doc",
                labelKey: "telegram.copy-code",
                identifier: AccessibilityIdentifiers.accountTelegramCopy
            ) {
                UIPasteboard.general.string = "/connect \(code)"
            }

            codeActionButton(
                symbol: "arrow.clockwise",
                labelKey: "telegram.refresh-code",
                identifier: AccessibilityIdentifiers.accountTelegramRefresh,
                isDisabled: isLoading || !isOnline
            ) {
                Task { await connect() }
            }
        }
    }

    private func codeActionButton(
        symbol: String,
        labelKey: LocalizedStringKey,
        identifier: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AppSymbol.image(symbol)
                .font(AppTypography.iconSize(AppToolbarStyle.iconSide))
                .foregroundStyle(Color.accentColor)
                .frame(width: AppToolbarStyle.minimumTapSide, height: AppToolbarStyle.minimumTapSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .accessibilityLabel(labelKey)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func instructionsView(_ text: String) -> some View {
        Text(instructionsAttributedString(from: text))
    }

    private func instructionsAttributedString(from text: String) -> AttributedString {
        let parts = text.components(separatedBy: recipeScalerBotHandle)
        guard parts.count > 1 else { return AttributedString(text) }

        var result = AttributedString()
        for (index, part) in parts.enumerated() {
            if !part.isEmpty { result += AttributedString(part) }
            if index < parts.count - 1 {
                var handle = AttributedString(recipeScalerBotHandle)
                handle.link = recipeScalerBotURL
                result += handle
            }
        }
        return result
    }

    private func refreshStatus() async {
        guard AuthService.shared.userId != nil else { return }
        do {
            let status = try await TelegramAPI.status()
            applyStatus(status)
        } catch {
            // Match web: status errors are non-fatal on initial load.
        }
    }

    private func applyStatus(_ status: TelegramConnectionStatusDTO) {
        isConnected = status.connected
        telegramUsername = status.telegramUsername
        if status.connected {
            connectionCode = nil
            instructions = nil
        }
    }

    private func connect() async {
        guard isOnline else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await TelegramAPI.connect()
            connectionCode = result.code
            instructions = result.instructions
            restartPolling(if: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() async {
        guard isOnline else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await TelegramAPI.disconnect()
            isConnected = false
            telegramUsername = nil
            connectionCode = nil
            instructions = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restartPolling(if shouldPoll: Bool) {
        stopPolling()
        guard shouldPoll, isOnline, !isConnected else { return }
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: statusPollIntervalSeconds * 1_000_000_000)
                guard !Task.isCancelled else { break }
                guard connectionCode != nil, !isConnected else { break }
                do {
                    let status = try await TelegramAPI.status()
                    guard !Task.isCancelled else { break }
                    applyStatus(status)
                    if status.connected { break }
                } catch {
                    // Keep polling until connected or code cleared.
                }
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}