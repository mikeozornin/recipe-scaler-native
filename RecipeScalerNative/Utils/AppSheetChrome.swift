//
//  AppSheetChrome.swift
//  RecipeScalerNative
//
//  Opaque sheet presentation — overrides iOS 26 Liquid Glass default for task-focused sheets.
//

import SwiftUI

enum AppSheetChrome {
    static var groupedBackground: Color { Color(.systemGroupedBackground) }
    static var secondaryGroupedBackground: Color { Color(.secondarySystemGroupedBackground) }
    static var plainBackground: Color { Color(.systemBackground) }
}

extension View {
    /// Grouped opaque sheet background for utility list/form sheets.
    func appOpaqueSheetPresentation(
        detents: Set<PresentationDetent>? = nil,
        dragIndicator: Visibility = .visible
    ) -> some View {
        modifier(
            OpaqueSheetPresentationModifier(
                background: AppSheetChrome.groupedBackground,
                detents: detents,
                dragIndicator: dragIndicator
            )
        )
    }

    /// Plain opaque sheet background for full-bleed content sheets.
    func appOpaqueSheetPresentationPlain(
        detents: Set<PresentationDetent>? = nil,
        dragIndicator: Visibility = .visible
    ) -> some View {
        modifier(
            OpaqueSheetPresentationModifier(
                background: AppSheetChrome.plainBackground,
                detents: detents,
                dragIndicator: dragIndicator
            )
        )
    }

    /// Custom opaque sheet background (e.g. black for camera).
    func appOpaqueSheetPresentation(
        background: Color,
        detents: Set<PresentationDetent>? = nil,
        dragIndicator: Visibility = .visible
    ) -> some View {
        modifier(
            OpaqueSheetPresentationModifier(
                background: background,
                detents: detents,
                dragIndicator: dragIndicator
            )
        )
    }

    /// Solid grouped surface for List/Form inside opaque utility sheets.
    func appOpaqueGroupedListSurface() -> some View {
        self
            .scrollContentBackground(.hidden)
            .listRowBackground(AppSheetChrome.secondaryGroupedBackground)
            .background(AppSheetChrome.groupedBackground)
    }

    /// Solid background for plain List sheets (no inset grouped row cards).
    func appOpaqueListSurface() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppSheetChrome.groupedBackground)
    }
}

private struct OpaqueSheetPresentationModifier: ViewModifier {
    let background: Color
    let detents: Set<PresentationDetent>?
    let dragIndicator: Visibility

    func body(content: Content) -> some View {
        var view = AnyView(
            content
                .presentationBackground(background)
                .presentationDragIndicator(dragIndicator)
        )
        if let detents {
            view = AnyView(view.presentationDetents(detents))
        }
        return view
    }
}
