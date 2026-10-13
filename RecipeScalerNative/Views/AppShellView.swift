//
//  AppShellView.swift
//  RecipeScalerNative
//

import RecipeScalerCore
import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Hashable {
    case discover
    case importTab
    case recipes
    case shopping
    case profile
    case assistant

    var title: LocalizedStringKey {
        switch self {
        case .discover: "discover.nav.discover"
        case .importTab: "discover.nav.import"
        case .recipes: "discover.nav.my-recipes"
        case .shopping: "discover.nav.shopping"
        case .profile: "discover.nav.profile"
        case .assistant: "assistant.title"
        }
    }

    /// Outline SF Symbol for `tabItem`. UITabBar draws the filled variant on the selected tab.
    /// Do not use `.fill` here — some glyphs (e.g. `square.and.arrow.down.fill`) do not exist and break tab icons.
    var tabBarSymbol: String {
        switch self {
        case .discover: "globe"
        case .importTab: "square.and.arrow.down"
        case .recipes: "book"
        case .shopping: "cart"
        case .profile: "person"
        case .assistant: "sparkles"
        }
    }

    /// Accessibility identifier applied to the `AppTabBarLabel` (the actual
    /// tab-bar button), so XCUITest can target `tab_discover` etc. directly.
    /// The modifier on `tabRoot(...)` in `tabView` does NOT propagate to the
    /// UITabBarButton — it lands on an inner container — so we attach it here
    /// on the label view instead.
    var accessibilityId: String {
        switch self {
        case .discover: AccessibilityIdentifiers.tabDiscover
        case .importTab:
            // Spec 074 — Import tab removed from the bar. The case survives
            // only for the DEBUG `-OpenTab=import` launch argument; this slug
            // is never attached to live UI.
            "debug-import"
        case .recipes: AccessibilityIdentifiers.tabRecipes
        case .shopping: AccessibilityIdentifiers.tabShopping
        case .profile: AccessibilityIdentifiers.tabProfile
        case .assistant: AccessibilityIdentifiers.tabAssistant
        }
    }
}

struct AppTabBarLabel: View {
    let tab: AppTab
    /// Another glyph for this bar (spec 081: the iPad top bar). `nil` — `tab.tabBarSymbol`.
    var systemImage: String?

    var body: some View {
        Label(tab.title, systemImage: systemImage ?? tab.tabBarSymbol)
            .font(AppTypography.tabBar)
            .accessibilityIdentifier(tab.accessibilityId)
    }
}

/// Red new-content dot (spec 072 US4) overlaid on the Discover tab icon.
/// `feedBadgeStore` is injected — tab labels are measured as bar items; after
/// assistant dismiss iOS 26 uses a fallback environment and
/// `@Environment(FeedBadgeStore.self)` traps.
struct FeedBadgeTabLabel: View {
    let feedBadgeStore: FeedBadgeStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppTabBarLabel(tab: .discover)
            if feedBadgeStore.hasNew {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .offset(x: 8, y: -6)
            }
        }
    }
}

