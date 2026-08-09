import Foundation
import XCTest

/// Reusable primitives for deterministic async / concurrency testing.
///
/// See `docs/agents/ASYNC-LIFECYCLE.md` §2 and §5. The point is to give tests
/// a *real* suspension point that the scheduler can interleave with other work
/// — `async let a; async let b` without an internal await does not prove
/// overlap.
enum AsyncTestGate {

    /// Continuation-backed gate. `wait()` suspends until `release()` is called,
    /// giving the test deterministic control over when an injected provider or
    /// task may resume. Useful for simulating "the second signal arrives while
    /// the first awaits".
    actor Gate {
        private var released = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func release() {
            released = true
            for waiter in waiters {
                waiter.resume()
            }
            waiters.removeAll()
        }

        func wait() async {
            if released { return }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        var isReleased: Bool { released }
    }

    /// Run two operations concurrently and wait for both. `operationA` receives
    /// a gate it is expected to wait on; `operationB` runs after a yield so the
    /// scheduler has a chance to start `operationA` first. Designed for
    /// single-flight / re-entry guard assertions.
    static func runOverlapping<A, B>(
        operationA: @escaping (Gate) async throws -> A,
        operationB: @escaping () async throws -> B
    ) async throws -> (A, B) {
        let gate = Gate()
        async let aValue = operationA(gate)
        await Task.yield()
        let bValue = try await operationB()
        let a = try await aValue
        return (a, bValue)
    }
}
