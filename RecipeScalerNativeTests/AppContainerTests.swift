import SwiftData
import XCTest
@testable import RecipeScalerNative

/// Verifies the AppContainer composition root (review #27):
/// - All 12 singleton-backed services are constructed and reachable.
/// - Construction is dependency-ordered (no crashes from missing deps).
/// - `bootstrap(userId:)` is idempotent and re-runnable.
@MainActor
final class AppContainerTests: XCTestCase {

    private func makeContainer() throws -> AppContainer {
        let modelContainer = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(modelContainer)
        return try AppContainer(modelContext: context)
    }

    func test_containerConstruction_buildsFullDependencyGraph() throws {
        let container = try makeContainer()

        // Foundation
        XCTAssertNotNil(container.database)
        XCTAssertNotNil(container.store)
        XCTAssertNotNil(container.mapStore)

        // Leaf services
        XCTAssertNotNil(container.imageCache)
        XCTAssertNotNil(container.publicImageCache)
        XCTAssertNotNil(container.yjsMergeHelper)
        XCTAssertNotNil(container.assistantRecipeContext)
        XCTAssertNotNil(container.deepLinkRouter)
        XCTAssertNotNil(container.timerLiveActivityCoordinator)
        XCTAssertNotNil(container.tips)

        // Networked
        XCTAssertNotNil(container.auth)
        XCTAssertNotNil(container.pushSchedule)
        XCTAssertNotNil(container.pushRegistration)
        XCTAssertNotNil(container.timerSync)
        XCTAssertNotNil(container.timer)
        XCTAssertNotNil(container.recipeImage)

        // Sync subsystem
        XCTAssertNotNil(container.sync)
        XCTAssertNotNil(container.reminders)
        XCTAssertNotNil(container.spotlight)
    }

    func test_container_setsProcessWideSharedHandle() throws {
        let previous = AppContainer.shared
        defer { AppContainer.setShared(previous) }

        let container = try makeContainer()
        XCTAssertTrue(AppContainer.shared === container)
    }

    func test_bootstrap_isIdempotentForSameUser() async throws {
        let container = try makeContainer()
        let userId = "test-user-\(UUID().uuidString)"

        await container.bootstrap(userId: userId)
        // Second call with the same user should not crash and should resume the session.
        await container.bootstrap(userId: userId)
    }

    func test_bootstrap_switchesUserWithoutCrash() async throws {
        let container = try makeContainer()
        let first = "test-user-\(UUID().uuidString)"
        let second = "test-user-\(UUID().uuidString)"

        await container.bootstrap(userId: first)
        await container.bootstrap(userId: second)
    }

    func test_stopForLogout_resetsShellCoordinator() async throws {
        let container = try makeContainer()
        container.shellCoordinator.selectedTab = .shopping
        container.shellCoordinator.recipesPath.append(
            RecipesRoute.folder(CollectionVirtualFolders.allRecipesFolderId)
        )
        container.deepLinkRouter.handle(.openHome)

        await container.stopForLogout()

        XCTAssertEqual(container.shellCoordinator.selectedTab, .recipes)
        XCTAssertTrue(container.shellCoordinator.recipesPath.isEmpty)
        XCTAssertNil(container.deepLinkRouter.pending)
    }


    func test_sharedShim_resolvesToContainerInstance() throws {
        let previous = AppContainer.shared
        defer { AppContainer.setShared(previous) }

        let container = try makeContainer()
        XCTAssertTrue(AuthService.shared === container.auth)
        XCTAssertTrue(TimerManager.shared === container.timer)
        XCTAssertTrue(DeepLinkRouter.shared === container.deepLinkRouter)
        XCTAssertTrue(TimerLiveActivityCoordinator.shared === container.timerLiveActivityCoordinator)
        XCTAssertTrue(PushScheduleService.shared === container.pushSchedule)
        XCTAssertTrue(PushRegistrationService.shared === container.pushRegistration)
        XCTAssertTrue(TimerSyncService.shared === container.timerSync)
        XCTAssertTrue(YjsMergeHelper.shared === container.yjsMergeHelper)
        XCTAssertTrue(AssistantRecipeContext.shared === container.assistantRecipeContext)
    }

    func test_tipProductCatalog_matchesAppStoreContract() {
        XCTAssertEqual(
            TipProductID.oneTime.map(\.rawValue),
            [
                "ru.recipescaler.tip.1",
                "ru.recipescaler.tip.2",
                "ru.recipescaler.tip.5",
                "ru.recipescaler.tip.10"
            ]
        )
        XCTAssertEqual(TipProductID.monthly.rawValue, "ru.recipescaler.support.monthly")
        XCTAssertEqual(Set(TipProductID.oneTime).count, 4)
        XCTAssertFalse(TipProductID.oneTime.contains(.monthly))
    }
}
