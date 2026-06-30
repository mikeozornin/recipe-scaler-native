//
//  FeatureAdoptionGuideCta.swift
//  RecipeScalerNative
//
//  Spec 040 — CTA routing from `FeatureAdoptionGuideView` to handlers in
//  `AccountView` (scroll-to-section) and `AppShellView` (cross-tab /
//  sheet / external Safari).
//
//  Split into two independent environment keys so that `AccountView`'s
//  inner `.environment(\.featureAdoptionProfileScrollCta, …)` does NOT
//  override `AppShellView`'s outer `.environment(\.featureAdoptionAppCta, …)`.
//  Previously both were crammed into a single value, and the inner view
//  always won, silently swallowing the app-level actions.
//

import SwiftUI

// MARK: - App-level CTA (assistant, import, external Safari)

/// Cross-cutting actions handled by `AppShellView` (tab switch + sheet
/// presentation + external browser). Defaults to no-op so views outside
/// the AppShell subtree don't crash.
struct FeatureAdoptionAppCtaHandler: Sendable, Equatable {
    var openAssistant: @Sendable () -> Void
    var openImport: @Sendable () -> Void
    var openSafari: @Sendable (URL) -> Void

    static let noOp = FeatureAdoptionAppCtaHandler(
        openAssistant: {},
        openImport: {},
        openSafari: { _ in }
    )

    static func == (lhs: FeatureAdoptionAppCtaHandler, rhs: FeatureAdoptionAppCtaHandler) -> Bool {
        // Closures are not Equatable; treat as equal so SwiftUI doesn't
        // re-render purely because closure identity changed.
        true
    }
}

private struct FeatureAdoptionAppCtaKey: EnvironmentKey {
    static let defaultValue: FeatureAdoptionAppCtaHandler = .noOp
}

// MARK: - Profile-scroll CTA (telegram section, public profile section)

/// In-Profile scroll actions handled by `AccountView` via `ScrollViewReader`.
struct FeatureAdoptionProfileScrollCtaHandler: Sendable, Equatable {
    var openTelegramSection: @Sendable () -> Void
    var openPublicProfileSection: @Sendable () -> Void

    static let noOp = FeatureAdoptionProfileScrollCtaHandler(
        openTelegramSection: {},
        openPublicProfileSection: {}
    )

    static func == (lhs: FeatureAdoptionProfileScrollCtaHandler, rhs: FeatureAdoptionProfileScrollCtaHandler) -> Bool {
        true
    }
}

private struct FeatureAdoptionProfileScrollCtaKey: EnvironmentKey {
    static let defaultValue: FeatureAdoptionProfileScrollCtaHandler = .noOp
}

// MARK: - EnvironmentValues

extension EnvironmentValues {
    /// Spec 040 — assistant / import / external Safari.
    /// Wired by `AppShellView`. Read by `FeatureAdoptionGuideView`.
    var featureAdoptionAppCta: FeatureAdoptionAppCtaHandler {
        get { self[FeatureAdoptionAppCtaKey.self] }
        set { self[FeatureAdoptionAppCtaKey.self] = newValue }
    }

    /// Spec 040 — scroll to Telegram / public-profile sections inside Profile.
    /// Wired by `AccountView`. Read by `FeatureAdoptionGuideView`.
    var featureAdoptionProfileScrollCta: FeatureAdoptionProfileScrollCtaHandler {
        get { self[FeatureAdoptionProfileScrollCtaKey.self] }
        set { self[FeatureAdoptionProfileScrollCtaKey.self] = newValue }
    }
}
