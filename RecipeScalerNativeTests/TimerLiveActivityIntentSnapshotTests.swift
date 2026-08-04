//
//  TimerLiveActivityIntentSnapshotTests.swift
//  RecipeScalerNativeTests
//
//  Spec 030 Phase A (US-A1): Pause/Resume intent path updates snapshot,
//  reloads widget timelines (spy), and still enqueues ActionQueue.
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

final class TimerLiveActivityIntentSnapshotTests: XCTestCase {
    private let timerId = "timer-phase-a-001"
    private let otherId = "timer-phase-a-other"
    private var fixedNow: Date!

    override func setUp() {
        super.setUp()
        fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        TimerSnapshotStore.clear()
        clearActionQueuePending()
    }

    override func tearDown() {
        TimerSnapshotStore.clear()
        clearActionQueuePending()
        super.tearDown()
    }

    // MARK: - Core patcher

    func testPatcher_ReplacesMatchingTimer_PreservesSiblings_Top4() {
        let existing = TimerSnapshotDocument(
            timers: [
                makeSnapshot(id: otherId, phase: .running, endDate: fixedNow.addingTimeInterval(600), paused: nil),
                makeSnapshot(id: timerId, phase: .running, endDate: fixedNow.addingTimeInterval(120), paused: nil),
            ],
            generatedAt: fixedNow.addingTimeInterval(-60)
        )
        let paused = makeSnapshot(id: timerId, phase: .paused, endDate: nil, paused: 90)
        let next = TimerSnapshotDocumentPatcher.patching(existing, with: paused, now: fixedNow)

        XCTAssertEqual(next.timers.count, 2)
        XCTAssertEqual(next.timers.first(where: { $0.id == timerId })?.phase, .paused)
        XCTAssertEqual(next.timers.first(where: { $0.id == timerId })?.pausedRemainingSeconds, 90)
        XCTAssertEqual(next.timers.first(where: { $0.id == otherId })?.phase, .running)
        XCTAssertEqual(next.generatedAt, fixedNow)
    }

    func testPatcher_ApplyAndSave_UsesInjectableStore() {
        var saved: TimerSnapshotDocument?
        let seed = TimerSnapshotDocument(
            timers: [makeSnapshot(id: otherId, phase: .paused, endDate: nil, paused: 30)],
            generatedAt: .distantPast
        )
        let patched = makeSnapshot(id: timerId, phase: .paused, endDate: nil, paused: 45)
        let result = TimerSnapshotDocumentPatcher.applyAndSave(
            snapshot: patched,
            now: fixedNow,
            load: { seed },
            save: { saved = $0 }
        )
        XCTAssertEqual(result.timers.map(\.id).sorted(), [otherId, timerId].sorted())
        XCTAssertEqual(saved?.timers.first(where: { $0.id == timerId })?.phase, .paused)
    }

    // MARK: - Pause / Resume performer

    func testPause_UpdatesSnapshotPhasePaused_Enqueues_Reloads() async {
        let remaining = 180
        let updatedStates = MutationBox<[RecipeTimerActivityAttributes.ContentState]>([])
        let reloadedKinds = MutationBox<[String]>([])
        let enqueued = MutationBox<[(TimerLiveActivityAction, String)]>([])
        let savedDocs = MutationBox<[TimerSnapshotDocument]>([])

        let attrs = RecipeTimerActivityAttributes(
            timerId: timerId,
            timerName: "Boil",
            recipeId: "recipe-1"
        )
        let runningState = RecipeTimerActivityAttributes.ContentState(
            phase: .running,
            endDate: fixedNow.addingTimeInterval(TimeInterval(remaining)),
            pausedRemainingSeconds: remaining,
            startedAt: fixedNow.addingTimeInterval(-20),
            totalDuration: 200,
            recipeName: "Pasta",
            recipeThumbnailName: nil,
            syncedAt: fixedNow.addingTimeInterval(-5)
        )

        let deps = TimerLiveActivityIntentDependencies(
            loadActivity: { id in
                XCTAssertEqual(id, self.timerId)
                return (attrs, runningState)
            },
            updateActivity: { id, state, stale in
                XCTAssertEqual(id, self.timerId)
                XCTAssertNil(stale)
                updatedStates.value.append(state)
                return true
            },
            applySnapshot: { snapshot in
                let doc = TimerSnapshotDocumentPatcher.applyAndSave(
                    snapshot: snapshot,
                    now: self.fixedNow,
                    load: { TimerSnapshotStore.load() },
                    save: { doc in
                        TimerSnapshotStore.save(doc)
                        savedDocs.value.append(doc)
                    }
                )
                _ = doc
            },
            markPendingLocal: { TimerSnapshotStore.markPendingLocalMutation(now: self.fixedNow) },
            reloadWidget: {
                reloadedKinds.value.append(TimerWidgetKind.id)
            },
            enqueue: { action, id in
                enqueued.value.append((action, id))
            }
        )

        await TimerLiveActivityIntentPerformer.performPause(
            timerId: timerId,
            now: fixedNow,
            dependencies: deps
        )

        XCTAssertEqual(updatedStates.value.count, 1)
        XCTAssertEqual(updatedStates.value[0].phase, .paused)
        XCTAssertNil(updatedStates.value[0].endDate)
        XCTAssertEqual(updatedStates.value[0].pausedRemainingSeconds, remaining)

        let stored = TimerSnapshotStore.load()
        let timer = stored.timers.first(where: { $0.id == timerId })
        XCTAssertEqual(timer?.phase, .paused)
        XCTAssertNil(timer?.endDate)
        XCTAssertEqual(timer?.pausedRemainingSeconds, remaining)
        XCTAssertFalse(savedDocs.value.isEmpty)
        XCTAssertTrue(TimerSnapshotStore.hasPendingLocalMutation(now: fixedNow.addingTimeInterval(1)))

        XCTAssertEqual(reloadedKinds.value, [TimerWidgetKind.id])
        XCTAssertEqual(enqueued.value.count, 1)
        XCTAssertEqual(enqueued.value[0].0, .pause)
        XCTAssertEqual(enqueued.value[0].1, timerId)
    }

