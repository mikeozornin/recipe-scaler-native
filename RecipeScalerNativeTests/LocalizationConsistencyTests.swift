//
//  LocalizationConsistencyTests.swift
//

import XCTest

final class LocalizationConsistencyTests: XCTestCase {
    /// Smoke check that the keys used in the freshly migrated SwiftUI call sites
    /// actually exist in the compiled Localizable.strings for both supported languages.
    /// Acts as a regression net for the "literal string as LocalizedStringKey" pattern.
    func testCriticalKeysResolveInBothLanguages() {
        let keys = [
            "shopping.title",
            "shopping.section.to-buy",
            "shopping.section.purchased",
            "shopping.share-button",
            "shopping.clear-bought",
            "shopping.sort.by-recipe",
            "shopping.sort.az",
            "shopping.empty-to-buy",
            "shopping.empty-to-buy-all-done",
            "shopping.copy-as-text",
            "shopping.items-added.one",
            "shopping.items-added.few",
            "shopping.items-added.many",
            "recipe.list.add",
            "recipes.add-button",
            "telegram.connect",
            "telegram.disconnect",
            "discover.nav.discover",
            "discover.nav.import",
            "discover.title",
            "discover.loading",
            "discover.error",
            "discover.error-server",
            "discover.empty",
            "discover.empty-description",
            "discover.curated-collections",
            "discover.featured-chefs",
            "discover.collection.title",
            "discover.collection.loading",
            "discover.collection.not-found",
            "discover.collection.not-found-description",
            "discover.collection.empty",
            "discover.collection.by-author",
            "discover.collection.recipe-count.one",
            "discover.collection.recipe-count.few",
            "discover.collection.recipe-count.many",
            "discover.recipe.copy-to-me",
            "discover.recipe.copying",
            "discover.recipe.copied",
            "discover.recipe.failed",
            "discover.recipe.loading",
            "discover.recipe.prep-time",
            "discover.recipe.cook-time",
            "discover.recipe.servings",
            "discover.recipe.ingredients",
            "discover.recipe.steps",
            "discover.recipe.open-in-my-recipes",
            "discover.profile.title",
            "discover.profile.not-found",
            "discover.profile.not-found-description",
            "discover.profile.recipe-count.one",
            "discover.profile.recipe-count.few",
            "discover.profile.recipe-count.many",
            "discover.profile.no-recipes",
            "discover.profile.share-mode.one_by_one",
            "discover.profile.share-mode.all",
            "discover.profile.share-mode.with_images_and_steps",
            "import.title",
            "import.description",
            "import.tab-text",
            "import.tab-photo",
            "import.mode-accessibility",
            "import.text-placeholder",
            "import.text-file-hint",
            "import.choose-photos",
            "import.photo-count",
            "import.photo-helper",
            "import.lets-go",
            "import.try-later",
            "import.success.one",
            "import.success.few",
            "import.success.many",
            "import.error",
            "import.error-captcha",
            "import.error-static",
            "import.error-invalid-response",
            "import.error-too-many-recipes.one",
            "import.error-too-many-recipes.few",
            "import.error-too-many-recipes.many",
            "import.error-photos-empty",
            "import.error-photo-too-large",
            "import.error-photo-invalid-type",
            "import.error-too-many-photos.one",
            "import.error-too-many-photos.few",
            "import.error-too-many-photos.many",
            "import.error-photo-corrupt",
            "import.offline-unavailable",
            "import.validation.invalid-servings",
            "import.validation.recipe-import-failed",
            "common.cancel",
            "common.close",
            "common.delete-image",
            "account.sync.title",
            "account.sync.never",
            "account.collections-layout.label",
            "account.collections-layout.list",
            "account.collections-layout.folders",
            "account.reminders.sync",
            "account.reminders.sync.footer",
            "account.reminders.denied",
            "account.reminders.list.label",
            "account.reminders.list.create-dedicated",
            "account.reminders.list.existing-header",
            "account.reminders.note.from",
            "privacy.link",
            "collections.title",
            "collections.view-flat",
            "collections.view-collections",
            "collections.view-flat-tooltip",
            "collections.view-collections-tooltip",
            "collections.all-recipes",
            "collections.new",
            "collections.create-new",
            "collections.new-placeholder",
            "collections.create",
            "collections.collection-color",
            "collections.rename",
            "collections.rename-placeholder",
            "collections.delete",
            "collections.delete-confirm-title",
            "collections.delete-confirm-description",
            "collections.assign-title",
            "collections.assign-tooltip",
            "collections.assign-empty",
            "collections.manage-recipes",
            "collections.select-recipes",
            "collections.uncategorized",
            "collections.empty",
            "collections.empty-folder",
            "collections.back",
            "collections.done",
            "recipes.no-title",
            "recipes.no-recipes",
            "search.recipes",
            "auth.welcome-title",
            "auth.welcome-subtitle",
            "auth.new-user",
            "auth.used-before",
            "auth.login",
            "auth.seed-placeholder",
            "sync.status.recipes.hint.offline.one",
            "sync.status.recipes.hint.offline.few",
            "sync.status.recipes.hint.offline.many",
            "sync.status.images.downloading",
            "mobile-timer.panel.title",
            "timer.example.title",
            "timer.example.active-timers",
            "timer.example.all-timers",
            "timer.example.no-active-timers",
            "timer.example.no-timers",
            "timer.example.seconds.one",
            "timer.example.seconds.few",
            "timer.example.seconds.many",
            "timer.siri.default-name",
            "timer.siri.intent.title",
            "timer.siri.intent.description",
            "timer.siri.parameter.hours.description",
            "timer.siri.parameter.minutes.description",
            "timer.siri.parameter.name.description",
            "timer.siri.dialog.hours-only",
            "timer.siri.dialog.minutes-only",
            "timer.siri.dialog.hours-and-minutes",
            "timer.siri.error.zero-duration",
            "timer.siri.hours.one",
            "timer.siri.hours.few",
            "timer.siri.hours.many",
            "timer.siri.minutes.one",
            "timer.siri.minutes.few",
            "timer.siri.minutes.many",
            // MARK: Spec 031 — error-message i18n (AuthError / APIError / YrsError / services)
            "api.error.invalid-url",
            "api.error.invalid-response",
            "api.error.decoding",
            "api.error.unauthorized",
            "api.error.http-4xx",
            "api.error.http-5xx",
            "api.error.server-generic",
            "auth.error.keychain",
            "auth.error.decoding",
            "auth.error.network",
            "auth.error.invalid-seed",
            "auth.error.seed-not-found",
            "auth.error.invalid-response",
            "auth.error.api-generic",
            "auth.login.failed",
            "auth.register.failed",
            "legacyAuth.banner.message",
            "legacyAuth.banner.details",
            "legacyAuth.banner.more",
            "yrs.error.technical",
            "yrs.error.apply-failed",
            "yrs.error.transaction",
            "account.profile.load-failed",
            "account.sharing.load-failed",
            "account.sharing.update-failed",
            "account.settings.load-failed",
            "account.error.unreachable",
            "account.error.generic",
            "discover.fetch-failed",
            "discover.collection-failed",
            "discover.recipe-failed",
            "discover.clone-failed",
            "discover.copy-failed",
            "discover.public-recipe-failed",
            "discover.public-profile-failed",
            "recipe.image.upload-failed",
            "recipe.image.delete-failed",
            "recipe.import.no-images",
            "recipe.import.failed",
            "account.data.import.folder-failed %@ %@",
            "account.data.import.folder-empty-skipped",
            "sharing.update-failed",
            "telegram.status-failed",
            "telegram.failed-to-get-code",
            "telegram.failed-to-disconnect",
            "assistant.message.empty",
            "assistant.message.too-long",
            "assistant.stream.http-error",
            // MARK: Spec 031 — Socket.IO sync_error (SyncErrorCode)
            "sync.error.ownership",
            "sync.error.recipe-deleted",
            "sync.error.empty-update",
            "sync.error.invalid-update",
            "sync.error.generic",
            // MARK: Spec 038 — feature adoption section
            "account.feature-adoption.title",
            "account.feature-adoption.progress %d %d",
            "account.feature-adoption.item.installed_native_app",
            "account.feature-adoption.item.installed_native_app.footnote",
            "account.feature-adoption.item.installed_watch_app",
            "account.feature-adoption.item.installed_watch_app.footnote",
            "account.feature-adoption.item.created_recipe",
            "account.feature-adoption.item.created_recipe.footnote",
            "account.feature-adoption.item.used_shopping_list",
            "account.feature-adoption.item.used_shopping_list.footnote",
            "account.feature-adoption.item.imported_recipe",
            "account.feature-adoption.item.imported_recipe.footnote",
            "account.feature-adoption.item.created_collection",
            "account.feature-adoption.item.created_collection.footnote",
            "account.feature-adoption.item.sent_assistant_message",
            "account.feature-adoption.item.sent_assistant_message.footnote",
            "account.feature-adoption.item.connected_telegram",
            "account.feature-adoption.item.connected_telegram.footnote",
            "account.feature-adoption.item.connected_mcp_assistant",
            "account.feature-adoption.item.connected_mcp_assistant.footnote",
            "account.feature-adoption.item.shared_recipe",
            "account.feature-adoption.item.shared_recipe.footnote",
            "account.feature-adoption.state.done",
            "account.feature-adoption.state.pending"
        ]

        for lang in ["en", "ru"] {
            guard let lproj = Bundle.main.path(forResource: lang, ofType: "lproj"),
                  let bundle = Bundle(path: lproj) else {
                XCTFail("Missing \(lang).lproj in test bundle")
                continue
            }
            for key in keys {
                let resolved = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(
                    resolved,
                    key,
                    "Key \(key) did not resolve in \(lang) (returned key as-is — missing entry)"
                )
            }
        }
    }

