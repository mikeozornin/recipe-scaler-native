import Foundation

/// Breaks the retain cycle that existed when `YjsSyncService.start` assigned a
/// self-referential closure to `TimerSyncService.sendTimerEvent`.
///
/// Both services are held by `AppContainer` for their full lifetime, so the bridge
/// itself does not need to retain either; it keeps weak references to allow
/// independent teardown in tests.
@MainActor
final class TimerEventBridge {
    private weak var sync: YjsSyncService?
    private weak var timerSync: TimerSyncService?

    /// Wires `timerSync.sendTimerEvent` to forward to `sync.emitTimerEvent`.
    /// Idempotent: re-installing on the same pair is a no-op beyond overwriting the closure.
    func install(sync: YjsSyncService, timerSync: TimerSyncService) {
        self.sync = sync
        self.timerSync = timerSync
        timerSync.sendTimerEvent = { [weak self] type, timerId, payload in
            guard let self else { return false }
            return await self.sync?.emitTimerEvent(type: type, timerId: timerId, eventData: payload) ?? false
        }
    }
}
