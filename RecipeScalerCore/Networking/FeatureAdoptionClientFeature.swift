//
//  FeatureAdoptionClientFeature.swift
//  RecipeScalerCore
//
//  Client-reported feature-adoption keys (spec 038).
//

import Foundation

public enum FeatureAdoptionClientFeature: String, Sendable {
    case installedNativeApp = "installed_native_app"
    case installedWatchApp = "installed_watch_app"
}