    /// Spec 025 T024 — verify `share-extension.*` keys from `Shared.xcstrings`
    /// (RecipeScalerCore) have entries for both en and ru. We parse the source
    /// `.xcstrings` JSON directly because RecipeScalerCore is statically linked
    /// into the test host, so `Bundle(for:).url(forResource:"RecipeScalerCore",
    /// withExtension:"bundle")` returns nil and `Bundle.main` does not contain
    /// the merged Shared.xcstrings in the test runtime.
    func testShareExtensionKeysResolveInBothLanguages() throws {
        let keys = Set([
            "share-extension.title",
            "share-extension.button-import",
            "share-extension.button-open",
            "share-extension.button-retry",
            "share-extension.button-cancel",
            "share-extension.importing",
            "share-extension.success",
            "share-extension.error-no-content",
            "share-extension.error-not-signed-in",
            "share-extension.error-network"
        ])

        // Locate Shared.xcstrings relative to the test file's repository root.
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sharedXcstrings = sourceRoot
            .appendingPathComponent("RecipeScalerCore/Resources/Shared.xcstrings")

        guard FileManager.default.fileExists(atPath: sharedXcstrings.path) else {
            XCTFail("Shared.xcstrings not found at \(sharedXcstrings.path)")
            return
        }

        let data = try Data(contentsOf: sharedXcstrings)
        let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        guard let strings = object?["strings"] as? [String: Any] else {
            XCTFail("Shared.xcstrings: missing top-level 'strings' object")
            return
        }

        for key in keys {
            guard let entry = strings[key] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                XCTFail("Key '\(key)' missing from Shared.xcstrings")
                continue
            }
            for lang in ["en", "ru"] {
                guard let langEntry = localizations[lang] as? [String: Any],
                      let stringUnit = langEntry["stringUnit"] as? [String: Any],
                      let value = stringUnit["value"] as? String,
                      !value.isEmpty else {
                    XCTFail("Key '\(key)' has no non-empty \(lang) value in Shared.xcstrings")
                    continue
                }
            }
        }
    }
}
