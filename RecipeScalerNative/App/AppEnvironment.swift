import SwiftUI
import RecipeScalerCore

// MARK: - AppContainer

extension EnvironmentValues {
    @Entry var appContainer: AppContainer? = nil
}

// MARK: - Per-service environment keys (for views that want direct injection)

extension EnvironmentValues {
    @Entry var authService: AuthService? = nil
    @Entry var timerManager: TimerManager? = nil
    @Entry var deepLinkRouter: DeepLinkRouter? = nil
    @Entry var assistantRecipeContext: AssistantRecipeContext? = nil
    @Entry var discoverListState: DiscoverListStateStore? = nil
    /// APIClient for feature views / view models that need direct REST access.
    /// Defaults to `.shared` so previews and tests without an `AppContainer`
    /// keep working; production wiring installs the container's client via
    /// `.appEnvironment(_:)` (composition-root single source of truth).
    @Entry var apiClient: APIClient = .shared
}

// MARK: - Convenience view extension

extension View {
    /// Installs `AppContainer` plus every `@Observable` service for SwiftUI observation.
    func appEnvironment(_ container: AppContainer) -> some View {
        self
            .environment(\.appContainer, container)
            .environment(\.authService, container.auth)
            .environment(\.timerManager, container.timer)
            .environment(\.deepLinkRouter, container.deepLinkRouter)
            .environment(\.assistantRecipeContext, container.assistantRecipeContext)
            .environment(\.discoverListState, container.discoverListState)
            .environment(\.apiClient, container.api)
            .environment(container.auth)
            .environment(container.timer)
            .environment(container.deepLinkRouter)
            .environment(container.assistantRecipeContext)
            .environment(container.sync)
            .environment(container.reminders)
            .environment(container.spotlight)
            .environment(container.featureAdoption)
            .environment(container.systemBanner)
    }
}