struct AppShellView: View {
    @Bindable private var coordinator: AppShellCoordinator
    @Environment(YjsSyncService.self) private var syncService
    @Environment(AuthService.self) private var authService
    @Environment(TimerManager.self) private var timerManager
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext
    @Environment(VkusvillSettingsStore.self) private var vkusvillSettings
    @Environment(OfflineBannerGate.self) private var offlineGate
    @Environment(FeedBadgeStore.self) private var feedBadgeStore
    @Environment(ClipboardImportStore.self) private var clipboardImport
    @Environment(ReleaseNotesStore.self) private var releaseNotes
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appLayoutMode) private var layoutMode
    /// The assistant is open: the phone sheet, or the iPad panel in a wide window
    /// (spec 081, T032) — one flag for both, so a size class change keeps it open.
    @State private var showAssistant = false
    @State private var assistantContextRecipeId: String?
    @State private var assistantOpenRequest: AssistantOpenRequest?
    /// Spec 078 — shake open payload delivered into the presented sheet.
    @State private var assistantShakeOpenRequest: AssistantShakeOpenRequest?
    /// PI-5 on the iPad panel (spec 081): an external request was routed in the current
    /// update, so an «Ассистент» tap of the same update must not toggle the panel shut.
    /// Cleared on the next main-actor turn.
    @State private var externalRequestRoutedInThisUpdate = false
    /// `layoutMode == .padRegular`, for the sheet binding's setter (spec 081): SwiftUI
    /// dismisses a sheet through the binding it was presented with, and that binding's
    /// closure sees the environment of its own update, not the current one.
    @State private var assistantShowsAsPanel = false
    @State private var transientStatus: TransientStatusPayload?
    @State private var transientStatusDismissTask: Task<Void, Never>?
    @State private var mobileTimerPanelCollapsed = true
    /// Spec 081 (T038, spike S6) — the timers popover over the capsule in a wide iPad
    /// window. Shell state: a `.popover` inside `tabViewBottomAccessory` never shows.
    @State private var timerPopoverShown = false
    /// `layoutMode == .padRegular` on the iPadOS 26.2+ shell, for the capsule binding's
    /// setter (it must see the current window, not the one of the update that built it).
    @State private var timersShowAsPopover = false
    /// Where the capsule (`tabViewBottomAccessory`) and the popover anchor are. Not
    /// observed: see `TimerPopoverGeometry`.
    @State private var timerPopoverGeometry = TimerPopoverGeometry()
    /// The capsule in the anchor's space: the popover points at it wherever the sidebar
    /// moves it (S6, `s6-06`). Taken when the popover opens and while it is shown.
    @State private var timerPopoverAnchorRect: CGRect = .zero
    #if DEBUG
    /// `-MobileTimerPanelExpanded=1` in a wide iPad window: the popover, once the capsule
    /// has a frame to point at.
    @State private var debugTimerPopoverPending = false
    #endif
    /// Spec 074 — TabView selection decoupled from `coordinator.selectedTab` so the
    /// fake assistant tab (`Color.clear`) never becomes the hosted tab root after a
    /// tap or dismiss (fixes shell chrome / safe-area corruption after sheet dismiss).
    @State private var tabViewSelection: AppTab = .recipes
    @State private var tabBarTopOffsetFromLayoutBottom: CGFloat = 0
    @State private var clipboardBannerHeight: CGFloat = 0
    @State private var clipboardImportPresentTask: Task<Void, Never>?
    @State private var inboundClipboardFinishTask: Task<Void, Never>?
    @Namespace private var mobileTimerPanelChevronNamespace

    /// Глобальный zoom-session для hero-фотографий (spec 064). `@State` +
    /// не-Observable holder, чтобы pinch/scroll ticks не пересобирали TabView.
    /// Overlay и сам hero подписаны на `context` через `@ObservedObject`.
    @State private var heroPhotoZoomSession = HeroPhotoZoomSession()

    /// Spec 081 (T032a) — owned by `AppContainer`; shared by the sheet and the iPad panel.
    private let assistantSession: AssistantSessionModel

    init(coordinator: AppShellCoordinator, assistantSession: AssistantSessionModel) {
        _coordinator = Bindable(wrappedValue: coordinator)
        self.assistantSession = assistantSession
    }

    /// Resolved from the environment's `AppContainer` (composition root owns
    /// teardown wiring); nil in previews/tests, where logout skips container
    /// teardown instead of touching a global.
    @Environment(\.appContainer) private var appContainer

    private var performLogoutTeardown: () async -> Void {
        let container = appContainer
        return {
            guard let container else { return }
            await container.sync.clearSessionForLogout()
            await container.stopForLogout()
        }
    }

    /// Spec 066 — ignore connection flaps while backgrounded; reset so lock
    /// time does not expire the banner delay (US1).
    private func applyOfflineBannerGate(for phase: ScenePhase) {
        switch phase {
        case .background:
            offlineGate.update(isNotConnected: false)
        case .active:
            applyOfflineBannerGate(isNotConnected: !syncService.connectionState.isConnected)
        default:
            break
        }
    }

    private func applyOfflineBannerGate(isNotConnected: Bool) {
        guard scenePhase == .active else { return }
        offlineGate.update(isNotConnected: isNotConnected)
    }

    private var mobileTimerPanelCollapsedBinding: Binding<Bool> {
        Binding(
            get: { mobileTimerPanelCollapsed },
            set: { newValue in
                withAnimation(MobileTimerPanelLayout.toggleAnimation) {
                    mobileTimerPanelCollapsed = newValue
                }
            }
        )
    }

    /// Routes a queued external assistant request only after the shell exists.
    /// The coordinator consumes the exact request id, so a newer request cannot
    /// be accidentally cleared by a delayed presentation callback.
    private func routePendingAssistantOpenRequest() {
        guard let request = coordinator.pendingAssistantOpenRequest else { return }
        coordinator.consumeAssistantOpenRequest(request)
        externalRequestRoutedInThisUpdate = true
        Task { @MainActor in
            externalRequestRoutedInThisUpdate = false
        }
        // Already open (the panel, or a tab open of the same update): hand the request
        // over now. The view's `onChange` would miss it when the view is built with it,
        // and the session deduplicates by request id.
        if showAssistant {
            assistantSession.receiveExternalRequest(request)
        }
        assistantOpenRequest = request
        assistantShakeOpenRequest = nil
        assistantContextRecipeId = nil
        markAssistantOpen()
        presentAssistant()
    }

    /// Spec 081 (T032a) — a real open starts the shared session from a clean
    /// slate (what a freshly built sheet did). Already open: the visible
    /// sheet/panel receives the new request through its `onChange`.
    /// `startsNewChat`: ✦ on the iPad «Покупки» / «Подборки» (FR-021).
    private func presentAssistant(startsNewChat: Bool = false) {
        if !showAssistant {
            assistantSession.beginPresentation(
                openRequest: assistantOpenRequest,
                shakeRequest: assistantShakeOpenRequest,
                startsNewChat: startsNewChat
            )
        }
        showAssistant = true
    }

    /// Before `showAssistant` flips: the recipe under the sheet must already see itself
    /// covered when it leaves the screen. The iPad panel stands beside it (T036).
    private func markAssistantOpen() {
        assistantRecipeContext.assistantDidOpen(asPanel: layoutMode == .padRegular)
    }

    /// Spec 081 (T036) — another section beside the open panel hides the recipe: the
    /// composer stops offering it (the shell's copy of its id too) and the screen may sleep
    /// again. The recipe view, hidden, turns its own cooking mode off on `onDisappear`.
    private func releaseRecipe(hiddenBy tab: AppTab) {
        guard assistantRecipeContext.releaseRecipe(hiddenBy: tab) else { return }
        assistantContextRecipeId = nil
        ScreenAwakeController.deactivate()
    }

    /// Spec 074 — manual open (tab-bar entry, FAB replacement, adoption CTA).
    /// Manual open carries no external payload; `assistantOpenRequest` is reset
    /// so a stale request from a previous presentation cannot leak in.
    private func openAssistantManually(startsNewChat: Bool = false) {
        assistantOpenRequest = nil
        assistantShakeOpenRequest = nil
        assistantContextRecipeId = assistantRecipeContext.visibleRecipeId
        markAssistantOpen()
        presentAssistant(startsNewChat: startsNewChat)
        resyncTabViewSelectionAfterAssistantInteraction()
    }

    /// Spec 078 — shake-to-open: attach visible recipe when present, else new chat + voice.
    private func routePendingShakeAssistantOpenRequest() {
        guard let request = coordinator.pendingShakeAssistantOpenRequest else { return }
        coordinator.consumeShakeAssistantOpenRequest(request)
        guard ShakeToOpenAssistantPreference.isActive(idiom: UIDevice.current.userInterfaceIdiom) else {
            return
        }
        assistantOpenRequest = nil
        assistantShakeOpenRequest = request
        assistantContextRecipeId = request.attachRecipeId ?? assistantRecipeContext.visibleRecipeId
        markAssistantOpen()
        presentAssistant()
        resyncTabViewSelectionAfterAssistantInteraction()
    }

    private func handleDeviceShake() {
        guard scenePhase == .active else { return }
        guard ShakeToOpenAssistantPreference.isActive(idiom: UIDevice.current.userInterfaceIdiom) else {
            return
        }
        guard DeviceShakeDetector.shouldAcceptShake() else { return }
        coordinator.requestShakeAssistantOpen(
            visibleRecipeId: assistantRecipeContext.visibleRecipeId
        )
    }

    /// Spec 081 (T032) — the assistant stands beside the tabs as a panel only in a
    /// wide iPad window; otherwise the same `showAssistant` presents the sheet.
    private var showsAssistantPanel: Bool {
        showAssistant && layoutMode == .padRegular
    }

    /// Spec 081 (T032) — the panel's ×. Does what the sheet's `onDismiss` does, which
    /// a panel never gets. Also closes the iPhone sheet (logout, `assistantSessionEpoch`).
    private func closeAssistantPanel() {
        showAssistant = false
        assistantContextRecipeId = nil
        assistantShakeOpenRequest = nil
        assistantOpenRequest = nil
        resyncTabViewSelectionAfterAssistantInteraction()
    }

    /// Keep TabView on the real tab; the assistant entry is a fake tab (sheet only).
    private func resyncTabViewSelectionAfterAssistantInteraction() {
        let tab = coordinator.selectedTab
        guard tab != .assistant else { return }
        tabViewSelection = tab
        #if DEBUG
        AgentSyncDebugLog.assistantLayout(
            hypothesisId: "H1",
            location: "AppShellView.resyncTabViewSelection",
            message: "tab_view_selection_resynced",
            data: ["tab": tab.rawValue]
        )
        #endif
    }

    /// Spec 040 — handlers for CTA taps in `FeatureAdoptionGuideView`.
    /// These are the app-level actions (tab switch, sheet, external Safari).
    /// The in-Profile scroll actions live in `AccountView` under a separate
    /// environment key (`featureAdoptionProfileScrollCta`) so the two never
    /// override each other.
    private func makeFeatureAdoptionAppCtaHandler() -> FeatureAdoptionAppCtaHandler {
        FeatureAdoptionAppCtaHandler(
            openAssistant: {
                Task { @MainActor in
                    openAssistantManually()
                }
            },
            openImport: {
                Task { @MainActor in
                    // Spec 074 — Import tab removed from the bar; the CTA
                    // presents the sheet directly over the current tab.
                    coordinator.presentImport()
                }
            },
            openSafari: { url in
                Task { @MainActor in
                    UIApplication.shared.open(url)
                }
            }
        )
    }

    var body: some View {
        shellObservers
            .environment(coordinator)
            .environment(
                \.featureAdoptionAppCta,
                makeFeatureAdoptionAppCtaHandler()
            )
            // Spec 081 (US6): the menu bar and its shortcuts, iPad only.
            .focusedSceneValue(\.appCommands, appCommandActions)
    }

    // MARK: - iPad menu bar (spec 081, US6, T045)

    /// The «Файл» and «Вид» commands; `nil` on the iPhone, which gets no new shortcuts.
    /// Each is the path of the phone's own button.
    private var appCommandActions: AppCommandActions? {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return nil }
        let isEditingRecipe = coordinator.recipeEdit != nil
        var newCollection: (() -> Void)?
        if #available(iOS 26.2, *) {
            newCollection = { coordinator.requestNewCollection() }
        }
        var focusSearch: (() -> Void)?
        if #available(iOS 18.0, *), !isEditingRecipe {
            focusSearch = { focusRecipeSearchFromKeyboard() }
        }
        return AppCommandActions(
            selectTab: { coordinator.selectTabFromKeyboard($0) },
            toggleAssistant: { toggleAssistantFromKeyboard() },
            newRecipe: isEditingRecipe ? nil : { Task { await coordinator.createRecipeFromKeyboard() } },
            importRecipe: { coordinator.presentImport() },
            newCollection: newCollection,
            focusSearch: focusSearch
        )
    }

    /// ⌘J: the «Ассистент» tab — it opens the assistant and, in a wide window, closes the
    /// panel. The sheet of a narrow window closes as its swipe down would.
    private func toggleAssistantFromKeyboard() {
        coordinator.isProfileSheetPresented = false
        if showAssistant, layoutMode != .padRegular {
            closeAssistantPanel()
            return
        }
        coordinator.handleTabSelection(.assistant)
    }

    /// ⌘F: «Рецепты» with the focus in the search field of the list on screen. In a wide
    /// window the list comes back first: the recipe collapses («Свернуть») and a panel
    /// that hides the list beside an open recipe (FR-022) closes.
    private func focusRecipeSearchFromKeyboard() {
        if layoutMode == .padRegular {
            if coordinator.recipeDetailExpanded {
                withAnimation(.easeInOut(duration: 0.25)) {
                    coordinator.setRecipeDetailExpanded(false, isPadRegular: true)
                }
            }
            if showsAssistantPanel,
               RecipesSelection.selection(from: coordinator.recipesPath).recipeId != nil {
                closeAssistantPanel()
            }
        }
        coordinator.requestRecipeSearchFocus()
    }

    /// `body` split: SwiftUI type-checker chokes on the full modifier chain
    /// (AppShellView body is one of the widest in the app), so overlays/sheets
    /// and lifecycle observers live in separate computed views.

    /// Tab bar height fallback until UIKit layout publishes a measured value.
    private static var fallbackTabBarTopOffsetFromLayoutBottom: CGFloat {
        49
    }

    private var clipboardBannerBottomPadding: CGFloat {
        let timerHeight = MobileTimerPanelLayout.height(
            timerCount: timerManager.timers.count,
            isExpanded: !mobileTimerPanelCollapsed
        )
        let tabBarOffset = tabBarTopOffsetFromLayoutBottom > 0
            ? tabBarTopOffsetFromLayoutBottom
            : Self.fallbackTabBarTopOffsetFromLayoutBottom
        // Spec 074 — no FAB; banner sits above tab bar + timer panel only.
        return tabBarOffset + timerHeight + ClipboardImportBannerLayout.bottomGap
    }

    private var clipboardEvaluateContext: ClipboardImportEvaluateContext {
        ClipboardImportEvaluateContext(
            hasSession: authService.isAuthenticated,
            isURLImportAvailable: isClipboardURLImportAvailable,
            isImportSheetPresented: coordinator.importPresentation != nil,
            hasPendingInboundImport: coordinator.inboundClipboardSuppressed
                || coordinator.pendingSpotlightRecipeId != nil
                || DeepLinkRouter.hasPendingRecipeId()
                || deepLinkRouter.pending != nil,
            isTransientToastVisible: transientStatus != nil
        )
    }

    private var isClipboardURLImportAvailable: Bool {
        switch syncService.connectionState {
        case .connected, .connecting, .reconnecting:
            return true
        case .disconnected, .error:
            return false
        }
    }

    private func evaluateClipboardImport() {
        let context = clipboardEvaluateContext
        Task { await clipboardImport.evaluate(context: context) }
    }

    private func presentClipboardImport() {
        clipboardImportPresentTask?.cancel()
        let generation = clipboardImport.evaluateGeneration
        clipboardImportPresentTask = Task {
            guard let seed = await clipboardImport.seedTextForImport() else { return }
            guard !Task.isCancelled else { return }
            guard generation == clipboardImport.evaluateGeneration else { return }
            guard authService.isAuthenticated else { return }
            coordinator.presentImport(
                seedText: seed,
                autoSubmit: true,
                consumesClipboard: true
            )
        }
    }

    private func armInboundClipboardSuppressionIfNeeded() {
        if DeepLinkRouter.hasPendingRecipeId() || deepLinkRouter.pending != nil {
            coordinator.beginInboundClipboardSuppression()
        }
    }

    private func scheduleEndInboundClipboardSuppression() {
        guard coordinator.inboundClipboardSuppressed else { return }
        inboundClipboardFinishTask?.cancel()
        inboundClipboardFinishTask = Task { @MainActor in
            coordinator.endInboundClipboardSuppression()
            evaluateClipboardImport()
        }
    }

    private var isClipboardBannerVisible: Bool {
        if transientStatus != nil { return false }
        if case .visible = clipboardImport.bannerState { return true }
        return false
    }

    @ViewBuilder
    private var bottomStatusOverlays: some View {
        if let transientStatus {
            TransientStatusBanner(
                message: transientStatus.message,
                symbolName: transientStatus.symbolName,
                kind: transientStatus.kind
            )
            .frame(maxWidth: .infinity)
            .padding(.bottom, 72)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if clipboardImport.bannerState == .visible {
            ClipboardImportBanner(
                onImport: presentClipboardImport,
                onDismiss: {
                    clipboardImport.dismissVisible()
                }
            )
            .padding(.horizontal, ClipboardImportBannerLayout.horizontalInset)
            .padding(.bottom, clipboardBannerBottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func importSheet(_ presentation: ImportPresentation) -> some View {
        ImportRecipeSheet(
            seedText: presentation.seedText,
            autoSubmit: presentation.autoSubmit
        ) { result in
            if presentation.consumesClipboard {
                clipboardImport.markConsumed()
            }
            if let message = coordinator.completeImport(result) {
                postTransientStatus(message)
            }
        }
    }

    /// Spec 081 (T032, plan.md Р7) — the assistant panel stands beside the `TabView`, not
    /// `.inspector` on it (that zeroes the top safe area of the tabs, spike S5). The panel
    /// lives at the shell level, so it survives tab switches. On the iPhone the `HStack`
    /// holds the tab view alone.
    private var shellWithOverlays: some View {
        HStack(spacing: 0) {
            tabView
                .environment(\.heroPhotoZoomContext, heroPhotoZoomSession.context)
                .background {
                    TabBarTopOffsetReader(offsetFromLayoutBottom: $tabBarTopOffsetFromLayoutBottom)
                }
                .heroPhotoZoomOverlay(heroPhotoZoomSession.context)
                .overlay(alignment: .bottom) {
                    bottomStatusOverlays
                }
            if showsAssistantPanel {
                assistantPanel
            }
        }
        .animation(.snappy, value: showsAssistantPanel)
        .onChange(of: layoutMode, initial: true) { _, mode in
            assistantShowsAsPanel = mode == .padRegular
            assistantRecipeContext.assistantDidMove(asPanel: mode == .padRegular)
        }
            .onPreferenceChange(ClipboardBannerHeightKey.self) { clipboardBannerHeight = $0 }
            .onChange(of: isClipboardBannerVisible) { _, visible in
                if !visible {
                    clipboardBannerHeight = 0
                }
            }
            .animation(
                .easeInOut(duration: ClipboardImportBannerLayout.appearDuration),
                value: isClipboardBannerVisible
            )
            .animation(.easeInOut(duration: 0.25), value: transientStatus != nil)
            .sheet(item: $coordinator.importPresentation, content: importSheet)
            .sheet(isPresented: Binding(
                get: { releaseNotes.isSheetPresented },
                set: { releaseNotes.isSheetPresented = $0 }
            )) {
                ReleaseNotesSheet()
                    .environment(releaseNotes)
            }
            .modifier(AssistantSheetModifier(
                // A wide iPad window shows the panel instead (T032).
                isPresented: Binding(
                    get: { showAssistant && layoutMode != .padRegular },
                    set: { isPresented in
                        // The sheet also goes away when the window turns regular and
                        // the chat moves into the panel (T032a): that is not a close.
                        if !isPresented, assistantShowsAsPanel { return }
                        showAssistant = isPresented
                    }
                ),
                contextRecipeId: assistantContextRecipeId ?? assistantRecipeContext.visibleRecipeId,
                openRequest: assistantOpenRequest,
                shakeOpenRequest: assistantShakeOpenRequest,
                onDismiss: {
                    #if DEBUG
                    // #region agent log
                    AgentSyncDebugLog.assistantLayout(
                        hypothesisId: "H1",
                        location: "AppShellView.assistantOnDismiss",
                        message: "assistant_sheet_onDismiss",
                        data: [
                            "selectedTab": coordinator.selectedTab.rawValue,
                            "showAssistant": showAssistant ? "true" : "false"
                        ]
                    )
                    AgentSyncDebugLog.logNavigationBarState(
                        hypothesisId: "H2",
                        location: "AppShellView.assistantOnDismiss",
                        tag: "sheet_onDismiss"
                    )
                    // #endregion
                    #endif
                    // Spec 081 (T032a): the sheet also goes away when the iPad
                    // window turns regular and the chat moves into the panel —
                    // that is not a close. Any other dismissal with the flag still
                    // set (the shell torn down under an open sheet) is one.
                    if showAssistant, assistantShowsAsPanel { return }
                    assistantRecipeContext.assistantDidClose()
                    assistantContextRecipeId = nil
                    assistantShakeOpenRequest = nil
                    // A request of a closed chat must not block the next tab open (PI-5 guard).
                    assistantOpenRequest = nil
                    resyncTabViewSelectionAfterAssistantInteraction()
                },
                session: assistantSession,
                environmentCoordinator: coordinator,
                syncService: syncService,
                offlineGate: offlineGate,
                assistantRecipeContext: assistantRecipeContext
            ))
    }
    /// Spec 081 (T032) — the assistant panel: the sheet's chat (shared session, T032a)
    /// with the panel chrome (T033), 340 pt behind a hairline.
    private var assistantPanel: some View {
        HStack(spacing: 0) {
            Divider()
                .ignoresSafeArea()
            AssistantSheet(
                session: assistantSession,
                // The recipe beside the panel stays visible and can change.
                contextRecipeId: assistantRecipeContext.visibleRecipeId ?? assistantContextRecipeId,
                openRequest: assistantOpenRequest,
                shakeOpenRequest: assistantShakeOpenRequest,
                syncService: syncService,
                presentation: .inspector,
                onClose: closeAssistantPanel
            )
            .environment(coordinator)
            .environment(offlineGate)
            .environment(assistantRecipeContext)
            .frame(width: IPadLayoutMetrics.inspectorWidth)
            .accessibilityElement(children: .contain)
        }
        .transition(.move(edge: .trailing))
    }

    /// Lifecycle observers, split into small chains so the SwiftUI
    /// type-checker can handle each expression.
    private var shellObservers: some View {
        clipboardObservers(on: assistantObservers(on: transientStatusObservers(on: navigationObservers(on: shellWithOverlays))))
            .onAppear {
                tabViewSelection = coordinator.selectedTab
                RecipeImageDiskCache.migrateFromCachesIfNeeded()
                armInboundClipboardSuppressionIfNeeded()
                // Spec 059 fix: on cold launch iOS delivers the Universal Link URL
                // during splash, before `AppShellView` mounts. `onChange(pending)`
                // cannot observe a value that was already set, so a queued link
                // would be silently dropped and the app opened on the default tab.
                // Drain any pre-existing pending link once on appear.
                if let link = deepLinkRouter.pending {
                    coordinator.handleDeepLink(link)
                }
                // Spec 066 — arm gate from the current state; `onChange` above does
                // not fire for a value already set before this view mounted (cold
                // start already offline), so without this the banner would never appear.
                applyOfflineBannerGate(for: scenePhase)
                routePendingAssistantOpenRequest()
                evaluateClipboardImport()
                scheduleEndInboundClipboardSuppression()
            }
            #if DEBUG
            .onAppear {
                coordinator.openDebugTabIfNeeded(DebugLaunchOptions.openTab)
                if DebugLaunchOptions.mobileTimerPanelExpanded {
                    if usesTimerPopover {
                        debugTimerPopoverPending = true
                    } else {
                        mobileTimerPanelCollapsed = false
                    }
                }
                if DebugLaunchOptions.showAssistant {
                    openAssistantManually()
                }
                coordinator.consumePendingRecipeIdIfNeeded()
                evaluateClipboardImport()
                scheduleEndInboundClipboardSuppression()
            }
            #else
            .onAppear {
                coordinator.consumePendingRecipeIdIfNeeded()
                evaluateClipboardImport()
                scheduleEndInboundClipboardSuppression()
            }
            #endif
    }

    private func clipboardObservers(on base: some View) -> some View {
        base
            .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
                evaluateClipboardImport()
            }
            .onChange(of: coordinator.importPresentation?.id) { _, _ in
                evaluateClipboardImport()
            }
            .onChange(of: transientStatus != nil) { _, _ in
                evaluateClipboardImport()
            }
            .onChange(of: coordinator.inboundClipboardSuppressed) { _, suppressed in
                if !suppressed {
                    evaluateClipboardImport()
                }
            }
            .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                if !isAuthenticated {
                    clipboardImportPresentTask?.cancel()
                }
            }
    }

    private func assistantObservers(on base: some View) -> some View {
        base
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                handleDeviceShake()
            }
            .onChange(of: coordinator.pendingAssistantOpenRequest) { _, _ in
                routePendingAssistantOpenRequest()
            }
            .onChange(of: coordinator.pendingShakeAssistantOpenRequest) { _, _ in
                routePendingShakeAssistantOpenRequest()
            }
            .onChange(of: coordinator.pendingAssistantTabOpen) { _, isPending in
                guard isPending else { return }
                let startsNewChat = coordinator.pendingAssistantTabOpenStartsNewChat
                coordinator.consumeAssistantTabOpen()
                // Spec 081 (FR-021): the tab and ✦ toggle the iPad panel. An external
                // request of the same update (routed already, or still queued) keeps
                // it open with that request (PI-5).
                if layoutMode == .padRegular, showAssistant {
                    guard !externalRequestRoutedInThisUpdate,
                          coordinator.pendingAssistantOpenRequest == nil
                    else { return }
                    closeAssistantPanel()
                    return
                }
                // PI-5: if an external request was routed in the same SwiftUI
                // transaction (both onChange handlers fire before the render),
                // it already set `assistantOpenRequest` and the sheet will
                // present its payload. A manual open would nil it out and the
                // message would be silently lost — skip the manual open.
                guard assistantOpenRequest == nil else { return }
                openAssistantManually(startsNewChat: startsNewChat)
            }
            .onChange(of: coordinator.selectedTab) { _, newTab in
                releaseRecipe(hiddenBy: newTab)
                guard newTab != .assistant else { return }
                tabViewSelection = newTab
            }
            .onChange(of: coordinator.assistantSessionEpoch) { _, _ in
                // Logout or account switch (`resetShellStateForLogout`) while the shell
                // stays: the sheet or panel closes, as the profile and import sheets do.
                guard showAssistant else { return }
                closeAssistantPanel()
            }
            .onChange(of: showAssistant) { _, isOpen in
                if isOpen {
                    markAssistantOpen()
                } else {
                    assistantRecipeContext.assistantDidClose()
                    assistantSession.close()
                }
                #if DEBUG
                // #region agent log
                AgentSyncDebugLog.assistantLayout(
                    hypothesisId: "H1",
                    location: "AppShellView.showAssistant",
                    message: "assistant_sheet_visibility",
                    data: [
                        "isOpen": isOpen ? "true" : "false",
                        "selectedTab": coordinator.selectedTab.rawValue,
                        "tabViewSelection": tabViewSelection.rawValue
                    ]
                )
                if !isOpen {
                    AgentSyncDebugLog.logNavigationBarState(
                        hypothesisId: "H2",
                        location: "AppShellView.showAssistant",
                        tag: "sheet_closed"
                    )
                }
                // #endregion
                #endif
            }
    }

    private func transientStatusObservers(on base: some View) -> some View {
        base
            .onReceive(NotificationCenter.default.publisher(for: .shoppingStatusMessage)) { notification in
                let payload: TransientStatusPayload?
                if let typed = notification.object as? TransientStatusPayload {
                    payload = typed
                } else if let message = notification.object as? String, !message.isEmpty {
                    payload = TransientStatusPayload(message: message)
                } else {
                    payload = nil
                }
                guard let payload, !payload.message.isEmpty else { return }
                transientStatusDismissTask?.cancel()
                withAnimation(.easeInOut(duration: 0.25)) {
                    transientStatus = payload
                }
                let shown = payload
                transientStatusDismissTask = Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if transientStatus == shown {
                            transientStatus = nil
                        }
                    }
                }
            }
    }

    private func navigationObservers(on base: some View) -> some View {
        base
            .onChange(of: coordinator.pendingFileImportToast) { _, newValue in
                guard let newValue else { return }
                postTransientStatus(newValue)
                coordinator.pendingFileImportToast = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRecipeRequested)) { _ in
                coordinator.consumePendingRecipeIdIfNeeded()
            }
            .onChange(of: deepLinkRouter.pending) { _, link in
                if link != nil {
                    coordinator.beginInboundClipboardSuppression()
                }
                guard let link else {
                    evaluateClipboardImport()
                    return
                }
                coordinator.handleDeepLink(link)
                evaluateClipboardImport()
                scheduleEndInboundClipboardSuppression()
            }
            .onChange(of: syncService.connectionState) { _, newState in
                applyOfflineBannerGate(isNotConnected: !newState.isConnected)
                evaluateClipboardImport()
            }
            .onChange(of: scenePhase) { _, phase in
                applyOfflineBannerGate(for: phase)
                if phase == .active {
                    evaluateClipboardImport()
                }
            }
    }

    private var mobileTimerPanel: some View {
        MobileTimerPanel(timerManager: timerManager, isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .legacy)
            .environment(timerManager)
    }

    private var mobileTimerPanelAccessory: some View {
        MobileTimerPanel(timerManager: timerManager, isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .accessoryCollapsed)
            .environment(timerManager)
            .environment(\.mobileTimerPanelChevronNamespace, mobileTimerPanelChevronNamespace)
    }

    private var mobileTimerPanelExpandedInset: some View {
        MobileTimerPanel(timerManager: timerManager, isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .insetExpanded)
            .environment(timerManager)
            .environment(\.mobileTimerPanelChevronNamespace, mobileTimerPanelChevronNamespace)
    }

    /// Spec 081 (T038) — iPadOS 26.2+ in a wide window: a tap on the capsule shows the
    /// timers in a popover over it, not the expanded panel. The phone and a compact iPad
    /// window expand the panel, as before.
    private var usesTimerPopover: Bool {
        guard #available(iOS 26.2, *) else { return false }
        return UIDevice.current.userInterfaceIdiom == .pad && layoutMode == .padRegular
    }

    /// The iPad capsule: in a wide window «expand» opens the popover instead. While the
    /// popover is shown a tap on the capsule lands in its dismiss region and closes it, so
    /// the capsule only ever opens it.
    private var iPadTimerAccessoryCollapsedBinding: Binding<Bool> {
        Binding(
            get: { mobileTimerPanelCollapsed },
            set: { collapsed in
                if !collapsed, timersShowAsPopover {
                    showTimerPopover()
                } else {
                    mobileTimerPanelCollapsedBinding.wrappedValue = collapsed
                }
            }
        )
    }

    private func showTimerPopover() {
        #if DEBUG
        debugTimerPopoverPending = false
        #endif
        timerPopoverAnchorRect = timerPopoverGeometry.anchorRect
        timerPopoverShown = true
    }

    /// The panel's chevron, a compact window, or the capsule gone. A tap outside closes the
    /// popover through its binding.
    private func closeTimerPopover() {
        timerPopoverShown = false
        #if DEBUG
        // `-MobileTimerPanelExpanded=1` asked for the popover in the window and with the
        // capsule it launched with, not for one that comes back later.
        debugTimerPopoverPending = false
        #endif
    }

    /// The popover follows the capsule while it is shown (a sidebar toggle, a rotation).
    private func followTimerCapsule() {
        guard timerPopoverShown else { return }
        let rect = timerPopoverGeometry.anchorRect
        if !rect.isApproximatelyEqual(to: timerPopoverAnchorRect) {
            timerPopoverAnchorRect = rect
        }
    }

    /// The phone capsule plus its frame for the popover anchor (iPad only, so the
    /// iPhone accessory stays as it was).
    private var iPadTimerAccessory: some View {
        MobileTimerPanel(timerManager: timerManager, isCollapsed: iPadTimerAccessoryCollapsedBinding, presentation: .accessoryCollapsed)
            .environment(timerManager)
            .environment(\.mobileTimerPanelChevronNamespace, mobileTimerPanelChevronNamespace)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                // The accessory is rebuilt on every shell update and measures off-window
                // first, at the origin: keep the last frame in the window.
                guard frame.origin != .zero, !frame.isEmpty else { return }
                timerPopoverGeometry.accessoryFrame = frame
                followTimerCapsule()
                #if DEBUG
                if debugTimerPopoverPending {
                    showTimerPopover()
                }
                #endif
            }
    }

    /// An invisible point at the tab view's corner; the popover is attached to the
    /// capsule's frame in its space, with the arrow down to the capsule (S6). A point, so
    /// the popover's host view covers nothing.
    private var timerPopoverAnchor: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onGeometryChange(for: CGPoint.self) { proxy in
                proxy.frame(in: .global).origin
            } action: { origin in
                timerPopoverGeometry.anchorOrigin = origin
                followTimerCapsule()
            }
            .popover(
                isPresented: $timerPopoverShown,
                attachmentAnchor: .rect(.rect(timerPopoverAnchorRect)),
                arrowEdge: .bottom
            ) {
                timerPopoverContent
            }
    }

    /// The phone's expanded panel, unchanged; its header chevron folds it, here it closes
    /// the popover.
    private var timerPopoverContent: some View {
        MobileTimerPanel(
            timerManager: timerManager,
            isCollapsed: Binding(
                get: { false },
                set: { collapsed in
                    if collapsed { closeTimerPopover() }
                }
            ),
            presentation: .insetExpanded
        )
        .environment(timerManager)
        .frame(width: IPadLayoutMetrics.timersPopoverWidth)
        .presentationCompactAdaptation(.sheet)
    }

    private var showsMobileTimerPanelAccessory: Bool {
        !timerManager.suppressPanelSafeAreaInset
            && !timerManager.activeTimers.isEmpty
            && mobileTimerPanelCollapsed
    }

    private var showsMobileTimerPanelExpandedInset: Bool {
        if #available(iOS 26.2, *) {
            return !timerManager.suppressPanelSafeAreaInset
                && !timerManager.activeTimers.isEmpty
                && !mobileTimerPanelCollapsed
        }
        return false
    }

    /// Spec 074 — dual TabView. The new `Tab { }` API cannot be mixed with the
    /// legacy `.tabItem` style in one TabView (type-checker fails), so the shell
    /// has two builders:
    ///  - iOS 26.2+: trailing `Tab(role: .search)` (Liquid Glass slot) → sheet;
    ///    no `.searchable` / no morph — fake selection via `handleTabSelection`.
    ///  - iOS < 26.2 (incl. 26.0/26.1): legacy fake tab (`Color.clear`) → sheet.
    ///    The modern path's timer panel (`tabViewBottomAccessory` / `safeAreaBar`)
    ///    only exists on 26.2+, so earlier 26.x must stay on the legacy builder
    ///    or its timer panel would silently disappear.
    @ViewBuilder
    private var tabView: some View {
        if #available(iOS 26.2, *) {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadTabView
            } else {
                modernTabView
            }
        } else {
            legacyTabView
        }
    }

    /// Spec 081 — the iPad shell: sidebar, top bar or the phone bottom bar in compact.
    /// The iPhone's timer capsule (it exists in the sidebar mode too, spike S6); in a wide
    /// window a tap on it opens the timers popover instead of the expanded panel (T038).
    @available(iOS 26.2, *)
    private var iPadTabView: some View {
        IPadAdaptiveTabView(
            coordinator: coordinator,
            syncService: syncService,
            feedBadgeStore: feedBadgeStore,
            tabRoots: tabRoots
        )
        .animation(MobileTimerPanelLayout.toggleAnimation, value: mobileTimerPanelCollapsed)
        .modifier(MobileTimerAccessoryModifier(
            isEnabled: showsMobileTimerPanelAccessory,
            accessory: iPadTimerAccessory
        ))
        .overlay(alignment: .topLeading) { timerPopoverAnchor }
        .onChange(of: layoutMode, initial: true) { _, mode in
            timersShowAsPopover = mode == .padRegular
            if mode == .padRegular {
                // A wide window has no expanded panel: the capsule and its popover.
                if !mobileTimerPanelCollapsed {
                    mobileTimerPanelCollapsed = true
                }
            } else {
                // A compact window is the phone: a tap on the capsule expands the panel.
                closeTimerPopover()
            }
        }
        .onChange(of: showsMobileTimerPanelAccessory) { _, shown in
            // No capsule (the last timer ended, edit mode): nothing to point at.
            if !shown {
                closeTimerPopover()
            }
        }
    }

    @available(iOS 26.2, *)
    private var modernTabView: some View {
        modernTabBar
            .animation(MobileTimerPanelLayout.toggleAnimation, value: mobileTimerPanelCollapsed)
            .modifier(MobileTimerAccessoryModifier(
                isEnabled: showsMobileTimerPanelAccessory,
                accessory: mobileTimerPanelAccessory
            ))
    }

    @available(iOS 26.2, *)
    private var modernTabBar: some View {
        TabView(selection: modernTabSelection) {
            Tab(value: AppTab.discover) {
                tabRoots.discover()
            } label: {
                FeedBadgeTabLabel(feedBadgeStore: feedBadgeStore)
            }

            Tab(value: AppTab.recipes) {
                tabRoots.recipes()
            } label: {
                AppTabBarLabel(tab: .recipes)
            }

            Tab(value: AppTab.shopping) {
                tabRoots.shopping()
            } label: {
                AppTabBarLabel(tab: .shopping)
            }

            Tab(value: AppTab.profile) {
                tabRoots.profile()
            } label: {
                AppTabBarLabel(tab: .profile)
            }

            // Spec 074 — fake assistant tab (sheet only). Without `role: .search`:
            // iOS 26.2+ search slot corrupts nav chrome after sheet dismiss.
            Tab(value: AppTab.assistant) {
                Color.clear
            } label: {
                AppTabBarLabel(tab: .assistant)
                    .accessibilityIdentifier(AccessibilityIdentifiers.tabAssistant)
            }
        }
    }

    @available(iOS 26.2, *)
    private var modernTabSelection: Binding<AppTab> {
        Binding(
            get: { tabViewSelection },
            set: { newTab in
                if newTab == .assistant {
                    openAssistantManually()
                    return
                }
                tabViewSelection = newTab
                coordinator.handleTabSelection(newTab)
            }
        )
    }

    /// Spec 081 (Q1) — on an iPad below iOS 26.2 the profile is a form sheet in a wide
    /// window too; the iPhone keeps the bare tab bar.
    @ViewBuilder
    private var legacyTabView: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            legacyTabBar
                .modifier(IPadProfileSheetModifier(
                    coordinator: coordinator,
                    auth: authService,
                    timer: timerManager,
                    vkusvillSettings: vkusvillSettings,
                    performLogoutTeardown: performLogoutTeardown
                ))
        } else {
            legacyTabBar
        }
    }

    private var legacyTabBar: some View {
        TabView(selection: tabSelection) {
            tabRoot(DiscoverRootView(
                    path: $coordinator.discoverPath,
                    feedBadgeStore: feedBadgeStore,
                    coordinator: coordinator
                )) { FeedBadgeTabLabel(feedBadgeStore: feedBadgeStore) }
                .tag(AppTab.discover)
                .accessibilityIdentifier(AccessibilityIdentifiers.tabDiscover)

            tabRoot(RecipeListView(
                navigationPath: $coordinator.recipesPath,
                syncService: syncService,
                coordinator: coordinator,
                assistantRecipeContext: assistantRecipeContext,
                timerManager: timerManager,
                apiClient: appContainer?.api ?? .shared,
                appContainer: appContainer,
                systemBannerStore: appContainer?.systemBanner ?? SystemBannerStore(),
                mobileTimerPanelIsCollapsed: mobileTimerPanelCollapsed,
                scenePhase: scenePhase
            )) {
                AppTabBarLabel(tab: .recipes)
            }
            .tag(AppTab.recipes)
            .accessibilityIdentifier(AccessibilityIdentifiers.tabRecipes)

            tabRoot(ShoppingListView(
                    path: $coordinator.shoppingPath,
                    syncService: syncService,
                    timerManager: timerManager,
                    coordinator: coordinator,
                    authService: authService,
                    vkusvillSettings: vkusvillSettings,
                    mobileTimerPanelIsCollapsed: mobileTimerPanelCollapsed
                )) {
                AppTabBarLabel(tab: .shopping)
            }
            .tag(AppTab.shopping)
            .accessibilityIdentifier(AccessibilityIdentifiers.tabShopping)

            tabRoot(AccountView(
                auth: authService,
                timer: timerManager,
                vkusvillSettings: vkusvillSettings,
                performLogoutTeardown: performLogoutTeardown
            )) {
                AppTabBarLabel(tab: .profile)
            }
            .tag(AppTab.profile)
            .accessibilityIdentifier(AccessibilityIdentifiers.tabProfile)

            tabRoot(Color.clear) { AppTabBarLabel(tab: .assistant) }
                .tag(AppTab.assistant)
                .accessibilityIdentifier(AccessibilityIdentifiers.tabAssistant)
        }
    }

    /// Timer panel between tab content and tab bar (must be on tab root, not on `TabView` — otherwise tab bar is hidden).
    /// On iOS < 26.2 — manual `safeAreaInset(.bottom)` with opaque `systemBackground`.
    /// On iOS 26.2+ — collapsed mini player via `.tabViewBottomAccessory` on `TabView`;
    /// expanded list via `safeAreaBar` on each tab root (accessory slot is single-row only).
    ///
    /// Stable hierarchy rule: the bottom bar is always applied on iOS 26.2+ (content is empty when collapsed).
    /// Switching `if/else` between inset and plain content recreates the `List` subtree
    /// and resets scroll position when toggling collapsed↔expanded.
    ///
    /// iOS 26 `safeAreaBar` (vs `safeAreaInset`) drives the system scroll-edge fade and,
    /// crucially, propagates the bottom inset into nested `List`/`ScrollView` inside
    /// `NavigationStack` so the last rows stay visible above the expanded panel.
    @ViewBuilder
    private func tabRoot<Content: View, Label: View>(
        _ content: Content,
        @ViewBuilder tabItem: () -> Label
    ) -> some View {
        let rooted = content
            .environment(\.mobileTimerPanelIsCollapsed, mobileTimerPanelCollapsed)

        if #available(iOS 26.2, *) {
            rooted
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    if showsMobileTimerPanelExpandedInset {
                        mobileTimerPanelExpandedInset
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .tabItem { tabItem() }
        } else {
            // Keep `safeAreaInset` always attached on iOS 18.x. Toggling inset on/off when
            // `suppressPanelSafeAreaInset` changes (recipe edit mode) recreated the tab subtree
            // and reset `YDocRecipeDetailView` `@State` (`isEditing` back to false).
            rooted
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !timerManager.suppressPanelSafeAreaInset {
                        mobileTimerPanel
                    }
                }
                .tabItem { tabItem() }
        }
    }

    /// Tab roots shared with the iPad shell (spec 081, T013).
    private var tabRoots: AppShellTabRoots {
        AppShellTabRoots(
            coordinator: coordinator,
            syncService: syncService,
            authService: authService,
            timerManager: timerManager,
            assistantRecipeContext: assistantRecipeContext,
            vkusvillSettings: vkusvillSettings,
            feedBadgeStore: feedBadgeStore,
            appContainer: appContainer,
            scenePhase: scenePhase,
            performLogoutTeardown: performLogoutTeardown,
            mobileTimerPanelCollapsed: mobileTimerPanelCollapsed,
            mobileTimerPanelCollapsedBinding: mobileTimerPanelCollapsedBinding,
            showsMobileTimerPanelExpandedInset: showsMobileTimerPanelExpandedInset,
            mobileTimerPanelChevronNamespace: mobileTimerPanelChevronNamespace,
            assistantPanelOpen: showsAssistantPanel
        )
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { tabViewSelection },
            set: { newTab in
                if newTab == .assistant {
                    openAssistantManually()
                    return
                }
                tabViewSelection = newTab
                coordinator.handleTabSelection(newTab)
            }
        )
    }
    private func postTransientStatus(_ message: String) {
        NotificationCenter.default.post(name: .shoppingStatusMessage, object: message)
    }
}


