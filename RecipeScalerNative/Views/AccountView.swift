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
    @Environment(AppShellCoordinator.self) private var coordinator
    @Environment(\.mobileTimerPanelIsCollapsed) private var mobileTimerPanelIsCollapsed
    @Environment(\.locale) private var locale
    @State private var viewModel = AccountSettingsViewModel()

    @State private var showingLogoutConfirmation = false
    @State private var presentedSheet: AccountSheet?
    @State private var appLanguage: AppLanguagePreference = .current
    @State private var showingDeleteWarning = false
    @State private var showingDeleteSeedSheet = false
    /// Set by warning Continue; consumed when the alert finishes dismissing so the
    /// seed sheet does not race the system alert (SwiftUI alert→sheet bug).
    @State private var pendingDeleteSeedSheet = false
    @State private var isDeletingAccount = false
    @AppStorage(RecipeFolderRoutes.collectionsRootLayoutStorageKey)
    private var collectionsLayoutRaw: String = RecipeFolderRoutes.defaultCollectionsRootLayout.rawValue
    @State private var isTelegramConnected = false
    @State private var showRemindersListPicker = false
    /// Incremented on every pull-to-refresh so child views (Telegram status,
    /// legacy auth banner) re-run their `.task` and refetch non-pushed data.
    @State private var refreshTick = 0
    /// Tracks NDJSON journal presence so export/clear rows refresh after wipe.
    @State private var hasDebugLogFile = AppLog.currentLogFileURL() != nil

    private var collectionsLayout: RecipeFolderRoutes.CollectionsRootLayout {
        RecipeFolderRoutes.CollectionsRootLayout(rawValue: collectionsLayoutRaw)
            ?? RecipeFolderRoutes.defaultCollectionsRootLayout
    }

    /// Spec 040 — anchor ids for sections reachable from guide CTAs.
    enum AccountViewSection {
        case publicRecipes
        case telegram
        case reminders

        var id: String {
            switch self {
            case .publicRecipes: return "account.section.public-recipes"
            case .telegram: return "account.section.telegram"
            case .reminders: return "account.section.reminders"
            }
        }
    }

    private func makeProfileScrollCtaHandler(proxy: ScrollViewProxy) -> FeatureAdoptionProfileScrollCtaHandler {
        FeatureAdoptionProfileScrollCtaHandler(
            openTelegramSection: {
                withAnimation { proxy.scrollTo(AccountViewSection.telegram.id, anchor: .top) }
            },
            openPublicProfileSection: {
                withAnimation { proxy.scrollTo(AccountViewSection.publicRecipes.id, anchor: .top) }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                    legacyAuthBannerSection
                    featureAdoptionSection
                    publicRecipesSection
                        .id(AccountViewSection.publicRecipes.id)
                    preferencesSection
                    timerNotificationsSection
                    remindersSyncSection
                        .id(AccountViewSection.reminders.id)
                    telegramSection
                        .id(AccountViewSection.telegram.id)
                    dataSection
                    if authService.isAuthenticated {
                        dangerZoneSection
                    }

                    if let statusMessage = viewModel.statusMessage {
                        Section {
                            Text(statusMessage)
                                .appFootnote()
                                .foregroundStyle(.secondary)
                        }
                    }

                    footerSection
                    logExportSection

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
                .environment(
                    \.featureAdoptionProfileScrollCta,
                    makeProfileScrollCtaHandler(proxy: proxy)
                )
                .navigationDestination(isPresented: $showRemindersListPicker) {
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
                }
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
                .alert(
                    Bundle.currentLocalizedString("account.delete.warning.title"),
                    isPresented: $showingDeleteWarning
                ) {
                    Button(Bundle.currentLocalizedString("account.delete.warning.continue"), role: .destructive) {
                        pendingDeleteSeedSheet = true
                    }
                    Button(Bundle.currentLocalizedString("account.delete.warning.cancel"), role: .cancel) { }
                } message: {
                    Text(Bundle.currentLocalizedString("account.delete.warning.body"))
                }
                .onChange(of: showingDeleteWarning) { _, isPresented in
                    guard !isPresented, pendingDeleteSeedSheet else { return }
                    pendingDeleteSeedSheet = false
                    showingDeleteSeedSheet = true
                }
                .sheet(isPresented: $showingDeleteSeedSheet) {
                    AccountDeleteSeedSheet(
                        isDeleting: isDeletingAccount,
                        onDelete: { seedPhrase in
                            isDeletingAccount = true
                            let error = await viewModel.deleteAccount(
                                seedPhrase: seedPhrase,
                                syncService: syncService
                            )
                            isDeletingAccount = false
                            if error == nil {
                                showingDeleteSeedSheet = false
                            }
                            return error
                        }
                    )
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
                    await viewModel.refresh(syncService: syncService)
                    viewModel.loadRemindersLists(remindersService: remindersService)
                    await featureAdoptionStore.refresh()
                    refreshTick += 1
                }
                .task {
                    featureAdoptionStore.loadFromCache()
                    await featureAdoptionStore.refresh()
                    await viewModel.refresh(syncService: syncService)
                    appLanguage = .current
                    await consumePendingRemindersSetupIfNeeded(scrollProxy: proxy)
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
                .onChange(of: coordinator.pendingRemindersSetup) { _, isPending in
                    guard isPending else { return }
                    Task { @MainActor in
                        await consumePendingRemindersSetupIfNeeded(scrollProxy: proxy)
                    }
                }
            }
        }
    }

    @MainActor
    private func consumePendingRemindersSetupIfNeeded(scrollProxy: ScrollViewProxy) async {
        guard coordinator.pendingRemindersSetup else { return }
        coordinator.clearPendingRemindersSetup()
        ShoppingRemindersTipPreferences.dismiss()

        withAnimation {
            scrollProxy.scrollTo(AccountViewSection.reminders.id, anchor: .top)
        }

        await viewModel.setRemindersSyncEnabled(
            true,
            syncService: syncService,
            remindersService: remindersService
        )

        guard viewModel.remindersSyncEnabled else { return }
        viewModel.loadRemindersLists(remindersService: remindersService)
        showRemindersListPicker = true
    }

    // MARK: - Sections

    @ViewBuilder
    private var legacyAuthBannerSection: some View {
        if let userId = authService.userId {
            Section {
                LegacyAuthBannerView(userId: userId, refreshTick: refreshTick)
            }
        }
    }

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
                refreshTick: refreshTick,
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

        } header: {
            AppSectionHeader("account.section.preferences")
        }
        .appListSectionHeaderStyle()
    }

    @ViewBuilder
    private var timerNotificationsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.timerNotificationsEnabled },
                set: { value in
                    Task { @MainActor in await viewModel.setTimerNotificationsEnabled(value) }
                }
            )) {
                Text("account.timer-notifications.label").appBody()
            }
            .disabled(viewModel.timerNotificationsDenied)
            .accessibilityIdentifier(AccessibilityIdentifiers.accountTimerNotificationsToggle)
        } header: {
            AppSectionHeaderSpacer()
        } footer: {
            if viewModel.timerNotificationsDenied {
                Text("account.timer-notifications.denied")
                    .appFootnote()
            } else {
                Text("account.timer-notifications.footer")
                    .appFootnote()
            }
        }
        .appListSectionHeaderStyle()
    }

    @ViewBuilder
    private var remindersSyncSection: some View {
        Section {
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
        } footer: {
            if viewModel.remindersSyncDenied {
                Text("account.reminders.denied")
                    .appFootnote()
            } else {
                Text("account.reminders.sync.footer")
                    .appFootnote()
            }
        }
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
        } header: {
            AppSectionHeader("account.section.data")
        }
        .appListSectionHeaderStyle()
    }

    /// Spec 055: separate Danger Zone section (not inside data management).
    @ViewBuilder
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteWarning = true
            } label: {
                Text("account.delete.title")
                    .appBody()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.deleteAccountButton)
        } header: {
            AppSectionHeader("account.danger-zone")
        } footer: {
            Text("account.delete.description")
                .appFootnote()
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
            NavigationLink {
                SyncStatusContent(
                    connectionState: syncService.connectionState,
                    connectionTransport: syncService.connectionTransport,
                    imageCacheStatus: syncService.imageCacheStatus,
                    recipeDocumentCacheStatus: syncService.recipeDocumentCacheStatus,
                    onRetryImageDownload: { syncService.retryImagePrefetch() },
                    onRetryRecipeDocumentsDownload: { syncService.retryRecipeDocumentsBatchLoad() },
                    onForceReconnect: { syncService.forceReconnect() }
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

            if hasDebugLogFile, let url = AppLog.currentLogFileURL() {
                ShareLink(item: url) {
                    Label {
                        Text("account.export.logs.title")
                            .appBody()
                    } icon: {
                        AppSymbol.image("square.and.arrow.up")
                    }
                }

                Button {
                    AppLog.clearLogFiles()
                    hasDebugLogFile = false
                } label: {
                    Label {
                        Text("account.export.logs.clear")
                            .appBody()
                    } icon: {
                        AppSymbol.image("trash")
                    }
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.accountClearLogs)
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
        .onAppear {
            hasDebugLogFile = AppLog.currentLogFileURL() != nil
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        Section {
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

private struct AccountDeleteSeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var seedPhrase = ""
    @State private var errorMessage: String?

    let isDeleting: Bool
    /// Returns `nil` on success (parent dismisses sheet); otherwise a localized
    /// error shown in the footer while the sheet stays open.
    let onDelete: (String) async -> String?

    private var isPhraseValid: Bool {
        seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).count == 12
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("account.delete.seed.body")
                        .appBody()
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextEditor(text: $seedPhrase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 96)
                        .font(AppTypography.mono(AppTypography.bodySize))
                        .accessibilityIdentifier(AccessibilityIdentifiers.deleteAccountSeedInput)
                } header: {
                    AppSectionHeader("account.delete.seed.label")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .appFootnote()
                            .foregroundStyle(.red)
                            .accessibilityIdentifier(AccessibilityIdentifiers.deleteAccountError)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("common.cancel")
                    }
                    .disabled(isDeleting)
                    .accessibilityIdentifier(AccessibilityIdentifiers.deleteAccountCancelButton)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { @MainActor in
                            errorMessage = nil
                            if let error = await onDelete(seedPhrase) {
                                errorMessage = error
                            }
                        }
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("account.delete.seed.confirm")
                        }
                    }
                    .disabled(!isPhraseValid || isDeleting)
                    .accessibilityIdentifier(AccessibilityIdentifiers.deleteAccountConfirmButton)
                }
            }
        }
        .interactiveDismissDisabled(isDeleting)
        .appOpaqueSheetPresentationPlain()
    }
}

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
                                .appBody()
                            if let seed = try? authService.getSeedPhrase() {
                                Text(seed)
                                    .font(AppTypography.mono(AppTypography.bodySize))
                                    .lineSpacing(AppTypography.bodyLineSpacing)
                                    .textSelection(.enabled)
                                ShareLink(item: seed) {
                                    Label {
                                        Text("account.seed.copy").appBody()
                                    } icon: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                }
                                SeedQRCodeView(text: seed)
                            } else {
                                Text("account.no-seed")
                                    .appBody()
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
                                .appBody()
                        } else {
                            Text("account.seed.unlock-hint")
                                .appBody()
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
    let store = try! YDocStore.inMemory()
    let sync = YjsSyncService(store: store)
    let coordinator = AppShellCoordinator(syncService: sync, deepLinkRouter: DeepLinkRouter())
    return NavigationStack {
        AccountView()
            .environment(coordinator)
    }
}
#endif
