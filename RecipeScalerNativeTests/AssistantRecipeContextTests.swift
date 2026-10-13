@testable import RecipeScalerNative
import XCTest

/// Spec 081 (T036, US3 review M2 and L1): «the assistant is open» and «the assistant covers
/// the recipe» are two flags. The phone sheet covers the recipe (hands-free off, the recipe
/// keeps its context and keep-awake when it leaves the screen); the iPad panel stands
/// beside it, and another section beside the panel releases the hidden recipe.
@MainActor
final class AssistantRecipeContextTests: XCTestCase {
    func test_sheet_coversRecipe() {
        let context = AssistantRecipeContext()

        context.assistantDidOpen(asPanel: false)

        XCTAssertTrue(context.isAssistantOpen)
        XCTAssertTrue(context.coversRecipe)
        XCTAssertFalse(context.isBesideRecipe)
    }

    func test_panel_standsBesideRecipe() {
        let context = AssistantRecipeContext()

        context.assistantDidOpen(asPanel: true)

        XCTAssertTrue(context.isAssistantOpen)
        XCTAssertFalse(context.coversRecipe)
        XCTAssertTrue(context.isBesideRecipe)
    }

    func test_sizeClassChange_movesBetweenPanelAndSheet() {
        let context = AssistantRecipeContext()
        context.assistantDidOpen(asPanel: true)

        context.assistantDidMove(asPanel: false)
        XCTAssertTrue(context.coversRecipe, "a compact window shows the sheet over the recipe")

        context.assistantDidMove(asPanel: true)
        XCTAssertFalse(context.coversRecipe, "a regular window shows the panel beside it")
        XCTAssertTrue(context.isAssistantOpen)
    }

    func test_sizeClassChange_withAssistantClosed_coversNothing() {
        let context = AssistantRecipeContext()

        context.assistantDidMove(asPanel: false)

        XCTAssertFalse(context.coversRecipe)
        XCTAssertFalse(context.isAssistantOpen)
    }

    func test_close_clearsBothFlags_keepsVisibleRecipe() {
        let context = AssistantRecipeContext()
        context.setVisibleRecipeId("r1")
        context.assistantDidOpen(asPanel: false)

        context.assistantDidClose()

        XCTAssertFalse(context.isAssistantOpen)
        XCTAssertFalse(context.coversRecipe)
        XCTAssertEqual(context.visibleRecipeId, "r1")
    }

    /// The hands-free arm flag follows «covers», not «open» (`YDocRecipeDetailView.syncAwakeScrollArm`).
    func test_handsFree_armedBesidePanel_disarmedUnderSheet() {
        let context = AssistantRecipeContext()
        var flags = AwakeScrollArmFlags()
        flags.detailVisible = true
        flags.isScreenAwakeActive = true
        flags.voiceEnabled = true

        context.assistantDidOpen(asPanel: true)
        flags.assistantSheetOpen = context.coversRecipe
        XCTAssertTrue(flags.isArmed, "the panel beside the recipe keeps hands-free on")

        context.assistantDidMove(asPanel: false)
        flags.assistantSheetOpen = context.coversRecipe
        XCTAssertFalse(flags.isArmed, "the sheet over the recipe turns hands-free off")
    }

    func test_panel_otherSection_releasesHiddenRecipe() {
        for tab in [AppTab.shopping, .discover, .profile] {
            let context = AssistantRecipeContext()
            context.setVisibleRecipeId("r1")
            context.assistantDidOpen(asPanel: true)

            XCTAssertTrue(context.releaseRecipe(hiddenBy: tab), "\(tab) hides the recipe")
            XCTAssertNil(context.visibleRecipeId, "\(tab) left the hidden recipe in the composer")
        }
    }

    func test_panel_recipesOrAssistant_keepsRecipe() {
        for tab in [AppTab.recipes, .assistant] {
            let context = AssistantRecipeContext()
            context.setVisibleRecipeId("r1")
            context.assistantDidOpen(asPanel: true)

            XCTAssertFalse(context.releaseRecipe(hiddenBy: tab))
            XCTAssertEqual(context.visibleRecipeId, "r1")
        }
    }

    /// The iPhone is unchanged: a section switch under the sheet (or with no assistant)
    /// leaves the recipe to its own `onDisappear`.
    func test_sheetOrClosed_otherSection_leavesRecipeToItsView() {
        let covered = AssistantRecipeContext()
        covered.setVisibleRecipeId("r1")
        covered.assistantDidOpen(asPanel: false)
        XCTAssertFalse(covered.releaseRecipe(hiddenBy: .shopping))
        XCTAssertEqual(covered.visibleRecipeId, "r1")

        let closed = AssistantRecipeContext()
        closed.setVisibleRecipeId("r1")
        XCTAssertFalse(closed.releaseRecipe(hiddenBy: .shopping))
        XCTAssertEqual(closed.visibleRecipeId, "r1")
    }

    func test_resetForLogout_clearsEveryFlag() {
        let context = AssistantRecipeContext()
        context.setVisibleRecipeId("r1")
        context.assistantDidOpen(asPanel: false)

        context.resetForLogout()

        XCTAssertFalse(context.isAssistantOpen)
        XCTAssertFalse(context.coversRecipe)
        XCTAssertNil(context.visibleRecipeId)
    }
}
