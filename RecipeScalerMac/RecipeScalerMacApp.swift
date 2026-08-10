import CoreSpotlight
import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@main
struct RecipeScalerMacApp: App {
    @State private var container: AppContainer

    init() {
        AppLanguagePreference.bootstrap()
        AppFonts.registerBundledFontsIfNeeded()
        AppChromeAppearance.configure()

        let modelContext = ModelContext(Self.sharedModelContainer)
        do {
            container = try AppContainer(modelContext: modelContext)
        } catch {
            fatalError("Cannot initialize AppContainer: \(error)")
        }
    }

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([RecipeTimer.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [inMemory])
        }
    }()

    var body: some Scene {
        WindowGroup {
            MacRootView(container: container)
                .appEnvironment(container)
                .environment(\.interactionProfile, .pointer)
                .onOpenURL { url in
                    DeepLinkRouter.handle(url)
                }
                .modelContainer(Self.sharedModelContainer)
        }
        .defaultSize(width: MacWindowMetrics.defaultWidth, height: MacWindowMetrics.defaultHeight)
        .commands {
            MacAppCommands()
        }
    }
}

extension Notification.Name {
    static let macTabRequested = Notification.Name("RecipeScalerMac.tabRequested")
    static let macImportRequested = Notification.Name("RecipeScalerMac.importRequested")
    static let macAssistantRequested = Notification.Name("RecipeScalerMac.assistantRequested")
}

