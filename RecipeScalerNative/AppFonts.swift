//
//  AppFonts.swift
//  RecipeScalerNative
//
//

import CoreText
import SwiftUI

enum AppFonts {
    /// Body / regular text (matches web --font-sans)
    static let sans = "Martian Grotesk Nr Lt"
    /// Medium weight (matches web --font-sans-medium)
    static let sansMedium = "Martian Grotesk Nr Md"
    /// Display / headings (matches web --font-display)
    static let display = "Martian Grotesk Std xBd"
    /// Light display for large titles (matches web Martian Grotesk Std Lt)
    static let displayLight = "Martian Grotesk Std Lt"
    /// Monospace (matches web --font-mono)
    static let mono = "Martian Mono Nr Lt"

    private static var didRegisterBundledFonts = false

    /// Registers bundled `.otf` faces for `UIFont(name:size:)` (Previews and early `App.init`).
    static func registerBundledFontsIfNeeded() {
        guard !didRegisterBundledFonts else { return }
        didRegisterBundledFonts = true
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) else {
            return
        }
        for url in urls {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    /// PostScript names for `UIFont(name:size:)` when family/full names are unavailable.
    static func postScriptName(for faceName: String) -> String? {
        switch faceName {
        case sans: "MartianGrotesk-NrLt"
        case sansMedium: "MartianGrotesk-NrMd"
        case display: "MartianGrotesk-StdxBd"
        case displayLight: "MartianGrotesk-StdLt"
        case mono: "MartianMono-NrLt"
        default: nil
        }
    }
}
