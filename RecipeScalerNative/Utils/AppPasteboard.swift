//
//  AppPasteboard.swift
//  RecipeScalerNative
//
//  Spec 076 — app-owned clipboard writes so the import banner ignores them.
//

import UIKit

enum AppPasteboard {
    /// Owned by `AppContainer`. Weak store capture + MainActor hop; nil on logout.
    static var onOwnWrite: (@MainActor (Int) -> Void)?

    static func setString(_ value: String) {
        UIPasteboard.general.string = value
        let changeCount = UIPasteboard.general.changeCount
        Task { @MainActor in
            onOwnWrite?(changeCount)
        }
    }

    static func clearOwnWriteHandler() {
        onOwnWrite = nil
    }
}
