import SwiftUI

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
