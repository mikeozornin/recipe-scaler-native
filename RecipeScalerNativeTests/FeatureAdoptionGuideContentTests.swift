//
//  FeatureAdoptionGuideContentTests.swift
//  RecipeScalerNativeTests
//
//  Spec 040 — positive invariants for guide content and generated media names.
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class FeatureAdoptionGuideContentTests: XCTestCase {
    func testEmojiNameIsPartOfTheReportAndHasNoGuide() {
        XCTAssertEqual(FeatureAdoptionItem.allCases.count, 11)
        XCTAssertEqual(FeatureAdoptionItem.namedWithEmoji.rawValue, "named_with_emoji")
        XCTAssertFalse(FeatureAdoptionItem.namedWithEmoji.isGuideAvailable)
    }

    func testEveryGuideItemHasStepsAndMediaSceneIds() {
        for item in FeatureAdoptionItem.allCases where item.isGuideAvailable {
            let content = item.guideContent
            XCTAssertFalse(content.howStepKeys.isEmpty, "\(item.rawValue) has no how steps")
            XCTAssertFalse(content.mediaSceneIds.isEmpty, "\(item.rawValue) has no media scenes")
        }
    }

    func testAssistantAndMCPExampleCountsMatchContract() {
        XCTAssertEqual(FeatureAdoptionItem.sentAssistantMessage.guideContent.exampleImages?.count, 5)
        XCTAssertEqual(FeatureAdoptionItem.connectedMcpAssistant.guideContent.exampleImages?.count, 3)
    }

    func testGeneratedMediaSceneNamesAreStable() {
        XCTAssertEqual(
            FeatureAdoptionItem.importedRecipe.guideContent.mediaSceneIds,
            [
                "imported_recipe.share-instruction",
                "imported_recipe.import-text",
                "imported_recipe.import-photo"
            ]
        )
        XCTAssertEqual(
            FeatureAdoptionItem.connectedMcpAssistant.guideContent.mediaSceneIds.last,
            "connected_mcp_assistant.save-command"
        )
    }
}
