import UIKit
import XCTest
@testable import RecipeScalerNative

/// Regression tests for MIK-192: `TabBarDiscovery` must NOT re-run the recursive
/// view-controller search on a stable layout — only when the cached reference is
/// gone or its parent changed.
@MainActor
final class TabBarDiscoveryTests: XCTestCase {

    // MARK: - Stable layout: search runs once

    func testResolve_runsSearchOnceOnStableHierarchy() {
        let tabBarController = UITabBarController()
        let searchCount = SearchCounter()
        let discovery = TabBarDiscovery(search: searchCount.search)

        _ = discovery.resolve(root: tabBarController)
        _ = discovery.resolve(root: tabBarController)
        _ = discovery.resolve(root: tabBarController)

        XCTAssertEqual(searchCount.calls, 1, "Search must be cached on stable layout (3 calls → 1 traversal)")
    }

    // MARK: - Cache invalidated when controller leaves hierarchy

    func testResolve_rerunsSearchWhenCachedParentChanges() {
        let window = makePassthroughWindow()
        let outerContainer = UIViewController()
        let tabBarController = UITabBarController()
        outerContainer.addChild(tabBarController)
        tabBarController.didMove(toParent: outerContainer)
        window.rootViewController = outerContainer

        let searchCount = SearchCounter()
        let discovery = TabBarDiscovery(search: searchCount.search)

        XCTAssertEqual(searchCount.calls, 0)
        _ = discovery.resolve(root: outerContainer)
        XCTAssertEqual(searchCount.calls, 1)

        // Stable → no re-search.
        _ = discovery.resolve(root: outerContainer)
        XCTAssertEqual(searchCount.calls, 1)

        // Reparent: cache parent mismatch must trigger a fresh traversal.
        outerContainer.removeChild(tabBarController)
        let newContainer = UIViewController()
        newContainer.addChild(tabBarController)
        tabBarController.didMove(toParent: newContainer)

        _ = discovery.resolve(root: newContainer)
        XCTAssertEqual(searchCount.calls, 2, "Parent change must invalidate the cached tabBarController")
    }

    // MARK: - Cache invalidates when weak reference clears

    func testResolve_rerunsSearchAfterTabBarControllerDeallocates() {
        // The discovery cache stores a WEAK ref. We provide two controllers
        // via a `WeakTabBarControllerBox` (so the search closure does not pin
        // the controller itself) and verify that after the first controller is
        // deallocated, the next `resolve()` does NOT return the stale cached
        // controller — it re-runs search and picks up the new one.
        let box = WeakTabBarControllerBox()
        let discovery = TabBarDiscovery(search: { _ in box.value })

        // First controller: cache it, then release our strong ref.
        var firstHolder: UITabBarController? = UITabBarController()
        box.value = firstHolder
        XCTAssertEqual(discovery.resolve(root: firstHolder), firstHolder, "Initial resolve must return the first controller")

        // Drop the only strong reference and drain any autorelease pool. UIKit
        // view controllers are typically autoreleased, so without the pool the
        // weak refs may still resolve to the old instance.
        firstHolder = nil
        autoreleasepool { /* drain */ }
        XCTAssertNil(box.value, "Precondition: first controller must be deallocated before re-resolve")

        // Provide a fresh controller. resolve() must observe the dead cache
        // and re-run search instead of returning a dangling pointer.
        let second = UITabBarController()
        box.value = second
        let result = discovery.resolve(root: second)
        XCTAssertEqual(result, second, "After deallocation resolve must re-run search and return the new controller")
    }

    // MARK: - Search returning nil does not crash and stays cached-free

    func testResolve_searchReturnsNil_thenFindsAfterChange() {
        let tabBarController = UITabBarController()
        var shouldFind = false
        let discovery = TabBarDiscovery(search: { root in
            guard shouldFind else { return nil }
            return TabBarDiscovery.find(in: root)
        })

        XCTAssertNil(discovery.resolve(root: tabBarController))

        shouldFind = true
        // nil result is not cached (cache only stores resolved controller).
        let resolved = discovery.resolve(root: tabBarController)
        XCTAssertNotNil(resolved)
    }

    // MARK: - Helpers

    /// Counts how many times the recursive search closure is invoked.
    private final class SearchCounter {
        private(set) var calls = 0

        func search(_ candidate: UIViewController?) -> UITabBarController? {
            calls += 1
            return TabBarDiscovery.find(in: candidate)
        }
    }

    /// Indirection so the search closure can read a controller weakly without
    /// keeping it alive itself (a direct capture of a strong `var` would pin
    /// the controller through the closure).
    private final class WeakTabBarControllerBox {
        weak var value: UITabBarController?
    }

    /// A `UIWindow` that can be constructed in unit tests without a scene.
    private final class PassthroughWindow: UIWindow {
        override init(frame frameRect: CGRect) {
            super.init(frame: frameRect)
            isHidden = false
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
    }

    private func makePassthroughWindow() -> PassthroughWindow {
        PassthroughWindow(frame: UIScreen.main.bounds)
    }
}

private extension UIViewController {
    func removeChild(_ child: UIViewController) {
        guard child.parent === self else { return }
        child.willMove(toParent: nil)
        child.removeFromParent()
    }
}
