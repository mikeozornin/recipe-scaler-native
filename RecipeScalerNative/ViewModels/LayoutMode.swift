//
//  LayoutMode.swift
//  RecipeScalerNative
//
//  Spec 043 — compact TabView vs regular NavigationSplitView.
//

import SwiftUI

enum LayoutMode: Equatable {
    case compact
    case regular
}

enum LayoutModeResolver {
    static func resolve(
        horizontalSizeClass: UserInterfaceSizeClass?,
        forceLayout: LayoutMode?
    ) -> LayoutMode {
        if let forceLayout {
            return forceLayout
        }
        if horizontalSizeClass == .regular {
            return .regular
        }
        return .compact
    }
}