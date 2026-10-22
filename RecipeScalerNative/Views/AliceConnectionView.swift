//
//  AliceConnectionView.swift
//  RecipeScalerNative
//
//  Web spec 066 (US11): the Alice («Книга рецептов») row of «Моё всё».
//  Presentation only; network and polling live in `AliceConnectionViewModel`.
//

import SwiftUI

struct AliceConnectionView: View {
    let isOnline: Bool
    /// Incremented by the parent on pull-to-refresh so the status is re-fetched.
    let refreshTick: Int

    @State private var model = AliceConnectionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .appFootnote()
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            if model.isConnected {
                connectedContent
            } else if let connectionCode = model.connectionCode {
                codeContent(connectionCode)
            } else {
                connectButton
            }
        }
        .animation(AppMotion.enter, value: model.errorMessage)
        .task(id: refreshKey) {
            await model.refreshStatus(isOnline: isOnline)
            model.resumePollingIfNeeded()
        }
        .onDisappear {
            model.stopPolling()
        }
    }

    private var refreshKey: String {
        "\(isOnline)-\(refreshTick)"
    }

    private var actionsDisabled: Bool {
        model.isLoading || !isOnline
    }

    @ViewBuilder
    private var connectedContent: some View {
        HStack(spacing: 12) {
            Text("alice.connected")
                .appBody()
            Spacer(minLength: 0)
            AppSymbol.image("checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityIdentifiers.accountAliceStatus)

        Divider()

        Button {
            Task { await model.disconnect(isOnline: isOnline) }
        } label: {
            HStack {
                Text("alice.disconnect").appBody()
                Spacer(minLength: 0)
                if model.isLoading {
                    ProgressView()
                }
            }
        }
        .tint(.primary)
        .disabled(actionsDisabled)
        .accessibilityIdentifier(AccessibilityIdentifiers.accountAliceDisconnect)
    }

    private var connectButton: some View {
        Button {
            Task { await model.connect(isOnline: isOnline) }
        } label: {
            HStack {
                Text("alice.connect").appBody()
                Spacer(minLength: 0)
                if model.isLoading {
                    ProgressView()
                }
            }
        }
        .disabled(actionsDisabled)
        .accessibilityIdentifier(AccessibilityIdentifiers.accountAliceConnect)
    }

    @ViewBuilder
    private func codeContent(_ code: String) -> some View {
        Text("alice.code-instructions")
            .appBody()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

        HStack(alignment: .center, spacing: 0) {
            Text(verbatim: code)
                .font(AppTypography.mono(AppTypography.subheadlineSize))
                .frame(maxWidth: .infinity, minHeight: AppToolbarStyle.minimumTapSide, alignment: .leading)
                .padding(.horizontal, 12)
                // Grouped tertiary fill stays visible on the dark inset-grouped cell
                // (secondarySystemBackground equals the cell colour in dark mode).
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .textSelection(.enabled)
                .speechSpellsOutCharacters()
                .accessibilityIdentifier(AccessibilityIdentifiers.accountAliceCode)

            codeActionButton(
                symbol: "doc.on.doc",
                labelKey: "alice.copy-connect-code",
                identifier: AccessibilityIdentifiers.accountAliceCopy
            ) {
                AppPasteboard.setString(code)
            }

            codeActionButton(
                symbol: "arrow.clockwise",
                labelKey: "alice.refresh-connect-code",
                identifier: AccessibilityIdentifiers.accountAliceRefresh,
                isDisabled: actionsDisabled
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
}
