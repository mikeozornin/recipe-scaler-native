//
//  PublicURLBuilderTests.swift
//  RecipeScalerNativeTests
//

import XCTest
@testable import RecipeScalerNative

final class PublicURLBuilderTests: XCTestCase {

    private var previousLanguageRaw: String?

    override func setUp() {
        super.setUp()
        previousLanguageRaw = UserDefaults.standard.string(forKey: AppLanguagePreference.storageKey)
    }

    override func tearDown() {
        if let previousLanguageRaw {
            UserDefaults.standard.set(previousLanguageRaw, forKey: AppLanguagePreference.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguagePreference.storageKey)
        }
        super.tearDown()
    }

    func testAboutAndPrivacyURLsIncludeRussianLang() {
        UserDefaults.standard.set(AppLanguagePreference.ru.rawValue, forKey: AppLanguagePreference.storageKey)

        let about = PublicURLBuilder.aboutURL.absoluteString
        let privacy = PublicURLBuilder.privacyURL.absoluteString

        XCTAssertTrue(about.hasSuffix("/#/about?lang=ru"), about)
        XCTAssertTrue(privacy.hasSuffix("/#/privacy?lang=ru"), privacy)
        XCTAssertTrue(about.hasPrefix("https://"), about)
        XCTAssertTrue(privacy.hasPrefix("https://"), privacy)
    }

    func testAboutAndPrivacyURLsIncludeEnglishLang() {
        UserDefaults.standard.set(AppLanguagePreference.en.rawValue, forKey: AppLanguagePreference.storageKey)

        let about = PublicURLBuilder.aboutURL.absoluteString
        let privacy = PublicURLBuilder.privacyURL.absoluteString

        XCTAssertTrue(about.hasSuffix("/#/about?lang=en"), about)
        XCTAssertTrue(privacy.hasSuffix("/#/privacy?lang=en"), privacy)
        XCTAssertTrue(about.hasPrefix("https://"), about)
        XCTAssertTrue(privacy.hasPrefix("https://"), privacy)
    }
}