struct MacAppCommands: Commands {
    var body: some Commands {
        SidebarCommands()

        CommandMenu("app.actions") {
            Button("discover.nav.discover") {
                NotificationCenter.default.post(
                    name: .macTabRequested,
                    object: AppTab.discover
                )
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("discover.nav.import") {
                NotificationCenter.default.post(name: .macImportRequested, object: nil)
            }
            .keyboardShortcut("2", modifiers: .command)

            // Keep the positional tab shortcut above and expose the standard
            // mnemonic alias as well. Both routes use the same notification
            // bridge, so Import cannot diverge by entry point.
            Button("discover.nav.import") {
                NotificationCenter.default.post(name: .macImportRequested, object: nil)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("discover.nav.my-recipes") {
                NotificationCenter.default.post(
                    name: .macTabRequested,
                    object: AppTab.recipes
                )
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("discover.nav.shopping") {
                NotificationCenter.default.post(
                    name: .macTabRequested,
                    object: AppTab.shopping
                )
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("discover.nav.profile") {
                NotificationCenter.default.post(
                    name: .macTabRequested,
                    object: AppTab.profile
                )
            }
            .keyboardShortcut("5", modifiers: .command)

            Divider()

            Button("assistant.title") {
                NotificationCenter.default.post(name: .macAssistantRequested, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
        }
    }
}

struct MacRootView: View {
    @Bindable private var coordinator: AppShellCoordinator
    @Environment(AuthService.self) private var authService
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(YjsSyncService.self) private var syncService
    @AppStorage(AppThemePreference.storageKey) private var appThemeRaw = AppThemePreference.system.rawValue
    @AppStorage(AppLanguagePreference.storageKey) private var appLanguageRaw: String?
    @State private var showAssistant = false
    @State private var assistantContextRecipeId: String?

    private let container: AppContainer

    private var appLanguage: AppLanguagePreference {
        if let raw = appLanguageRaw, let value = AppLanguagePreference(rawValue: raw) {
            return value
        }
        return AppLanguagePreference.current
    }

    init(container: AppContainer) {
        self.container = container
        _coordinator = Bindable(wrappedValue: container.shellCoordinator)
    }

    var body: some View {
        Group {
            if authService.isAuthenticated {
                RegularAppShell(
                    coordinator: coordinator,
                    showAssistant: $showAssistant,
                    assistantContextRecipeId: $assistantContextRecipeId
                )
            } else {
                MacAuthView()
            }
        }
        .environment(\.interactionProfile, .pointer)
        .environment(\.font, AppTypography.body)
        .preferredColorScheme(
            (AppThemePreference(rawValue: appThemeRaw) ?? .system).colorScheme
        )
        .environment(
            \.locale,
            appLanguage.locale
        )
        .overlay {
            MacWindowConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .sheet(item: $coordinator.importPresentation) { _ in
            MacImportSheet()
        }
        .sheet(isPresented: $showAssistant, onDismiss: {
            assistantRecipeContext.isAssistantSheetOpen = false
            assistantContextRecipeId = nil
        }) {
            MacAssistantView(
                contextRecipeId: assistantContextRecipeId ?? assistantRecipeContext.visibleRecipeId
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .macImportRequested)) { _ in
            guard authService.isAuthenticated else { return }
            coordinator.presentImport()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macTabRequested)) { notification in
            guard authService.isAuthenticated,
                  let tab = notification.object as? AppTab else { return }
            coordinator.handleSidebarSelection(tab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macAssistantRequested)) { _ in
            guard authService.isAuthenticated else { return }
            assistantContextRecipeId = assistantRecipeContext.visibleRecipeId
            assistantRecipeContext.isAssistantSheetOpen = true
            showAssistant = true
        }
        .onAppear {
            coordinator.setRegularLayout(
                authService.isAuthenticated,
                entries: syncService.collectionEntries
            )
#if DEBUG
            if authService.isAuthenticated {
                coordinator.openDebugTabIfNeeded(DebugLaunchOptions.openTab)
                if DebugLaunchOptions.showAssistant {
                    assistantContextRecipeId = assistantRecipeContext.visibleRecipeId
                    assistantRecipeContext.isAssistantSheetOpen = true
                    showAssistant = true
                }
                coordinator.consumePendingRecipeIdIfNeeded()
            }
#endif
            handlePendingDeepLinkIfNeeded()
            coordinator.resolvePendingSpotlightRecipe(in: syncService.collectionEntries)
        }
        .onChange(of: deepLinkRouter.pending) { _, link in
            guard authService.isAuthenticated, link != nil else { return }
            handlePendingDeepLinkIfNeeded()
        }
        .onChange(of: syncService.collectionEntries) { _, entries in
            coordinator.resolvePendingSpotlightRecipe(in: entries)
        }
        .task(id: authService.userId) {
            guard let userId = authService.userId, authService.isAuthenticated else { return }
            await container.bootstrap(userId: userId)
        }
        .onChange(of: authService.isAuthenticated) { _, authenticated in
            coordinator.setRegularLayout(
                authenticated,
                entries: syncService.collectionEntries
            )
            guard !authenticated else {
                handlePendingDeepLinkIfNeeded()
                return
            }
            Task { await container.stopForLogout() }
        }
    }

    private func handlePendingDeepLinkIfNeeded() {
        guard let link = deepLinkRouter.pending else { return }
        coordinator.handleDeepLink(link)
    }
}

private enum MacWindowMetrics {
    static let defaultWidth: CGFloat = 1280
    static let defaultHeight: CGFloat = 800
    static let minimumWidth: CGFloat = 960
    static let minimumHeight: CGFloat = 640
}

private struct MacWindowConfigurator: NSViewRepresentable {
    final class Coordinator {
        var didConfigureMinSize = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(window: nsView.window, coordinator: context.coordinator)
    }

    private func configure(window: NSWindow?, coordinator: Coordinator) {
        guard let window, !coordinator.didConfigureMinSize else { return }
        coordinator.didConfigureMinSize = true
        window.minSize = CGSize(
            width: MacWindowMetrics.minimumWidth,
            height: MacWindowMetrics.minimumHeight
        )
    }
}

private struct MacAuthView: View {
    @Environment(AuthService.self) private var authService
    @State private var seedPhrase = ""
    @State private var isEnteringSeed = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppSurface.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("auth.welcome-title")
                    .font(AppTypography.display(AppTypography.authTitleSize))
                Text("auth.welcome-subtitle")
                    .appBody()
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage)
                        .appFootnote()
                        .foregroundStyle(.red)
                        .frame(maxWidth: 420)
                }

                if isEnteringSeed {
                    TextEditor(text: $seedPhrase)
                        .frame(width: 420, height: 120)
                        .padding(8)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.35)))
                        .appBodyFieldTypography()

                    HStack {
                        Button("common.cancel") {
                            isEnteringSeed = false
                        }
                        .buttonStyle(.borderless)

                        Button("auth.login") {
                            Task { await login() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }
                } else {
                    Button("auth.new-user") {
                        Task { await register() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                    Button("auth.used-before") {
                        isEnteringSeed = true
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
                }

                if isLoading {
                    ProgressView()
                }
            }
            .frame(maxWidth: 480)
            .padding(40)
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.authRoot)
    }

    private func register() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await authService.registerAuto()
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func login() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await authService.loginWithSeed(seedPhrase)
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }
}

private struct MacImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            Text("import.title")
                .font(AppTypography.title2)
            Text("import.mac.description")
                .appBody()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let statusMessage {
                Text(statusMessage)
                    .appFootnote()
                    .foregroundStyle(.secondary)
            }

            Button("import.select-file") {
                isImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting)
            .accessibilityIdentifier(AccessibilityIdentifiers.importFilePickButton)

            Button("common.cancel") {
                dismiss()
            }
            .buttonStyle(.borderless)
        }
        .frame(width: 460, height: 260)
        .padding(28)
        .accessibilityIdentifier(AccessibilityIdentifiers.importSheet)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.data, .archive]
        ) { result in
            guard case .success(let url) = result else { return }
            Task { await importFile(url) }
        }
    }

    private func importFile(_ url: URL) async {
        isImporting = true
        defer { isImporting = false }
        var didCompleteImport = false
        statusMessage = await container.shellCoordinator.fileImportCoordinator?.importFile(
            at: url,
            isOnline: container.sync.connectionState.isConnected,
            onComplete: { result in
                didCompleteImport = result?.importedCount ?? 0 > 0
            }
        )
        if didCompleteImport {
            dismiss()
        }
    }
}
