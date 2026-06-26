//
//  ActiveTimerPresentationTests.swift
//  RecipeScalerNativeTests
//
//  Spec 039 — falsifiable claims for /verify-this (see specs/039-watchos-timers/verify-claims.md).
//

import XCTest
import RecipeScalerCore

final class ActiveTimerPresentationTests: XCTestCase {
    private func runningState(
        duration: Int,
        endOffset: TimeInterval,
        reference: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> (ActiveTimerState, Date) {
        let now = reference
        let state = ActiveTimerState(
            duration: duration,
            endDate: now.addingTimeInterval(endOffset),
            isPaused: false,
            pausedRemainingSeconds: nil
        )
        return (state, now)
    }

    // MARK: - Live progress (claim: progress grows over time without refresh)

    func testProgressIncreasesAsTimeAdvances() {
        let (state, t0) = runningState(duration: 100, endOffset: 50)
        let t5 = t0.addingTimeInterval(5)
        let early = ActiveTimerPresentation.progressFraction(state, now: t0)
        let later = ActiveTimerPresentation.progressFraction(state, now: t5)
        XCTAssertGreaterThan(later, early)
        XCTAssertEqual(later - early, 0.05, accuracy: 0.001)
    }

    func testRemainingDecreasesAsTimeAdvances() {
        let (state, t0) = runningState(duration: 60, endOffset: 30)
        let t3 = t0.addingTimeInterval(3)
        XCTAssertEqual(ActiveTimerPresentation.remainingSeconds(state, now: t0), 30)
        XCTAssertEqual(ActiveTimerPresentation.remainingSeconds(state, now: t3), 27)
    }

    // MARK: - Exceeded (claim: bar 100%, accent red)

    func testProgressFullWhenExceeded() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let state = ActiveTimerState(
            duration: 10,
            endDate: now.addingTimeInterval(-480),
            isPaused: false,
            pausedRemainingSeconds: nil
        )
        XCTAssertEqual(ActiveTimerPresentation.progressFraction(state, now: now), 1, accuracy: 0.0001)
        XCTAssertEqual(ActiveTimerPresentation.palette(state, now: now).accent, .exceeded)
    }

    func testExceededColorsNameAndBarAccent() {
        let now = Date()
        let state = ActiveTimerState(
            duration: 10,
            endDate: now.addingTimeInterval(-7),
            isPaused: false,
            pausedRemainingSeconds: nil
        )
        XCTAssertEqual(ActiveTimerPresentation.snapshotPhase(state, now: now), .exceeded)
        XCTAssertEqual(ActiveTimerPresentation.palette(state, now: now).accent, .exceeded)
    }

    // MARK: - Soon (claim: last 10% inclusive → orange)

    func testSoonAccentLastSecondOfTenSecondTimer() {
        let now = Date()
        let state = ActiveTimerState(
            duration: 10,
            endDate: now.addingTimeInterval(1),
            isPaused: false,
            pausedRemainingSeconds: nil
        )
        XCTAssertEqual(ActiveTimerPresentation.palette(state, now: now).accent, .soon)
    }

    func testNormalAccentBeforeSoonWindow() {
        let now = Date()
        let state = ActiveTimerState(
            duration: 10,
            endDate: now.addingTimeInterval(2),
            isPaused: false,
            pausedRemainingSeconds: nil
        )
        XCTAssertEqual(ActiveTimerPresentation.palette(state, now: now).accent, .normal)
    }

    // MARK: - Paused (claim: remaining frozen)

    func testPausedUsesStoredRemaining() {
        let now = Date()
        let state = ActiveTimerState(
            duration: 600,
            endDate: now.addingTimeInterval(300),
            isPaused: true,
            pausedRemainingSeconds: 120
        )
        let later = now.addingTimeInterval(60)
        XCTAssertEqual(ActiveTimerPresentation.remainingSeconds(state, now: now), 120)
        XCTAssertEqual(ActiveTimerPresentation.remainingSeconds(state, now: later), 120)
        XCTAssertEqual(ActiveTimerPresentation.progressFraction(state, now: later), 0.8, accuracy: 0.001)
    }

    func testInitFromServerPausedUsesRemainingNotPausedDuration() {
        let timer = ServerActiveTimer(
            timerId: "t1",
            name: "Test",
            duration: 2700,
            endTime: 1_782_516_304_810,
            isPaused: true,
            pausedDuration: 8,
            createdAt: 0,
            lastUpdated: 1_782_513_616_115,
            startedAt: 1_782_512_985_696,
            pausedAt: nil,
            recipeId: nil
        )
        let state = ActiveTimerState(server: timer)
        XCTAssertEqual(state.pausedRemainingSeconds, 2_688)
    }
}