    func testResume_UpdatesSnapshotRunningWithEndDate_Enqueues_Reloads() async throws {
        let remaining = 90
        let updatedStates = MutationBox<[RecipeTimerActivityAttributes.ContentState]>([])
        let reloadedKinds = MutationBox<[String]>([])
        let enqueued = MutationBox<[(TimerLiveActivityAction, String)]>([])

        let attrs = RecipeTimerActivityAttributes(
            timerId: timerId,
            timerName: "Bake",
            recipeId: nil
        )
        let pausedState = RecipeTimerActivityAttributes.ContentState(
            phase: .paused,
            endDate: nil,
            pausedRemainingSeconds: remaining,
            startedAt: fixedNow.addingTimeInterval(-100),
            totalDuration: 300,
            recipeName: nil,
            recipeThumbnailName: nil,
            syncedAt: fixedNow.addingTimeInterval(-10)
        )

        let deps = TimerLiveActivityIntentDependencies(
            loadActivity: { _ in (attrs, pausedState) },
            updateActivity: { _, state, stale in
                updatedStates.value.append(state)
                XCTAssertNotNil(stale)
                return true
            },
            applySnapshot: { snapshot in
                TimerSnapshotDocumentPatcher.applyAndSave(
                    snapshot: snapshot,
                    now: self.fixedNow
                )
            },
            markPendingLocal: { TimerSnapshotStore.markPendingLocalMutation(now: self.fixedNow) },
            reloadWidget: {
                reloadedKinds.value.append(TimerWidgetKind.id)
            },
            enqueue: { action, id in
                enqueued.value.append((action, id))
            }
        )

        await TimerLiveActivityIntentPerformer.performResume(
            timerId: timerId,
            now: fixedNow,
            dependencies: deps
        )

        XCTAssertEqual(updatedStates.value.count, 1)
        XCTAssertEqual(updatedStates.value[0].phase, .running)
        XCTAssertEqual(
            updatedStates.value[0].endDate?.timeIntervalSince1970,
            fixedNow.addingTimeInterval(TimeInterval(remaining)).timeIntervalSince1970
        )

        let stored = TimerSnapshotStore.load()
        let timer = try XCTUnwrap(stored.timers.first(where: { $0.id == timerId }))
        XCTAssertEqual(timer.phase, .running)
        XCTAssertNotNil(timer.endDate)
        XCTAssertEqual(
            timer.endDate?.timeIntervalSince1970,
            fixedNow.addingTimeInterval(TimeInterval(remaining)).timeIntervalSince1970
        )
        XCTAssertNil(timer.pausedRemainingSeconds)

        XCTAssertEqual(reloadedKinds.value, [TimerWidgetKind.id])
        XCTAssertEqual(enqueued.value.map(\.0), [.resume])
        XCTAssertEqual(enqueued.value.map(\.1), [timerId])
    }

    func testPause_StillEnqueuesWhenActivityMissing() async {
        let enqueued = MutationBox<[(TimerLiveActivityAction, String)]>([])
        let reloadCount = MutationBox(0)

        // Seed store so fallback can patch without ActivityKit.
        TimerSnapshotStore.save(
            TimerSnapshotDocument(
                timers: [
                    makeSnapshot(
                        id: timerId,
                        phase: .running,
                        endDate: fixedNow.addingTimeInterval(60),
                        paused: nil
                    ),
                ],
                generatedAt: fixedNow
            )
        )

        let deps = TimerLiveActivityIntentDependencies(
            loadActivity: { _ in nil },
            updateActivity: { _, _, _ in
                XCTFail("updateActivity must not be called when activity is missing")
                return false
            },
            applySnapshot: { snapshot in
                TimerSnapshotDocumentPatcher.applyAndSave(snapshot: snapshot, now: self.fixedNow)
            },
            markPendingLocal: { TimerSnapshotStore.markPendingLocalMutation(now: self.fixedNow) },
            reloadWidget: { reloadCount.value += 1 },
            enqueue: { action, id in enqueued.value.append((action, id)) }
        )

        await TimerLiveActivityIntentPerformer.performPause(
            timerId: timerId,
            now: fixedNow,
            dependencies: deps
        )

        XCTAssertEqual(TimerSnapshotStore.load().timers.first?.phase, .paused)
        XCTAssertEqual(reloadCount.value, 1)
        XCTAssertEqual(enqueued.value.map(\.0), [.pause])
        XCTAssertTrue(TimerSnapshotStore.hasPendingLocalMutation(now: fixedNow.addingTimeInterval(1)))
    }

