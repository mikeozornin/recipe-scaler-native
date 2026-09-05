//
//  YDocRecipeDetailScrollSupport.swift
//  RecipeScalerNative
//
//  Review 2026.09.04 №20 — extracted from `YDocRecipeDetailView.swift`:
//  caret-scroll anchoring + popover-dismiss gesture support types.
//

import SwiftUI
import UIKit
import WebKit

/// Scrolls the inline description editor so the caret sits in the visible
/// band above the formatting bar / keyboard.
///
/// System keyboard avoidance + formatting-bar `safeAreaInset` own scroll extent.
/// This helper only moves `contentOffset` (explicit clamp — `scrollRectToVisible`
/// is unreliable while keyboard insets are animating).
enum DescriptionEditorScrollAnchor {
    private static let caretTopMargin: CGFloat = 72
    private static let caretBottomPadding: CGFloat = 8

    @MainActor
    static func scrollCaretIntoView(
        bridge: DescriptionEditorBridge?,
        keyboardOverlap: CGFloat,
        onlyCorrectIfOffsetTooHigh: Bool = false
    ) async -> Bool {
        guard let editorView = bridge?.editorWebView ?? keyWindowDescriptionWebView(),
              let scrollView = detailScrollView(containing: editorView)
        else { return false }

        let editorRect = editorView.convert(editorView.bounds, to: scrollView)
        guard editorRect.height > 0, editorRect.width > 0 else { return false }

        let paintedBottom = min(
            editorRect.height,
            max(bridge?.paintedContentBottom ?? editorRect.height, 1)
        )
        let effectiveEditorRect = CGRect(
            x: editorRect.minX,
            y: editorRect.minY,
            width: editorRect.width,
            height: paintedBottom
        )

        var caretInEditor: CGRect?
        if let bridge {
            caretInEditor = await bridge.requestCaretRectInEditor()
        }
        if caretInEditor == nil, let webView = editorView as? WKWebView {
            caretInEditor = await queryCaretRect(on: webView)
        }

        let breathing = DescriptionFormattingBarLayoutMetrics.contentBottomBreathingRoom
        let barTopInBounds = formattingBarTopInScrollBounds(scrollView)
        let focusRect: CGRect
        var pinToBottom = false
        let userIsScrolling = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating

        if let caretInEditor {
            let caret = editorView.convert(caretInEditor, to: scrollView)
            let nearPaintedEnd = caret.maxY >= effectiveEditorRect.maxY - 64
            pinToBottom = nearPaintedEnd
            if nearPaintedEnd {
                // Last lines: pin painted bottom just above the formatting bar.
                let pinHeight: CGFloat = 48 + breathing
                focusRect = CGRect(
                    x: effectiveEditorRect.minX,
                    y: max(effectiveEditorRect.minY, effectiveEditorRect.maxY - pinHeight),
                    width: effectiveEditorRect.width,
                    height: pinHeight
                )
            } else {
                let caretReveal = CGRect(
                    x: effectiveEditorRect.minX,
                    y: max(effectiveEditorRect.minY, caret.minY - caretTopMargin),
                    width: effectiveEditorRect.width,
                    height: max(
                        caret.height + breathing + caretBottomPadding,
                        44
                    )
                )
                focusRect = CGRect(
                    x: caretReveal.minX,
                    y: caretReveal.minY,
                    width: caretReveal.width,
                    height: min(
                        caretReveal.height,
                        max(0, effectiveEditorRect.maxY - caretReveal.minY)
                    )
                )
            }
        } else {
            let sliceHeight = min(120, effectiveEditorRect.height)
            focusRect = CGRect(
                x: effectiveEditorRect.minX,
                y: effectiveEditorRect.minY,
                width: effectiveEditorRect.width,
                height: sliceHeight + breathing
            )
        }

        let maxOffsetBelowEditor = maxOffsetShowingEditorBottom(
            scrollView: scrollView,
            editorRect: effectiveEditorRect,
            barTopInBounds: barTopInBounds,
            breathing: breathing
        )

        // Visibility alone is not enough: keyboard avoidance can leave the
        // caret in-band while contentOffset sits above the pin (white hole).
        let offsetTooHigh = scrollView.contentOffset.y > maxOffsetBelowEditor + 2
        if !onlyCorrectIfOffsetTooHigh,
           !offsetTooHigh,
           (keyboardOverlap <= 0 || caretInEditor != nil),
           isFocusVisible(focusRect: focusRect, scrollView: scrollView)
        {
            return true
        }

        let rawTargetOffsetY = targetContentOffset(
            scrollView: scrollView,
            focusRect: focusRect,
            preferCaretBottom: pinToBottom,
            barTopInBounds: barTopInBounds,
            breathing: breathing
        )
        let targetOffsetY = min(rawTargetOffsetY, maxOffsetBelowEditor)
        let appliedOffsetY = clampedContentOffset(
            scrollView: scrollView,
            targetOffsetY: targetOffsetY
        )

        if onlyCorrectIfOffsetTooHigh,
           !userIsScrolling,
           scrollView.contentOffset.y <= appliedOffsetY + 2
        {
            return true
        }

        guard abs(scrollView.contentOffset.y - appliedOffsetY) > 1 else {
            return true
        }

        return await applyContentOffset(
            scrollView: scrollView,
            offsetY: appliedOffsetY
        )
    }