private struct TabBarTopOffsetReader: UIViewControllerRepresentable {
    @Binding var offsetFromLayoutBottom: CGFloat

    func makeUIViewController(context: Context) -> TabBarTopOffsetReaderViewController {
        let controller = TabBarTopOffsetReaderViewController()
        controller.onOffsetChange = { newValue in
            guard offsetFromLayoutBottom != newValue else { return }
            offsetFromLayoutBottom = newValue
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: TabBarTopOffsetReaderViewController, context: Context) {
        uiViewController.onOffsetChange = { newValue in
            guard offsetFromLayoutBottom != newValue else { return }
            offsetFromLayoutBottom = newValue
        }
        uiViewController.view.setNeedsLayout()
    }
}

/// Resolves the `UITabBarController` hosting a window's root view-controller
/// hierarchy. Caches the resolved controller and only re-runs the recursive
/// search when the cached reference is missing (controller deallocated) or its
/// `parent` has changed (modal presentation / reparenting), so a stable layout
/// does not walk the view-controller hierarchy on every `viewDidLayoutSubviews`.
///
/// `search` is injectable so tests can count traversals without polluting
/// production code with test hooks.
final class TabBarDiscovery {
    private weak var cached: UITabBarController?
    private var cachedParent: UIViewController?
    private let search: (UIViewController?) -> UITabBarController?

