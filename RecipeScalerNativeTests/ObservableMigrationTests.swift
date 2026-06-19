import Combine
import XCTest
@testable import RecipeScalerCore
@testable import RecipeScalerNative

/// Verifies that the seven ObservableObject types listed in review #28 now use the
/// `@Observable` macro (or have had vestigial `ObservableObject` conformance removed).
@MainActor
final class ObservableMigrationTests: XCTestCase {

    /// All seven types must now conform to `Observable` (or, for `APIClient`, neither
    /// `Observable` nor `ObservableObject` — its conformance was vestigial).
    func test_migratedTypes_conformToObservable() {
        let stubStore = makeStubStore()
        let sync = YjsSyncService(store: stubStore)

        XCTAssertTrue(isObservable(sync), "YjsSyncService must be @Observable")
        XCTAssertTrue(
            isObservable(RemindersSyncService(mapStore: makeStubMapStore())),
            "RemindersSyncService must be @Observable"
        )
        XCTAssertTrue(
            isObservable(SpotlightIndexer(syncService: sync)),
            "SpotlightIndexer must be @Observable"
        )
        XCTAssertTrue(
            isObservable(RecipeListViewModel(syncService: sync)),
            "RecipeListViewModel must be @Observable"
        )
        XCTAssertTrue(
            isObservable(DescriptionEditorBridge(recipeId: "test", syncService: sync)),
            "DescriptionEditorBridge must be @Observable"
        )
        XCTAssertTrue(
            isObservable(DescriptionEditorChromeState()),
            "DescriptionEditorChromeState must be @Observable"
        )
    }

    func test_apiClient_doesNotConformToObservableObject() {
        // APIClient had a vestigial `: ObservableObject` conformance with zero
        // `@Published` properties. After migration it should not conform to
        // `ObservableObject`.
        XCTAssertFalse(
            APIClient.shared is ObservableObject,
            "APIClient should no longer conform to ObservableObject (vestigial conformance removed)"
        )
    }

    func test_alreadyObservableTypes_remainObservable() {
        XCTAssertTrue(isObservable(AuthService.shared), "AuthService must remain @Observable")
        XCTAssertTrue(isObservable(TimerManager.shared), "TimerManager must remain @Observable")
        XCTAssertTrue(isObservable(DeepLinkRouter.shared), "DeepLinkRouter must remain @Observable")
        XCTAssertTrue(isObservable(AssistantRecipeContext.shared), "AssistantRecipeContext must remain @Observable")
    }

    // MARK: - Helpers

    private func makeStubStore() -> YDocStore {
        let db = (try? YrsDatabase.makeInMemoryFallback())!
        return YDocStore(dbQueue: db.dbQueue)
    }

    private func makeStubMapStore() -> RemindersMapStore {
        let db = (try? YrsDatabase.makeInMemoryFallback())!
        return RemindersMapStore(dbQueue: db.dbQueue)
    }

    /// The `@Observable` macro injects a `_$observationRegistrar` stored property.
    /// This helper probes for it via Mirror reflection as an indirect conformance signal.
    private func isObservable(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.children.contains { $0.label == "_$observationRegistrar" }
    }
}