    @MainActor
    private static func applyContentOffset(
        scrollView: UIScrollView,
        offsetY: CGFloat
    ) async -> Bool {
        // A caret query can span the start of a user pan. Never overwrite the
        // offset while UIKit owns the gesture (device logs: 2321 → 1888).
        guard !(scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating) else {
            return false
        }
        for attempt in 0 ..< 6 {
            guard !(scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating) else {
                return false
            }
            UIView.performWithoutAnimation {
                scrollView.layer.removeAllAnimations()
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: offsetY),
                    animated: false
                )
                scrollView.layoutIfNeeded()
            }
            if abs(scrollView.contentOffset.y - offsetY) <= 1 {
                return true
            }
            if attempt < 5 {
                try? await Task.sleep(for: .milliseconds(32))
            }
        }
        return abs(scrollView.contentOffset.y - offsetY) <= 2
    }

    private static func bottomPinnedContentOffset(
        scrollView: UIScrollView,
        focusMaxY: CGFloat,
        barTopInBounds: CGFloat?,
        breathing: CGFloat
    ) -> CGFloat {
        if let barTopInBounds, barTopInBounds > 0 {
            // Pin focusMaxY just above the real formatting-bar frame (bounds space).
            // contentY = offset + boundsY  ⇒  offset = focusMaxY - barTop + breathing
            return focusMaxY - barTopInBounds + breathing
        }
        return DescriptionFormattingBarLayoutMetrics.bottomPinnedContentOffset(
            focusMaxY: focusMaxY,
            boundsHeight: scrollView.bounds.height,
            insetBottom: scrollView.adjustedContentInset.bottom
        )
    }

    @MainActor
    private static func formattingBarTopInScrollBounds(_ scrollView: UIScrollView) -> CGFloat? {
        guard let root = scrollView.window ?? keyWindow() else { return nil }
        guard let bar = findView(in: root, accessibilityID: "description_formatting_bar") else {
            return nil
        }
        let frame = bar.convert(bar.bounds, to: scrollView)
        guard frame.height > 0, frame.minY > 0 else { return nil }
        return frame.minY
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func findView(in root: UIView, accessibilityID: String) -> UIView? {
        if root.accessibilityIdentifier == accessibilityID { return root }
        for sub in root.subviews {
            if let found = findView(in: sub, accessibilityID: accessibilityID) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private static func visibleContentHeight(scrollView: UIScrollView) -> CGFloat {
        max(
            0,
            scrollView.bounds.height
                - scrollView.adjustedContentInset.top
                - scrollView.adjustedContentInset.bottom
        )
    }

    @MainActor
    private static func visibleContentRect(in scrollView: UIScrollView) -> CGRect {
        let insetTop = scrollView.adjustedContentInset.top
        let insetBottom = scrollView.adjustedContentInset.bottom
        let minY = scrollView.contentOffset.y + insetTop
        let maxY = scrollView.contentOffset.y + scrollView.bounds.height - insetBottom
        return CGRect(x: 0, y: minY, width: scrollView.bounds.width, height: max(0, maxY - minY))
    }

    /// Do not scroll past the editor bottom — avoids a WebView-tall white band under text.
    @MainActor
    private static func maxOffsetShowingEditorBottom(
        scrollView: UIScrollView,
        editorRect: CGRect,
        barTopInBounds: CGFloat?,
        breathing: CGFloat
    ) -> CGFloat {
        let insetTop = scrollView.adjustedContentInset.top
        return max(
            -insetTop,
            bottomPinnedContentOffset(
                scrollView: scrollView,
                focusMaxY: editorRect.maxY,
                barTopInBounds: barTopInBounds,
                breathing: breathing
            )
        )
    }

    @MainActor
    private static func isFocusVisible(
        focusRect: CGRect,
        scrollView: UIScrollView
    ) -> Bool {
        let visible = visibleContentRect(in: scrollView)
        guard visible.height > 0 else { return false }
        return focusRect.minY >= visible.minY - 2
            && focusRect.maxY <= visible.maxY + 2
    }

    @MainActor
    private static func targetContentOffset(
        scrollView: UIScrollView,
        focusRect: CGRect,
        preferCaretBottom: Bool,
        barTopInBounds: CGFloat?,
        breathing: CGFloat
    ) -> CGFloat {
        let insetTop = scrollView.adjustedContentInset.top
        if preferCaretBottom {
            return bottomPinnedContentOffset(
                scrollView: scrollView,
                focusMaxY: focusRect.maxY,
                barTopInBounds: barTopInBounds,
                breathing: breathing
            )
        }
        return focusRect.minY - insetTop
    }

    @MainActor
    private static func clampedContentOffset(
        scrollView: UIScrollView,
        targetOffsetY: CGFloat
    ) -> CGFloat {
        let insetTop = scrollView.adjustedContentInset.top
        let insetBottom = scrollView.adjustedContentInset.bottom
        let minY = -insetTop
        let maxY = max(
            minY,
            scrollView.contentSize.height + insetBottom - scrollView.bounds.height
        )
        return min(max(targetOffsetY, minY), maxY)
    }

    @MainActor
    private static func queryCaretRect(on webView: WKWebView) async -> CGRect? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                "window.__descriptionEditorGetCaretRect && window.__descriptionEditorGetCaretRect()"
            ) { result, _ in
                continuation.resume(
                    returning: DescriptionEditorWebView.Coordinator.parseCaretRect(result)
                )
            }
        }
    }

    @MainActor
    private static func keyWindowDescriptionWebView() -> WKWebView? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return nil }
        return findWebView(in: window)
    }

    private static func findWebView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for sub in view.subviews {
            if let found = findWebView(in: sub) { return found }
        }
        return nil
    }

    /// Detail `ScrollView`, never the editor's nested `WKWebView.scrollView`.
    /// Prefer the ancestor with the largest content size that contains the
    /// editor — SwiftUI may insert intermediate scroll views.
    static func detailScrollView(containing editorView: UIView) -> UIScrollView? {
        var ancestor: UIView? = editorView.superview
        var best: UIScrollView?
        var bestContentHeight: CGFloat = 0
        while let current = ancestor {
            if let scroll = current as? UIScrollView, !scroll.isDescendant(of: editorView) {
                let editorRect = editorView.convert(editorView.bounds, to: scroll)
                if editorRect.height > 0, scroll.contentSize.height >= bestContentHeight {
                    best = scroll
                    bestContentHeight = scroll.contentSize.height
                }
            }
            ancestor = current.superview
        }
        return best
    }
}

struct DismissPopoverOnVerticalDragModifier: ViewModifier {
    let isActive: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    guard isActive else { return }
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    onDismiss()
                }
        )
    }
}
