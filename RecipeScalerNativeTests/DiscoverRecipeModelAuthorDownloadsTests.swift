//
//  DiscoverRecipeModelAuthorDownloadsTests.swift
//  RecipeScalerNativeTests
//
//  Spec 072 review fix — the feed recipe page must honor the author's
//  `allowRecipeDownloads` public-profile preference (web parity:
//  `public-recipe.tsx` fetches the profile and gates the copy CTA on
//  `!== false`).
//
//  Covered (all via the injected `fetchAuthorProfile` seam, no network):
//    - profile resolves `false` → the model reports `authorAllowsDownloads = false`
//    - profile resolves `true` → `true`
//    - fetch throws → swallowed, `nil` (web parity: stay on the default-on fallback)
//    - nil / empty username → no fetch at all
//    - share URL: profile URL once the profile resolves, `/public/{id}` otherwise
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class DiscoverRecipeModelAuthorDownloadsTests: XCTestCase {

    func test_profileFalse_setsAuthorAllowsDownloadsFalse() async {
        var requested: String?
        let model = DiscoverRecipeModel(api: .shared) { username in
            requested = username
            return false
        }

        await model.updateAuthorDownloads(username: "author")

        XCTAssertEqual(requested, "author")
        XCTAssertEqual(model.authorAllowsDownloads, false)
    }

    func test_profileTrue_setsAuthorAllowsDownloadsTrue() async {
        let model = DiscoverRecipeModel(api: .shared) { _ in true }

        await model.updateAuthorDownloads(username: "author")

        XCTAssertEqual(model.authorAllowsDownloads, true)
    }

    func test_fetchFailure_swallowed_staysNil() async {
        struct FetchError: Error {}
        let model = DiscoverRecipeModel(api: .shared) { _ in
            throw FetchError()
        }

        await model.updateAuthorDownloads(username: "author")

        XCTAssertNil(
            model.authorAllowsDownloads,
            "a failed profile fetch must stay on the view's default (nil), like web's default-on"
        )
    }

    func test_nilUsername_doesNotFetch() async {
        let model = DiscoverRecipeModel(api: .shared) { _ in true }

        await model.updateAuthorDownloads(username: nil)

        XCTAssertNil(model.authorAllowsDownloads)
    }

    func test_emptyUsername_doesNotFetch() async {
        let model = DiscoverRecipeModel(api: .shared) { _ in true }

        await model.updateAuthorDownloads(username: "")

        XCTAssertNil(model.authorAllowsDownloads)
    }

    func test_shareURL_profileResolved_usesProfileRecipeURL() async {
        let model = DiscoverRecipeModel(api: .shared) { _ in true }

        await model.updateAuthorDownloads(username: "author")

        XCTAssertEqual(
            model.shareURL(recipeId: "abc"),
            PublicURLBuilder.profileRecipeURL(username: "author", recipeId: "abc")
        )
    }

    func test_shareURL_profileFetchFailed_fallsBackToLegacyURL() async {
        struct FetchError: Error {}
        let model = DiscoverRecipeModel(api: .shared) { _ in
            throw FetchError()
        }

        await model.updateAuthorDownloads(username: "author")

        XCTAssertEqual(
            model.shareURL(recipeId: "abc"),
            PublicURLBuilder.recipeShareURL(recipeId: "abc"),
            "a disabled / missing profile must not produce a /public/@/ link that 404s"
        )
    }

    func test_shareURL_noProfileFetch_usesLegacyURL() {
        let model = DiscoverRecipeModel(api: .shared) { _ in true }

        XCTAssertEqual(model.shareURL(recipeId: "abc"), PublicURLBuilder.recipeShareURL(recipeId: "abc"))
    }
}
