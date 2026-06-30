//
//  AccountView.swift
//  RecipeScalerNative
//

import LocalAuthentication
import SwiftUI

private enum AccountSheet: Identifiable {
    case seed, about, privacy

    var id: Self { self }
}

struct AccountView: View {
    @Environment(YjsSyncService.self) private var syncService
    @Environment(RemindersSyncService.self) private var remindersService
    @Environment(AuthService.self) private var authService
    @Environment(FeatureAdoptionStore.self) private var featureAdoptionStore
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.mobileTimerPanelIsCollapsed) private var mobileTimerPanelIsCollapsed
    @Environment(\.locale) private var locale
    @State private var viewModel = AccountSettingsViewModel()

    @State private var showingLogoutConfirmation = false
    @State private var presentedSheet: AccountSheet?
    @State private var appLanguage: AppLanguagePreference = .current
    @AppStorage(RecipeFolderRoutes.collectionsRootLayoutStorageKey)
    private var collectionsLayoutRaw: String = RecipeFolderRoutes.CollectionsRootLayout.list.rawValue
    @State private var isTelegramConnected = false

    private var collectionsLayout: RecipeFolderRoutes.CollectionsRootLayout {
        RecipeFolderRoutes.CollectionsRootLayout(rawValue: collectionsLayoutRaw) ?? .list
    }

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.isOnline {
                    Section {
                        Label {
                            Text("account.offline.alert")
                                .appBody()
                                .foregroundStyle(.secondary)
                        } icon: {
                            AppSymbol.image("wifi.slash")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                }

                accountSection
                featureAdoptionSection
                publicRecipesSection
                telegramSection
                preferencesSection
                dataSection
                logExportSection

                if let statusMessage = viewModel.statusMessage {
                    Section {
                        Text(statusMessage)
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                }

                footerSection

                if MobileTimerPanelListChrome.needsSpacer(
                    timerManager: timerManager,
                    isCollapsed: mobileTimerPanelIsCollapsed
                ) {
                    MobileTimerPanelListSpacerRow()
                }
            }
            .localizedNavigationTitle("account.title")
            .listSectionSpacing(12)
            .appListBodyTypography()
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .seed:
                    AccountSeedPhraseSheet()
                case .about:
                    InAppSafariView(url: PublicURLBuilder.aboutURL)
                        .ignoresSafeArea()
                        .appOpaqueSheetPresentationPlain()
                case .privacy:
                    InAppSafariView(url: PublicURLBuilder.privacyURL)
                        .ignoresSafeArea()
                        .appOpaqueSheetPresentationPlain()
                }
            }
            .confirmationDialog(
                Bundle.currentLocalizedString("account.logout.confirm"),
                isPresented: $showingLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button(Bundle.currentLocalizedString("account.logout"), role: .destructive) {
                    Task { @MainActor in await viewModel.logout(syncService: syncService) }
                }
                Button(Bundle.currentLocalizedString("common.cancel"), role: .cancel) { }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.accountRoot)
            .refreshable {
                await featureAdoptionStore.refresh()
            }
            .task {
                featureAdoptionStore.loadFromCache()
                await featureAdoptionStore.refresh()
                await viewModel.refresh(syncService: syncService)
                appLanguage = .current
            }
            .onChange(of: syncService.connectionState) { _, _ in
                Task { @MainActor in
                    viewModel.bind(syncService: syncService)
                }
            }
            .onChange(of: isTelegramConnected) { wasConnected, isConnected in
                guard !wasConnected, isConnected else { return }
                Task { await featureAdoptionStore.refresh() }
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
                        .appBody()
                    Spacer(minLength: 8)
                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        AppSymbol.image("rectangle.portrait.and.arrow.right")
                            .font(AppTypography.body)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Bundle.currentLocalizedString("account.logout"))
                }
            }

            Button {
                presentedSheet = .seed
            } label: {
                Text("auth.login-with-another").appBody()
            }
        } header: {
            AppSectionHeader("account.section.account")
        }
        .appListSectionHeaderStyle()
    }

    @ViewBuilder
    private var featureAdoptionSection: some View {
        Section {
            NavigationLink {
                FeatureAdoptionDetailView()
            } label: {
                HStack {
                    Text("account.feature-adoption.title")
                        .appBody()
                    Spacer()
                    Text("\(featureAdoptionDoneCount) / \(FeatureAdoptionItem.allCases.count)")
                        .appBody()
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            AppSectionHeaderSpacer()
        }
        .appListSectionHeaderStyle()
    }

    @ViewBuilder
    private var publicRecipesSection: some View {
        Section {
            if !viewModel.isOnline {
                Text("account.public-profile.offline")
                    .appBody()
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

            NavigationLink {
                AccountCheckmarkSelectionView(
                    navigationTitle: "account.collections-layout.label",
                    options: RecipeFolderRoutes.CollectionsRootLayout.allCases,
                    selection: collectionsLayout,
                    title: { $0.localizedTitleKey },
                    onSelect: { layout in
                        collectionsLayoutRaw = layout.rawValue
                    }
                )
            } label: {
                AccountSettingsNavigationRow(
                    label: "account.collections-layout.label",
                    value: collectionsLayout.localizedTitleKey
                )
            }

            Toggle(isOn: Binding(
                get: { viewModel.showNutrition },
                set: { value in
                    Task { @MainActor in await viewModel.setShowNutrition(value) }
                }
            )) {
                Text("account.nutrition.show").appBody()
            }

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
            NavigationLink {
                DataManagementView()
            } label: {
                Text("account.data.management")
                    .appBody()
            }
        }
        .appListSectionHeaderStyle()
    }

    private var featureAdoptionDoneCount: Int {
        FeatureAdoptionItem.allCases
            .filter { featureAdoptionStore.value(for: $0) }
            .count
    }


    @ViewBuilder
    private var logExportSection: some View {
        Section {
            if let url = AppLog.currentLogFileURL() {
                ShareLink(item: url) {
                    Label {
                        Text("account.export.logs.title")
                            .appBody()
                    } icon: {
                        AppSymbol.image("square.and.arrow.up")
                    }
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("account.export.logs.missing")
                            .appBody()
                        Text("account.export.logs.missing.hint")
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    AppSymbol.image("info.circle")
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityIdentifiers.accountExportLogsMissing)
            }
        } header: {
            AppSectionHeader("account.section.logs")
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
                presentedSheet = .about
            } label: {
                Text("account.about-link")
                    .appBody()
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                presentedSheet = .privacy
            } label: {
                Text("privacy.link")
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
    @Environment(AuthService.self) private var authService
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
                        AppEmptyState.label("account.seed.locked", symbol: "lock.fill")
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
                    .font(AppTypography.body)
                }
            }
            .background(Color(.systemBackground))
            .localizedNavigationTitle("account.secret-phrase")
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
        .appOpaqueSheetPresentationPlain()
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
            authError = UserFacingAPIError.message(for: error)
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