    init(search: @escaping (UIViewController?) -> UITabBarController? = TabBarDiscovery.find) {
        self.search = search
    }

    func resolve(root: UIViewController?) -> UITabBarController? {
        if let cached, cached.parent === cachedParent {
            return cached
        }
        let resolved = search(root)
        cached = resolved
        cachedParent = resolved?.parent
        return resolved
    }

    static func find(in viewController: UIViewController?) -> UITabBarController? {
        guard let viewController else { return nil }
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        for child in viewController.children {
            if let tabBarController = find(in: child) {
                return tabBarController
            }
        }
        if let presented = viewController.presentedViewController,
           let tabBarController = find(in: presented) {
            return tabBarController
        }
        return nil
    }
}

private final class TabBarTopOffsetReaderViewController: UIViewController {
    var onOffsetChange: ((CGFloat) -> Void)?
    private let tabBarDiscovery = TabBarDiscovery()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        publishOffsetIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        publishOffsetIfNeeded()
    }

    private func publishOffsetIfNeeded() {
        guard let window = view.window,
              let tabBar = tabBarDiscovery.resolve(root: window.rootViewController)?.tabBar else { return }
        let tabBarFrame = tabBar.convert(tabBar.bounds, to: window)
        let offsetFromWindowBottom = window.bounds.height - tabBarFrame.minY
        let offsetFromLayoutBottom = offsetFromWindowBottom - window.safeAreaInsets.bottom
        guard offsetFromLayoutBottom > 0 else { return }
        onOffsetChange?(offsetFromLayoutBottom)
    }
}

