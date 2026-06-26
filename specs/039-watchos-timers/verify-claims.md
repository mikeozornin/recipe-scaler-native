# Verify claims — watchOS timers (spec 039)

Falsifiable claims for `/verify-this`. Automated gate: `bash scripts/verify-watch-timers.sh`.

| ID | Claim | Metric | Threshold | Automated |
|----|-------|--------|-----------|-----------|
| W1 | Running timer progress grows over wall-clock time | `progressFraction(now)` at `t` vs `t+5s` | `later > early`, delta ≈ `5/duration` | `ActiveTimerPresentationTests.testProgressIncreasesAsTimeAdvances` |
| W2 | Exceeded timer shows full bar | `progressFraction` when `remaining ≤ 0` | `== 1.0` | `ActiveTimerPresentationTests.testProgressFullWhenExceeded` |
| W3 | Exceeded accent is red | `palette.accent` when overdue | `== .exceeded` | `ActiveTimerPresentationTests.testExceededColorsNameAndBarAccent` |
| W4 | Soon accent in last 10% (inclusive) | 10s timer, 1s left | `== .soon` | `ActiveTimerPresentationTests.testSoonAccentLastSecondOfTenSecondTimer` |
| W5 | List sort: soonest finish on top | sort order among running | ascending `remaining` | `TimerOrderingTests.testAscendingRemainingAmongRunning` |
| W6 | Running before paused | sort order | running first | `TimerOrderingTests.testRunningBeforePaused` |
| W7 | UI tick driver at list level | `TimerListView` source | `TimelineView` wraps `List`, not inside row | `scripts/verify-watch-timers.sh` grep |
| W8 | Watch target builds | `xcodebuild` exit code | `0` | `scripts/verify-watch-timers.sh` |

Manual (simulator) when automation is inconclusive for UI paint:

- Start 30s timer on watch; progress bar width increases within 5s without app restart.
- At `-8m`, bar full width; time, name, and bar use red accent.
