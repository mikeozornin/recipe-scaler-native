//
//  Bundle+Language.swift
//  RecipeScalerNative
//
//  In-app language switcher: overrides Bundle.localizedString(forKey:value:table:)
//  so that `String(localized:)`, `LocalizedStringKey`, and `Text("key")` all resolve
//  translations from the user-selected language bundle instead of the system language.
//
//  The override is a no-op until `AppLanguagePreference.apply(_:)` is called at launch.
//  Swizzle is installed once via `+load` on app binary load (before SwiftUI spins up).
//

import Foundation
import RecipeScalerCore

private var kBundleMainKey: UInt = 0

extension Bundle {
    /// Thread-safe storage of the current language bundle override.
    private static var languageBundle: Bundle? {
        get { objc_getAssociatedObject(self, &kBundleMainKey) as? Bundle }
        set { objc_setAssociatedObject(self, &kBundleMainKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Apply (or clear) the language override. Call from `AppLanguagePreference.apply`.
    /// Passing `nil` restores standard system-language behavior.
    static func setLanguageOverride(_ language: String?) {
        guard let language else {
            languageBundle = nil
            return
        }
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            languageBundle = nil
            return
        }
        languageBundle = bundle
    }

    /// Resolve a localized string from the currently selected language bundle.
    ///
    /// Unlike `String(localized:)`, this is guaranteed to honor the in-app language
    /// override: it reads straight from the override `.lproj` bundle (falling back to
    /// `Bundle.main` / system language when no override is set). Use this when you need a
    /// concrete `String` that must reflect the runtime-selected language right now
    /// (e.g. a verbatim navigation title) rather than relying on SwiftUI's lazy
    /// `LocalizedStringKey` resolution.
    static func currentLocalizedString(_ key: String, table: String? = nil) -> String {
        (languageBundle ?? .main).localizedString(forKey: key, value: nil, table: table)
    }

    /// Install swizzle once. Idempotent.
    static func installLanguageOverrideSwizzle() {
        struct Token { static var once: Bool = false }
        guard !Token.once else { return }
        Token.once = true

        let original = class_getInstanceMethod(
            Bundle.self,
            #selector(Bundle.localizedString(forKey:value:table:))
        )
        let swizzled = class_getInstanceMethod(
            Bundle.self,
            #selector(Bundle.rs_localizedString(forKey:value:table:))
        )
        guard let original, let swizzled else { return }
        method_exchangeImplementations(original, swizzled)
    }

    @objc fileprivate func rs_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let override = Bundle.languageBundle
        let isMain = self === Bundle.main

        // Path 1: Caller is an lproj sub-bundle (SwiftUI's preferred path for Text/LocalizedStringKey).
        // Redirect to override lproj if it's a different language.
        if let override, !isMain {
            let selfIsOverride = override.bundlePath == self.bundlePath
            if !selfIsOverride, self.bundlePath.contains(".lproj") {
                return override.rs_localizedString(forKey: key, value: value, table: tableName)
            }
        }

        // Path 2: Caller is Bundle.main (String(localized:) or direct call).
        // Redirect to override bundle.
        if let override, isMain {
            return override.rs_localizedString(forKey: key, value: value, table: tableName)
        }

        // Fallback: call original implementation.
        return rs_localizedString(forKey: key, value: value, table: tableName)
    }
}

// MARK: - Pluralization
// Merged from RecipeScalerNative/Utils/Pluralization.swift

extension Bundle {
    /// Format a count-dependent localized string using the in-app language preference.
    ///
    /// This is a convenience over `Bundle.pluralizedString(key:count:table:locale:)`
    /// that passes `AppLanguagePreference.current.locale` so the plural rule matches
    /// the runtime-selected language even when the system locale differs.
    static func appPluralizedString(key: String, count: Int, table: String? = nil) -> String {
        pluralizedString(
            key: key,
            count: count,
            table: table,
            locale: AppLanguagePreference.current.locale,
            localizedString: { currentLocalizedString($0, table: $1) }
        )
    }
}