    func testPause_Overdue_DoesNotEnqueueOrUpdate() async {
        let remaining = -30
        let updatedStates = MutationBox<[RecipeTimerActivityAttributes.ContentState]>([])
        let enqueued = MutationBox<[(TimerLiveActivityAction, String)]>([])
        let attrs = RecipeTimerActivityAttributes(
            timerId: timerId,
            timerName: "Overdue",
            recipeId: nil
        )
        let exceededState = RecipeTimerActivityAttributes.ContentState(
            phase: .exceeded,
            endDate: fixedNow.addingTimeInterval(TimeInterval(remaining)),
            pausedRemainingSeconds: 0,
            startedAt: fixedNow.addingTimeInterval(-400),
            totalDuration: 300,
            recipeName: nil,
            recipeThumbnailName: nil,
            syncedAt: fixedNow
        )
        let deps = TimerLiveActivityIntentDependencies(
            loadActivity: { _ in (attrs, exceededState) },
            updateActivity: { _, state, _ in
                updatedStates.value.append(state)
                return true
            },
            applySnapshot: { _ in XCTFail("must not apply snapshot for overdue pause") },
            markPendingLocal: { XCTFail("must not mark pending for overdue pause") },
            reloadWidget: { XCTFail("must not reload for overdue pause") },
            enqueue: { action, id in enqueued.value.append((action, id)) }
        )
        await TimerLiveActivityIntentPerformer.performPause(
            timerId: timerId,
            now: fixedNow,
            dependencies: deps
        )
        XCTAssertTrue(updatedStates.value.isEmpty)
        XCTAssertTrue(enqueued.value.isEmpty)
    }

    func testResume_ZeroRemaining_DoesNotEnqueueOrUpdate() async {
        let updatedStates = MutationBox<[RecipeTimerActivityAttributes.ContentState]>([])
        let enqueued = MutationBox<[(TimerLiveActivityAction, String)]>([])
        let attrs = RecipeTimerActivityAttributes(
            timerId: timerId,
            timerName: "Zero",
            recipeId: nil
        )
        let pausedState = RecipeTimerActivityAttributes.ContentState(
            phase: .paused,
            endDate: nil,
            pausedRemainingSeconds: 0,
            startedAt: fixedNow.addingTimeInterval(-100),
            totalDuration: 300,
            recipeName: nil,
            recipeThumbnailName: nil,
            syncedAt: fixedNow
        )
        let deps = TimerLiveActivityIntentDependencies(
            loadActivity: { _ in (attrs, pausedState) },
            updateActivity: { _, state, _ in
                updatedStates.value.append(state)
                return true
            },
            applySnapshot: { _ in XCTFail("must not apply snapshot for zero resume") },
            markPendingLocal: { XCTFail("must not mark pending for zero resume") },
            reloadWidget: { XCTFail("must not reload for zero resume") },
            enqueue: { action, id in enqueued.value.append((action, id)) }
        )
        await TimerLiveActivityIntentPerformer.performResume(
            timerId: timerId,
            now: fixedNow,
            dependencies: deps
        )
        XCTAssertTrue(updatedStates.value.isEmpty)
        XCTAssertTrue(enqueued.value.isEmpty)
    }

    // Intent.perform() is a one-liner into TimerLiveActivityIntentPerformer
    // (production deps → ActionQueue.enqueue). Do not assert via App Group
    // peek after Intent.perform(): Darwin notify + host TimerManager.installHandler
    // can drain pending before the test reads it (flaky nil). Enqueue coverage
    // is the injectable `dependencies.enqueue` spy above (pause / resume /
    // missing-activity cases).

    // MARK: - Helpers

    private func makeSnapshot(
        id: String,
        phase: TimerSnapshotPhase,
        endDate: Date?,
        paused: Int?
    ) -> TimerSnapshot {
        TimerSnapshot(
            id: id,
            name: "T-\(id)",
            recipeId: nil,
            recipeName: nil,
            endDate: endDate,
            pausedRemainingSeconds: paused,
            phase: phase,
            totalDurationSeconds: 300
        )
    }

    private func clearActionQueuePending() {
        AppGroup.userDefaults?.removeObject(forKey: "timerLiveActivity.pendingAction")
    }
}

/// Tiny mutable box so `@Sendable` test spies can record without Swift 6 capture errors.
private final class MutationBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
