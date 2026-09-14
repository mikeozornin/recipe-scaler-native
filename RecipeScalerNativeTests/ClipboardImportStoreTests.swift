import XCTest
@testable import RecipeScalerNative

final class FakeClipboardPasteboard: ClipboardImportPasteboard, @unchecked Sendable {
    var changeCount = 1
    var probableWebURL = true
    var text: String? = "https://example.com/recipe"
    var sleepNanos: UInt64 = 0
    var plainTextCallCount = 0

    func hasProbableWebURL() async -> Bool {
        if sleepNanos > 0 {
            try? await Task.sleep(nanoseconds: sleepNanos)
        }
        return probableWebURL
    }

    func plainText() async -> String? {
        plainTextCallCount += 1
        if sleepNanos > 0 {
            try? await Task.sleep(nanoseconds: sleepNanos)
        }
        return text
    }
}

@MainActor
final class ClipboardImportStoreTests: XCTestCase {
    func testShowsWhenLikelyURLWithoutReadingContents() {
        let store = ClipboardImportStore(pasteboard: FakeClipboardPasteboard())
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        XCTAssertEqual(store.bannerState, .visible)
    }

    func testHidesWhenImportSheetOpen() {
        let store = ClipboardImportStore()
        var context = ClipboardImportEvaluateContext.eligible
        context.isImportSheetPresented = true
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: context
        )
        XCTAssertEqual(store.bannerState, .hidden)
    }

    func testHidesWhenOffline() {
        let store = ClipboardImportStore()
        var context = ClipboardImportEvaluateContext.eligible
        context.isURLImportAvailable = false
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: context
        )
        XCTAssertEqual(store.bannerState, .hidden)
    }

    func testDismissRemembersThisChangeCount() {
        let store = ClipboardImportStore()
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        store.dismissVisible()
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        XCTAssertEqual(store.bannerState, .hidden)
    }

    func testDifferentChangeCountShowsAgain() {
        let store = ClipboardImportStore()
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        store.dismissVisible()
        store.applySnapshot(
            changeCount: 2,
            hasProbableWebURL: true,
            context: .eligible
        )
        XCTAssertEqual(store.bannerState, .visible)
    }

    func testConsumedNotShownAgain() {
        let store = ClipboardImportStore()
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        store.markConsumed()
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        XCTAssertEqual(store.bannerState, .hidden)
    }

    func testOwnWriteIsIgnored() {
        let store = ClipboardImportStore()
        store.ignoreOwnWrite(changeCount: 9)
        store.applySnapshot(
            changeCount: 9,
            hasProbableWebURL: true,
            context: .eligible
        )
        XCTAssertEqual(store.bannerState, .hidden)
    }

    func testNoProbableUrlStaysHidden() {
        let store = ClipboardImportStore()
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: false,
            context: .eligible
        )
        XCTAssertEqual(store.bannerState, .hidden)
    }

    func testEvaluateDoesNotReadPlainText() async {
        let pasteboard = FakeClipboardPasteboard()
        let store = ClipboardImportStore(pasteboard: pasteboard)
        await store.evaluate(context: .eligible)
        XCTAssertEqual(pasteboard.plainTextCallCount, 0)
        XCTAssertEqual(store.bannerState, .visible)
    }

    func testSeedTextForImportReadsOnDemand() async {
        let pasteboard = FakeClipboardPasteboard()
        pasteboard.text = "https://example.com/r"
        let store = ClipboardImportStore(pasteboard: pasteboard)
        store.applySnapshot(changeCount: 1, hasProbableWebURL: true, context: .eligible)
        let seed = await store.seedTextForImport()
        XCTAssertEqual(seed, "https://example.com/r")
        XCTAssertEqual(pasteboard.plainTextCallCount, 1)
    }

    func testLogoutDropsStaleEvaluate() async {
        let pasteboard = FakeClipboardPasteboard()
        pasteboard.sleepNanos = 200_000_000
        pasteboard.text = "https://example.com/stale"
        let store = ClipboardImportStore(pasteboard: pasteboard)
        let evaluate = Task { await store.evaluate(context: .eligible) }
        while store.evaluateGeneration == 0 {
            await Task.yield()
        }
        store.clearForLogout()
        await evaluate.value
        XCTAssertEqual(store.bannerState, .hidden)
        XCTAssertGreaterThanOrEqual(store.evaluateGeneration, 2)
        XCTAssertEqual(pasteboard.plainTextCallCount, 0)
    }

    func testLogoutClearsDismissedMemory() {
        let store = ClipboardImportStore()
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        store.dismissVisible()
        store.clearForLogout()
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        XCTAssertEqual(store.bannerState, .visible)
    }

    func testLogoutDropsInFlightSeed() async {
        let pasteboard = FakeClipboardPasteboard()
        pasteboard.sleepNanos = 200_000_000
        pasteboard.text = "https://example.com/stale-seed"
        let store = ClipboardImportStore(pasteboard: pasteboard)
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        let seed = Task { await store.seedTextForImport() }
        while pasteboard.plainTextCallCount == 0 {
            await Task.yield()
        }
        store.clearForLogout()
        let result = await seed.value
        XCTAssertNil(result)
    }

    func testMarkConsumedUsesSeededChangeCountNotLivePasteboard() async {
        let pasteboard = FakeClipboardPasteboard()
        pasteboard.changeCount = 1
        pasteboard.text = "https://example.com/r"
        let store = ClipboardImportStore(pasteboard: pasteboard)
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        pasteboard.changeCount = 99
        _ = await store.seedTextForImport()
        store.markConsumed()
        store.applySnapshot(
            changeCount: 1,
            hasProbableWebURL: true,
            context: .eligible
        )
        XCTAssertEqual(store.bannerState, .hidden)
        store.applySnapshot(
            changeCount: 99,
            hasProbableWebURL: true,
            context: .eligible
        )
        XCTAssertEqual(store.bannerState, .visible)
    }

    func testMarkConsumedDoesNotStampLivePasteboardWhenBannerHidden() {
        let pasteboard = FakeClipboardPasteboard()
        pasteboard.changeCount = 7
        let store = ClipboardImportStore(pasteboard: pasteboard)
        store.applySnapshot(
            changeCount: 7,
            hasProbableWebURL: true,
            context: .eligible
        )
        var sheetOpen = ClipboardImportEvaluateContext.eligible
        sheetOpen.isImportSheetPresented = true
        store.applySnapshot(
            changeCount: 7,
            hasProbableWebURL: true,
            context: sheetOpen
        )
        store.markConsumed()
        store.applySnapshot(
            changeCount: 7,
            hasProbableWebURL: true,
            context: .eligible
        )
        XCTAssertEqual(store.bannerState, .visible)
    }
}
