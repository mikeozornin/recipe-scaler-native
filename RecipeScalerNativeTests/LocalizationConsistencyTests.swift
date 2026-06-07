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
            "recipe.list.add",
            "telegram.connect",
            "telegram.disconnect",
            "discover.nav.discover",
            "discover.nav.import",
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
            "import.success",
            "import.success-multiple",
            "import.error",
            "import.error-captcha",
            "import.error-static",
            "import.error-invalid-response",
            "import.error-too-many-recipes",
            "import.error-photos-empty",
            "import.error-photo-too-large",
            "import.error-photo-invalid-type",
            "import.error-too-many-photos",
            "import.error-photo-corrupt",
            "import.offline-unavailable",
            "import.validation.invalid-servings",
            "import.validation.recipe-import-failed",
            "common.cancel",
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
            "privacy.title",
            "privacy.link",
            "privacy.serverKnows.1",
            "privacy.aiServices.1",
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
            "search.recipes"
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
}
