//
//  AccountView.swift
//  RecipeScalerNative
//

import LocalAuthentication
import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var syncService: YjsSyncService
    @EnvironmentObject private var remindersService: RemindersSyncService
    @Environment(\.locale) private var locale
    @StateObject private var authService = AuthService.shared
    @StateObject private var viewModel = AccountSettingsViewModel()

    @State private var showingLogoutConfirmation = false
    @State private var showLoginOnDevice = false
    @State private var appLanguage: AppLanguagePreference = .current
    @State private var isTelegramConnected = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.isOnline {
                    Section {
                        Label {
                            Text("account.offline.alert")
                        } icon: {
                            AppSymbol.image("wifi.slash")
                                .foregroundStyle(.secondary)
                        }
                        .font(AppTypography.subheadline)
                        .padding(.top, 8)
                    }
                }

                accountSection
                publicRecipesSection
                telegramSection
                preferencesSection
                // dataSection

                if let statusMessage = viewModel.statusMessage {
                    Section {
                        Text(statusMessage)
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                }

                footerSection

                MobileTimerPanelListSpacerRow()
            }
            .localizedNavigationTitle("account.title")
            .listSectionSpacing(12)
            .appListBodyTypography()
            .sheet(isPresented: $showLoginOnDevice) {
                AccountSeedPhraseSheet()
            }
            .sheet(isPresented: $showingAbout) {
                InAppSafariView(url: PublicURLBuilder.aboutURL)
                    .ignoresSafeArea()
            }
            .confirmationDialog(
                String(localized: "account.logout.confirm"),
                isPresented: $showingLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "account.logout"), role: .destructive) {
                    Task { @MainActor in await viewModel.logout(syncService: syncService) }
                }
                Button(String(localized: "common.cancel"), role: .cancel) { }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.accountRoot)
            .task {
                await viewModel.refresh(syncService: syncService)
                appLanguage = .current
            }
            .onChange(of: syncService.connectionState) { _, _ in
                Task { @MainActor in
                    viewModel.bind(syncService: syncService)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let userId = authService.userId {
                HStack(spacing: 12) {
                    accountAvatar
                    Text(UserIdFormatter.format(userId))
                        .font(AppTypography.body)
                    Spacer(minLength: 8)
                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        AppSymbol.image("rectangle.portrait.and.arrow.right")
                            .font(AppTypography.body)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "account.logout"))
                }
            }

            Button("auth.login-with-another") {
                showLoginOnDevice = true
            }
        } header: {
            AppSectionHeader("account.section.account")
        }
        .appListSectionHeaderStyle()
    }

    @ViewBuilder
    private var publicRecipesSection: some View {
        Section {
            if !viewModel.isOnline {
                Text("account.public-profile.offline")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.isLoading {
                ProgressView()
            } else {
                Toggle(isOn: Binding(
                    get: { viewModel.publicProfileEnabled },
                    set: { newValue in
                        Task { @MainActor in await viewModel.setPublicProfileEnabled(newValue) }
                    }
                )) {
                    Text("account.public-profile.switch").appBody()
                }
                .disabled(viewModel.isUpdatingSharing)

                if viewModel.publicProfileEnabled {
                    NavigationLink {
                        AccountProfileEditView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Text("account.profile.edit")
                                .appBody()
                            Spacer()
                            Text(viewModel.displayName.isEmpty
                                ? (viewModel.username.map { "@\($0)" } ?? "")
                                : viewModel.displayName)
                                .appBody()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    NavigationLink {
                        AccountCheckmarkSelectionView(
                            navigationTitle: "account.share-mode.label",
                            options: PublicShareMode.allCases,
                            selection: viewModel.shareMode,
                            title: { $0.localizedTitleKey },
                            onSelect: { mode in
                                Task { @MainActor in await viewModel.setShareMode(mode) }
                            }
                        )
                    } label: {
                        AccountSettingsNavigationRow(
                            label: "account.share-mode.label",
                            value: viewModel.shareMode.localizedTitleKey
                        )
                    }
                    .disabled(viewModel.isUpdatingSharing)

                    Toggle(isOn: Binding(
                        get: { viewModel.allowRecipeDownloads },
                        set: { enabled in
                            Task { @MainActor in await viewModel.setAllowRecipeDownloads(enabled) }
                        }
                    )) {
                        Text("account.allow-downloads").appBody()
                    }
                    .disabled(viewModel.isUpdatingSharing)

                    if let username = viewModel.username,
                       let url = PublicURLBuilder.publicProfileURL(username: username) {
                        Link(destination: url) {
                            Text("account.your-public-recipes").appBody()
                        }
                    }
                }
            }
        } header: {
            AppSectionHeader("account.section.public-recipes")
        }
        .appListSectionHeaderStyle()
    }

    @ViewBuilder
    private var telegramSection: some View {
        Section {
            if !isTelegramConnected {
                Text("telegram.benefits-description-1")
                    .appBody()
                    .foregroundStyle(.secondary)
            }
            TelegramConnectionView(
                isOnline: viewModel.isOnline,
                onStatusChange: { isTelegramConnected = $0 }
            )
        } header: {
            AppSectionHeader("telegram.accordion-title")
        }
        .appListSectionHeaderStyle()
    }

    @ViewBuilder
    private var preferencesSection: some View {
        Section {
            NavigationLink {
                AccountCheckmarkSelectionView(
                    navigationTitle: "account.language.label",
                    options: AppLanguagePreference.allCases,
                    selection: appLanguage,
                    title: { $0.localizedTitleKey },
                    onSelect: { language in
                        appLanguage = language
                        AppLanguagePreference.save(language)
                    }
                )
            } label: {
                AccountSettingsNavigationRow(
                    label: "account.language.label",
                    value: appLanguage.localizedTitleKey
                )
            }

            NavigationLink {
                AccountCheckmarkSelectionView(
                    navigationTitle: "account.theme.label",
                    options: AppThemePreference.allCases,
                    selection: viewModel.appTheme,
                    title: { $0.localizedTitleKey },
                    onSelect: { viewModel.setAppTheme($0) }
                )
            } label: {
                AccountSettingsNavigationRow(
                    label: "account.theme.label",
                    value: viewModel.appTheme.localizedTitleKey
                )
            }

            Toggle("account.nutrition.show", isOn: Binding(
                get: { viewModel.showNutrition },
                set: { value in
                    Task { @MainActor in await viewModel.setShowNutrition(value) }
                }
            ))

            // MARK: Apple Reminders sync
            Toggle(isOn: Binding(
                get: { viewModel.remindersSyncEnabled },
                set: { value in
                    Task { @MainActor in
                        await viewModel.setRemindersSyncEnabled(
                            value,
                            syncService: syncService,
                            remindersService: remindersService
                        )
                    }
                }
            )) {
                Text("account.reminders.sync").appBody()
            }
            .disabled(viewModel.remindersSyncDenied)

            if viewModel.remindersSyncEnabled {
                NavigationLink {
                    RemindersListPickerView(
                        availableLists: viewModel.availableRemindersLists,
                        currentIdentifier: RemindersSyncPreferences.listIdentifier
                    ) { identifier in
                        Task { @MainActor in
                            await viewModel.selectRemindersList(
                                identifier,
                                syncService: syncService,
                                remindersService: remindersService
                            )
                        }
                    }
                    .onAppear {
                        viewModel.loadRemindersLists(remindersService: remindersService)
                    }
                } label: {
                    HStack {
                        Text("account.reminders.list.label")
                            .appBody()
                        Spacer()
                        Text(verbatim: viewModel.remindersListName)
                            .appBody()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

        } header: {
            AppSectionHeader("account.section.preferences")
        } footer: {
            if viewModel.remindersSyncDenied {
                Text("account.reminders.denied")
                    .appFootnote()
            } else {
                Text("account.reminders.sync.footer")
                    .appFootnote()
            }
        }
        .appListSectionHeaderStyle()
    }

    @ViewBuilder
    private var dataSection: some View {
        Section {
            Text("account.data.coming-soon")
                .font(AppTypography.subheadline)
                .foregroundStyle(.secondary)
        } header: {
            AppSectionHeader("account.section.data")
        }
        .appListSectionHeaderStyle()
    }

    @ViewBuilder
    private var footerSection: some View {
        Section {
            NavigationLink {
                SyncStatusContent(
                    connectionState: syncService.connectionState,
                    connectionTransport: syncService.connectionTransport,
                    imageCacheStatus: syncService.imageCacheStatus,
                    recipeDocumentCacheStatus: syncService.recipeDocumentCacheStatus,
                    onRetryImageDownload: { syncService.retryImagePrefetch() },
                    onRetryRecipeDocumentsDownload: { syncService.retryRecipeDocumentsBatchLoad() }
                )
                .localizedNavigationTitle("account.sync.title")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack {
                    Text("account.sync.title")
                        .appBody()
                    Spacer()
                    Text(syncDateLabel)
                        .appBody()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Button {
                showingAbout = true
            } label: {
                Text("account.about-link")
                    .appBody()
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                LabeledContent("account.version", value: version)
            }
        } header: {
            AppSectionHeaderSpacer()
        }
    }

    /// Relative "5 min ago"-style label for the last successful sync.
    /// Reads `\.locale` so the label recomputes when the user switches language.
    private var syncDateLabel: String {
        _ = locale
        guard let date = syncService.lastSuccessfulSyncAt else {
            return Bundle.currentLocalizedString("account.sync.never")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private var accountAvatar: some View {
        Group {
            if let url = viewModel.avatarURL {
                AuthAvatarImage(url: url)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}

// MARK: - Seed phrase (biometrics + QR)

private struct AccountSeedPhraseSheet: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var unlocked = false
    @State private var authError: String?

    var body: some View {
        NavigationStack {
            Group {
                if unlocked {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("account.secret-phrase")
                                .font(AppTypography.body)
                            if let seed = try? authService.getSeedPhrase() {
                                Text(seed)
                                    .font(AppTypography.mono(AppTypography.bodySize))
                                    .textSelection(.enabled)
                                ShareLink(item: seed) {
                                    Label("account.seed.copy", systemImage: "doc.on.doc")
                                }
                                SeedQRCodeView(text: seed)
                            } else {
                                Text("account.no-seed")
                                    .font(AppTypography.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                } else {
                    ContentUnavailableView {
                        Label("account.seed.locked", systemImage: "lock.fill")
                    } description: {
                        if let authError {
                            Text(authError)
                                .font(AppTypography.body)
                        } else {
                            Text("account.seed.unlock-hint")
                                .font(AppTypography.body)
                        }
                    } actions: {
                        Button("account.seed.unlock") {
                            Task { @MainActor in await authenticate() }
                        }
                    }
                }
            }
            .navigationTitle(Text("account.secret-phrase"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                        .appToolbarConfirmButton()
                }
            }
            .appListBodyTypography()
            .task {
                await authenticate()
            }
        }
    }

    @MainActor
    private func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true
            return
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "account.seed.biometric-reason")
            )
            unlocked = ok
            authError = ok ? nil : String(localized: "account.seed.auth-failed")
        } catch {
            authError = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AccountView()
    }
}
#endif