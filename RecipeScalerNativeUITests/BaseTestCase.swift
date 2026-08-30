import XCTest

/// Base class for all E2E specs.
///
/// Web parity: `tests/e2e/fixtures/auth.ts`'s `test` export. Each test
/// gets a freshly-registered anonymous user via `POST /api/auth/register-auto`,
/// and the credentials are injected into the app via launch env so the
/// app's `AuthService` / `AppContainer.bootstrap` reads them on cold start.
///
/// Subclasses override `extraLaunchArguments()` and `extraLaunchEnvironment()`
/// to add per-spec launch args (e.g. `-OpenTab=shopping`). These are read
/// during `super.setUp()` BEFORE `app.launch()`.
class BaseTestCase: XCTestCase {
    let app = XCUIApplication()

    /// Per-test auth registrar (web parity: register-auto fixture). Created
    /// fresh in `setUp` so credentials never leak between tests in the same
    /// process. `seedClient` is constructed after `user` is registered.
    private(set) var seedClient: SeedClient!
    /// Registered E2E user for this test (seed phrase, tokens). Subclasses
    /// read `e2eUser.seedPhrase` for flows that need the phrase in-UI.
    private(set) var e2eUser: TestUser!
    private let debugUser = DebugUser()

    /// Override in subclass to add launch args. Composed before launch.
    func extraLaunchArguments() -> [String] { [] }

    /// Override in subclass to add launch env. Composed before launch.
    func extraLaunchEnvironment() -> [String: String] { [:] }

    /// Override to seed data **before** `app.launch()` so the first
    /// collection sync can rebuild from SQL recipes (REST `createEmptyRecipe`
    /// does not write the Yjs collection doc by itself).
    func prepareBeforeLaunch() async throws {}

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        let user: TestUser
        do {
            user = try await debugUser.registerFresh()
        } catch {
            throw XCTSkip("E2E register-auto failed: \(error). Skipping test to avoid cascade.")
        }
        e2eUser = user
        seedClient = SeedClient(user: debugUser)

        // Seed before launch when subclass needs it (hydrate tests).
        try await prepareBeforeLaunch()

        let apiBase = E2EConfig.apiBaseURL.absoluteString
        let wsBase: String = {
            if apiBase.hasPrefix("https://") {
                return "wss://" + String(apiBase.dropFirst("https://".count))
            }
            if apiBase.hasPrefix("http://") {
                return "ws://" + String(apiBase.dropFirst("http://".count))
            }
            return "ws://127.0.0.1:3001"
        }()

        var env: [String: String] = [
            E2EConfig.launchEnvUserId: user.userId,
            E2EConfig.launchEnvDeviceToken: user.deviceToken,
            E2EConfig.launchEnvSeedPhrase: user.seedPhrase,
            E2EConfig.launchEnvDeviceId: user.deviceId,
            E2EConfig.launchEnvApiBase: apiBase,
            E2EConfig.launchEnvWsBase: wsBase,
            "AGENT_DEBUG_LOG_DISABLED": "0",
        ]
        env.merge(extraLaunchEnvironment()) { _, new in new }
        app.launchEnvironment = env

        var args = ["-SkipSplash=1"]
        args.append(contentsOf: extraLaunchArguments())
        app.launchArguments = args

        app.launch()
    }

    @MainActor
    override func tearDown() async throws {
        // Persist a screenshot only when the test actually failed — full-screen
        // captures on every test (the previous behavior) accumulate credentials
        // and PII in .xcresult artifacts (CI buckets, crash logs). Successful
        // runs need no post-state evidence. See review finding High #7.
        //
        // `XCTestRun` exposes failure count via `failureCount`; if non-zero the
        // test failed and we keep the screenshot. Otherwise skip the
        // attachment entirely.
        if (testRun?.failureCount ?? 0) > 0 {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "tearDown-final-state"
            shot.lifetime = .keepAlways
            add(shot)
        }

        Logs.assertNoCrash(in: app)

        try await super.tearDown()
    }

    // MARK: - Seed helpers

    /// Soft-skip when REST seeding fails **against prod**, but hard-fail on
    /// loopback.
    ///
    /// Production `POST /api/recipes` currently returns HTTP 500 for fresh
    /// users; web E2E uses localhost. On **loopback** we assume the backend
    /// is healthy and any seed failure is a real regression — fail the test
    /// so a 100%-green run actually means something was verified. On **prod**
    /// the failure is environment-driven and we skip to avoid cascade noise.
    /// See review finding Critical #5 + docs/E2E.md.
    func seedOrSkip<T>(
        _ label: String = "REST seed",
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            if E2EConfig.isLoopbackBackend {
                XCTFail("\(label) failed on loopback backend — seed failure is a regression, not an environment issue: \(error)")
                throw error
            }
            throw XCTSkip("\(label) failed — soft-skipping (prod may reject seed): \(error)")
        }
    }

    // MARK: - Convenience page accessors

    var recipeListPage: RecipeListPage { RecipeListPage(app: app) }
    var recipeDetailPage: RecipeDetailPage { RecipeDetailPage(app: app) }
    var shoppingListPage: ShoppingListPage { ShoppingListPage(app: app) }
    var collectionsPage: CollectionsPage { CollectionsPage(app: app) }
    var accountPage: AccountPage { AccountPage(app: app) }
    var discoverPage: DiscoverPage { DiscoverPage(app: app) }
    var assistantPage: AssistantPage { AssistantPage(app: app) }
    var timersPage: TimersPage { TimersPage(app: app) }
    var importPage: ImportPage { ImportPage(app: app) }
    var authPage: AuthPage { AuthPage(app: app) }
    var feedPage: FeedPage { FeedPage(app: app) }
}
