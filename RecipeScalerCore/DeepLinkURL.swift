//
//  DeepLinkURL.swift
//  RecipeScalerCore
//
//  Canonical custom URL scheme shared between the main app and extensions.
//  Use `DeepLinkURL.baseScheme` when BUILDING deep-link URL strings; parsing
//  (`DeepLinkRouter.parse`) accepts both flavors so cross-install taps never
//  break.
//

import Foundation

public enum DeepLinkURL {
    /// Custom URL scheme for deep links into the app.
    ///
    /// Spec 066 (side-by-side builds): the dev flavor declares
    /// `recipe-scaler-dev` in its Info.plist (`$(RS_URL_SCHEME)`), so URLs
    /// built inside dev widgets / Share extension must target the same
    /// install. Parsing accepts both schemes regardless of flavor.
    #if RS_DEV_FLAVOR
    public static let baseScheme = "recipe-scaler-dev"
    #else
    public static let baseScheme = "recipe-scaler"
    #endif
}