/// Spec 081 (T038) — the capsule's and the timers popover anchor's frames in the window.
/// A plain class in `@State`, so a write does not update the shell: the capsule
/// (`tabViewBottomAccessory`) is rebuilt on every shell update and measures off-window
/// first, so a state write per measurement updated the shell in a loop and hung the app.
private final class TimerPopoverGeometry {
    var accessoryFrame: CGRect = .zero
    var anchorOrigin: CGPoint = .zero

    /// The capsule in the anchor's space.
    var anchorRect: CGRect {
        accessoryFrame.offsetBy(dx: -anchorOrigin.x, dy: -anchorOrigin.y)
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

/// Spec 074 — availability-isolated `tabViewBottomAccessory` (iOS 26.2+). The
/// modern TabView gate in `AppShellView.tabView` is also 26.2+, so the `else`
/// branch here is unreachable in production and exists for type-checking only.
private struct MobileTimerAccessoryModifier<Accessory: View>: ViewModifier {
    let isEnabled: Bool
    let accessory: Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.2, *) {
            content
                .tabViewBottomAccessory(isEnabled: isEnabled) {
                    accessory
                }
        } else {
            content
        }
    }
}

/// Spec 074 — assistant sheet for all iOS versions (fake tab entry).
private struct AssistantSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let contextRecipeId: String?
    let openRequest: AssistantOpenRequest?
    let shakeOpenRequest: AssistantShakeOpenRequest?
    let onDismiss: () -> Void
    let session: AssistantSessionModel
    let environmentCoordinator: AppShellCoordinator
    let syncService: YjsSyncService
    let offlineGate: OfflineBannerGate
    let assistantRecipeContext: AssistantRecipeContext

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                AssistantSheet(
                    session: session,
                    contextRecipeId: contextRecipeId,
                    openRequest: openRequest,
                    shakeOpenRequest: shakeOpenRequest,
                    syncService: syncService
                )
                .environment(environmentCoordinator)
                .environment(offlineGate)
                .environment(assistantRecipeContext)
                .appOpaqueSheetPresentationPlain()
            }
    }
}
