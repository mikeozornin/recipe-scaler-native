//
//  VkusvillSettingsSection.swift
//  RecipeScalerNative
//
//  Spec 072 + 083: секция «Вкусвилл» в профиле — тогл и вход в аккаунт
//  (вариант B прототипа). Тогл без входа — анонимный режим; вход добавляет
//  наличие по адресу доставки и историю покупок.
//

import AuthenticationServices
import RecipeScalerCore
import SwiftUI

struct VkusvillSettingsSection: View {
    let isEnabled: Bool
    let isToggleDisabled: Bool
    /// Идёт `PUT /api/settings`. После него статус входа перечитывается:
    /// выключение тогла выходит из аккаунта на сервере.
    let isUpdatingToggle: Bool
    let isOnline: Bool
    /// Incremented by the parent on pull-to-refresh.
    let refreshTick: Int
    let onToggle: (Bool) -> Void

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.locale) private var locale
    @State private var model = VkusvillAccountViewModel()

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { isEnabled }, set: onToggle)) {
                Text("vkusvill.settings-toggle-title").appBody()
            }
            .disabled(isToggleDisabled)
            .accessibilityIdentifier(AccessibilityIdentifiers.vkusvillToggle)
            .task(id: refreshKey) {
                guard isEnabled, !isUpdatingToggle else { return }
                await model.refresh(isOnline: isOnline)
            }
            .onChange(of: isEnabled) { _, enabled in
                model.handleToggleChange(enabled: enabled)
            }

            if showsAccountRows {
                accountRows
            }
        } header: {
            AppSectionHeader("vkusvill.settings-title")
        } footer: {
            footer
        }
        .appListSectionHeaderStyle()
    }

    private var refreshKey: String {
        "\(isEnabled)-\(isUpdatingToggle)-\(isOnline)-\(refreshTick)"
    }

    private var showsAccountRows: Bool {
        isEnabled && model.isAvailable
    }

    private var actionsDisabled: Bool {
        !isOnline || model.isWorking
    }

    // MARK: - Rows

    @ViewBuilder
    private var accountRows: some View {
        if model.isConnected {
            statusRow
            if model.needsReconnect {
                signInButton("vkusvill.account.sign-in-again")
            }
            Button {
                Task { await model.signOut(isOnline: isOnline) }
            } label: {
                Text("vkusvill.account.sign-out").appBody()
            }
            .tint(.primary)
            .disabled(actionsDisabled)
            .accessibilityIdentifier(AccessibilityIdentifiers.vkusvillSignOut)
        } else {
            signInButton("vkusvill.account.sign-in")
        }
    }

    private func signInButton(_ titleKey: LocalizedStringKey) -> some View {
        Button {
            Task { await model.signIn(isOnline: isOnline, authenticate: authenticate) }
        } label: {
            HStack {
                Text(titleKey).appBody()
                Spacer(minLength: 0)
                if model.isWorking {
                    ProgressView()
                }
            }
        }
        .disabled(actionsDisabled)
        .accessibilityIdentifier(AccessibilityIdentifiers.vkusvillSignIn)
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("vkusvill.account.title").appBody()
                Text(statusSubtitle)
                    .appFootnote()
                    .foregroundStyle(model.needsReconnect ? Color.orange : Color.secondary)
            }
            Spacer(minLength: 0)
            AppSymbol.image(model.needsReconnect ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(model.needsReconnect ? Color.orange : Color.green)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityIdentifiers.vkusvillAccountStatus)
    }

    private var statusSubtitle: String {
        if model.needsReconnect {
            return Bundle.currentLocalizedString("vkusvill.account.reconnect-required")
        }
        guard let date = model.connection?.connectedDate else {
            return Bundle.currentLocalizedString("vkusvill.account.signed-in")
        }
        return String(
            format: Bundle.currentLocalizedString("vkusvill.account.signed-in-at"),
            Self.signedInDateText(date, locale: locale)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsAccountRows, let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .appFootnote()
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(AccessibilityIdentifiers.vkusvillAccountError)
            }
            footerNote
        }
    }

    @ViewBuilder
    private var footerNote: some View {
        if !showsAccountRows {
            Text("vkusvill.settings-toggle-footer").appFootnote()
        } else if model.needsReconnect {
            // The status row above already shows the warning icon.
            Text("vkusvill.account.reconnect-footer")
                .appFootnote()
                .foregroundStyle(.orange)
        } else if model.hasNoDeliveryAddress {
            warningNote("vkusvill.account.no-address-footer")
        } else if model.isConnected {
            Text("vkusvill.account.connected-footer").appFootnote()
        } else {
            Text("vkusvill.account.consent-footer").appFootnote()
        }
    }

    private func warningNote(_ key: LocalizedStringKey) -> some View {
        Label {
            Text(key).appFootnote()
        } icon: {
            AppSymbol.image("exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
    }

    // MARK: - Sign-in

    /// Ephemeral-сессия: сразу страница Вкусвилла, без системного диалога
    /// «„Recipe Scaler“ хочет использовать „vkusvill.ru“ для входа» (spec 083).
    private func authenticate(_ url: URL) async throws -> URL {
        if #available(iOS 17.4, *) {
            return try await webAuthenticationSession.authenticate(
                using: url,
                callback: .customScheme(DeepLinkURL.baseScheme),
                preferredBrowserSession: .ephemeral,
                additionalHeaderFields: [:]
            )
        }
        return try await webAuthenticationSession.authenticate(
            using: url,
            callbackURLScheme: DeepLinkURL.baseScheme,
            preferredBrowserSession: .ephemeral
        )
    }

    /// «17 октября»; год — только если вход был не в этом году.
    static func signedInDateText(_ date: Date, now: Date = Date(), locale: Locale, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar).day().month(.wide)
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(style)
        }
        return date.formatted(style.year())
    }
}
