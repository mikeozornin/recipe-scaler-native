import SwiftUI
import UIKit

// Presentation helpers for the iPad (spec 081, plan.md Р7). On `.phone` every helper
// keeps the existing iPhone behavior. Both branches stay in the view tree and only
// their inputs change, so a size class change does not reset the content state (FR-018).

extension View {
    /// `.sheet` on `.phone`, `.popover` on `.padRegular`.
    ///
    /// `content` is passed to both unchanged: sheet contents in the app already carry
    /// their chrome (`appOpaqueSheetPresentation()`), so the phone shows exactly the
    /// existing sheet. Inside a popover the system ignores detents and the drag indicator.
    func adaptivePopover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) -> some View {
        modifier(AdaptivePopoverModifier(isPresented: isPresented, arrowEdge: arrowEdge, popoverContent: content))
    }

    /// Caps the width at `width` and centers it on `.padRegular`
    /// (`IPadLayoutMetrics.readablePageWidth`, `.authorPageWidth`). No effect on `.phone`.
    func iPadReadableWidth(_ width: CGFloat) -> some View {
        modifier(IPadReadableWidthModifier(width: width))
    }

    /// Form sheet sizing for a sheet's content on iPad, iOS 18+. Apply inside the sheet.
    ///
    /// Keyed on the idiom, which never changes while the app runs, so the sheet content
    /// keeps its identity when the window resizes. In a compact iPad window the system
    /// shows a form sheet as a regular full-width sheet, the same as `.phone`.
    /// On iOS 17 the iPad already presents sheets as form sheets.
    @ViewBuilder
    func iPadFormSheet() -> some View {
        if #available(iOS 18.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            presentationSizing(.form)
        } else {
            self
        }
    }
}

private struct AdaptivePopoverModifier<PopoverContent: View>: ViewModifier {
    @Environment(\.appLayoutMode) private var layoutMode

    @Binding var isPresented: Bool
    let arrowEdge: Edge
    let popoverContent: () -> PopoverContent

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: layoutMode == .phone ? $isPresented : .constant(false), content: popoverContent)
            .popover(
                isPresented: layoutMode == .padRegular ? $isPresented : .constant(false),
                arrowEdge: arrowEdge,
                content: popoverContent
            )
    }
}

private struct IPadReadableWidthModifier: ViewModifier {
    @Environment(\.appLayoutMode) private var layoutMode

    let width: CGFloat

    func body(content: Content) -> some View {
        // `nil` frames pass the proposal and the size through unchanged.
        let isPad = layoutMode == .padRegular
        content
            .frame(maxWidth: isPad ? width : nil)
            .frame(maxWidth: isPad ? .infinity : nil)
    }
}

#if DEBUG
private struct AdaptivePresentationPreview: View {
    @State private var showsPopover = false

    var body: some View {
        VStack(spacing: 24) {
            Button {
                showsPopover = true
            } label: {
                Text(verbatim: "Popover / sheet")
            }
            .adaptivePopover(isPresented: $showsPopover) {
                List {
                    Text(verbatim: "Row 1")
                    Text(verbatim: "Row 2")
                }
                .frame(minWidth: IPadLayoutMetrics.collectionsPopoverWidth, minHeight: 200)
                .appOpaqueSheetPresentation(detents: [.medium])
            }

            Text(verbatim: String(repeating: "Readable width. ", count: 40))
                .padding()
                .background(Color(.secondarySystemBackground))
                .iPadReadableWidth(IPadLayoutMetrics.readablePageWidth)
        }
        .padding()
    }
}

#Preview("adaptive-presentation-phone") {
    AdaptivePresentationPreview()
        .environment(\.appLayoutMode, .phone)
}

#Preview("adaptive-presentation-pad", traits: .fixedLayout(width: 1194, height: 834)) {
    AdaptivePresentationPreview()
        .environment(\.appLayoutMode, .padRegular)
}
#endif
