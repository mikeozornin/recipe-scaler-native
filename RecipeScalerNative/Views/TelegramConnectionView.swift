//
//  TelegramConnectionView.swift
//  RecipeScalerNative
//

import SwiftUI

private let recipeScalerBotURL = URL(string: "https://t.me/RecipeScalerBot")!
private let recipeScalerBotHandle = "@RecipeScalerBot"

/// Review 2026.09.04 №18: network orchestration + polling live in
/// `TelegramConnectionViewModel`; this view is pure presentation.
struct TelegramConnectionView: View {
    let isOnline: Bool
    /// Incremented by the parent on pull-to-refresh so this view re-fetches
    /// connection status even when nothing else changes.
    let refreshTick: Int
    let onStatusChange: (Bool) -> Void

    @Environment(OfflineBannerGate.self) private var offlineGate
    @State private var model = TelegramConnectionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status banner gated by OfflineBannerGate (spec 066) — 3s debounce.
            // `isOnline` below (disabled buttons) intentionally stays instant.
            if offlineGate.isVisible {
                Text("account.public-profile.offline")
                    .appBody()
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .appFootnote()
                    .foregroundStyle(.secondary)
            }

            if model.isConnected {
                connectedContent
            } else if let connectionCode = model.connectionCode {
                codeContent(connectionCode)
            } else {
                connectButton
            }
        }
        .task(id: pollTaskKey) {
            await model.refreshStatus()
        }
        .onChange(of: model.connectionCode) { _, _ in
            model.handleConnectionCodeChange(isOnline: isOnline)
        }
        .onChange(of: model.isConnected) { _, connected in
            onStatusChange(connected)
            if connected {
                model.handleConnected()
            }
        }
        .onDisappear {
            model.stopPolling()
        }
    }

    private var pollTaskKey: String {
        "\(model.isConnected)-\(model.connectionCode ?? "")-\(isOnline)-\(refreshTick)"
    }

    @ViewBuilder
    private var connectedContent: some View {
        Label {
            Text(connectedLabel)
                .appBody()
        } icon: {
            AppSymbol.image("checkmark.circle.fill")
                .foregroundStyle(.green)
        }

        Divider()

        Button(String(localized: "telegram.disconnect")) {
            Task { await model.disconnect(isOnline: isOnline) }
        }
        .disabled(model.isLoading || !isOnline)
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
        guard let raw = model.telegramUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw.hasPrefix("@") ? raw : "@\(raw)"
    }

    @ViewBuilder
    private var connectButton: some View {
        Button("telegram.connect") {
            Task { await model.connect(isOnline: isOnline) }
        }
        .disabled(model.isLoading || !isOnline)
        .accessibilityIdentifier(AccessibilityIdentifiers.accountTelegramConnect)
    }

    @ViewBuilder
    private func codeContent(_ code: String) -> some View {
        if let instructions = model.instructions {
            instructionsView(instructions)
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
                AppPasteboard.setString("/connect \(code)")
            }

            codeActionButton(
                symbol: "arrow.clockwise",
                labelKey: "telegram.refresh-code",
                identifier: AccessibilityIdentifiers.accountTelegramRefresh,
                isDisabled: model.isLoading || !isOnline
            ) {
                Task { await model.connect(isOnline: isOnline) }
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

    private func instructionsView(_ text: String) -> some View {
        Text(instructionsAttributedString(from: text))
            .appBody()
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
}
