//
//  AssistantPendingActionTests.swift
//  RecipeScalerNativeTests
//
//  Spec 021 US5 parity — verify assistant pending action + widget coexistence and
//  user-bubble label resolution (mirror of web `assistant-message-list.tsx:getResolvedUserMessageText`).
//

import XCTest
@testable import RecipeScalerNative

final class AssistantPendingActionTests: XCTestCase {

    // MARK: - Metadata decoding

    func testDecodesWidgetAndPendingActionFromSameMessage() throws {
        // Real-shape payload from /api/assistant/threads/:id/messages — server emits BOTH
        // `interactiveWidget` (the actual quick-reply buttons) AND `pendingAction` (the backend
        // confirmation gate) on a single assistant message.
        let json = """
        {
            "attachments": null,
            "interactiveWidget": {
                "type": "quick_replies",
                "options": [
                    {"label": "Удалить", "value": "confirm_delete"},
                    {"label": "Отмена", "value": "cancel_delete"}
                ]
            },
            "pendingAction": {
                "id": "01997de3-e1b0-4af6-9dc0-ca558bb62686",
                "status": "pending",
                "toolName": "delete_recipe",
                "targetLabel": "__Тест для нативки",
                "message": "Вы уверены, что хотите навсегда удалить этот рецепт?",
                "confirmLabel": "Удалить",
                "cancelLabel": "Отмена",
                "confirmValue": "confirm_delete",
                "cancelValue": "cancel_delete",
                "createdAt": "2026-06-15T21:10:58.260Z",
                "expiresAt": "2026-06-15T21:20:58.260Z"
            },
            "actionResolution": null,
            "followUpSuggestions": null
        }
        """.data(using: .utf8)!

        let metadata = try JSONDecoder().decode(AssistantMessageMetadata.self, from: json)

        XCTAssertNotNil(metadata.interactiveWidget)
        XCTAssertEqual(metadata.pendingAction?.status, .pending)
        XCTAssertEqual(metadata.pendingAction?.confirmValue, "confirm_delete")
        XCTAssertNil(metadata.actionResolution)
    }

    func testDecodesActionResolutionOnUserMessageAfterConfirm() throws {
        // After the user taps the confirm widget option, the server persists the user message
        // with content = "confirm_delete" and attaches `actionResolution.source == "widget"`
        // plus the same `pendingAction` snapshot so the client can render a friendlier label.
        let json = """
        {
            "attachments": null,
            "interactiveWidget": null,
            "pendingAction": {
                "id": "01997de3-e1b0-4af6-9dc0-ca558bb62686",
                "status": "consumed",
                "toolName": "delete_recipe",
                "targetLabel": null,
                "message": null,
                "confirmLabel": "Удалить",
                "cancelLabel": "Отмена",
                "confirmValue": "confirm_delete",
                "cancelValue": "cancel_delete",
                "createdAt": "2026-06-15T21:10:58.260Z",
                "expiresAt": "2026-06-15T21:20:58.260Z"
            },
            "actionResolution": {
                "pendingActionId": "01997de3-e1b0-4af6-9dc0-ca558bb62686",
                "disposition": "confirmed",
                "source": "widget",
                "createdAt": "2026-06-15T21:11:05.000Z"
            },
            "followUpSuggestions": null
        }
        """.data(using: .utf8)!

        let metadata = try JSONDecoder().decode(AssistantMessageMetadata.self, from: json)

        XCTAssertEqual(metadata.actionResolution?.source, "widget")
        XCTAssertEqual(metadata.actionResolution?.disposition, "confirmed")
        XCTAssertEqual(metadata.pendingAction?.status, .consumed)
    }

    // MARK: - Resolved user-bubble text (web `getResolvedUserMessageText` parity)

    func testUserBubbleShowsConfirmLabelForWidgetConfirmedMessage() {
        let message = AssistantMessage(
            id: "user-1",
            role: "user",
            text: "confirm_delete",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: nil,
                interactiveWidget: nil,
                pendingAction: makePendingAction(),
                actionResolution: makeResolution(source: "widget", disposition: "confirmed"),
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertEqual(AssistantMessageCopyText.text(for: message), "Удалить")
    }

    func testUserBubbleShowsCancelLabelForWidgetCancelledMessage() {
        let message = AssistantMessage(
            id: "user-2",
            role: "user",
            text: "cancel_delete",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: nil,
                interactiveWidget: nil,
                pendingAction: makePendingAction(),
                actionResolution: makeResolution(source: "widget", disposition: "cancelled"),
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertEqual(AssistantMessageCopyText.text(for: message), "Отмена")
    }

    func testUserBubbleKeepsRawTextWhenSourceIsTyped() {
        // Web parity: only `source == "widget"` triggers the label substitution.
        // For typed confirmations the user already typed something readable.
        let message = AssistantMessage(
            id: "user-3",
            role: "user",
            text: "confirm_delete",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: nil,
                interactiveWidget: nil,
                pendingAction: makePendingAction(),
                actionResolution: makeResolution(source: "typed", disposition: "confirmed"),
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertEqual(AssistantMessageCopyText.text(for: message), "confirm_delete")
    }

    func testUserBubbleKeepsRawTextWhenNoActionResolution() {
        let message = AssistantMessage(
            id: "user-4",
            role: "user",
            text: "Удали плиз рецепт",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: nil,
                interactiveWidget: nil,
                pendingAction: nil,
                actionResolution: nil,
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertEqual(AssistantMessageCopyText.text(for: message), "Удали плиз рецепт")
    }

    func testOptimisticUserBubbleKeepsFriendlyDisplayText() {
        // When the user taps a quick-reply widget, the optimistic bubble is created with the
        // widget label (e.g. "Удалить") rather than the raw value ("confirm_delete"). Until the
        // server responds with actionResolution metadata, the bubble should simply show that text.
        let message = AssistantMessage(
            id: "user-optimistic",
            role: "user",
            text: "Удалить",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: nil,
                interactiveWidget: nil,
                pendingAction: nil,
                actionResolution: nil,
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertEqual(AssistantMessageCopyText.text(for: message), "Удалить")
    }

    func testValueNormalizerIsCaseInsensitiveAndTrims() {
        XCTAssertEqual(AssistantMessageValueNormalizer.normalize("  Confirm_Delete  "), "confirm_delete")
        XCTAssertEqual(AssistantMessageValueNormalizer.normalize("CANCEL_DELETE"), "cancel_delete")
    }

    // MARK: - Footer presentation (web parity: widget only)

    func testWidgetRenderedWhenInteractiveWidgetPresent() throws {
        let metadata = try decodeMetadataWithWidgetAndPendingAction()

        XCTAssertTrue(
            AssistantMessageFooterPresentation.shouldRenderWidget(
                role: "assistant",
                isStreaming: false,
                isLastMessage: true,
                isSending: false,
                widgetSubmitted: false,
                metadata: metadata
            )
        )
    }

    func testWidgetHiddenAfterSubmit() throws {
        let metadata = try decodeMetadataWithWidgetAndPendingAction()

        XCTAssertFalse(
            AssistantMessageFooterPresentation.shouldRenderWidget(
                role: "assistant",
                isStreaming: false,
                isLastMessage: true,
                isSending: false,
                widgetSubmitted: true,
                metadata: metadata
            )
        )
    }

    func testPendingActionMetadataAloneDoesNotRenderFooterUI() throws {
        let json = """
        {
            "attachments": null,
            "interactiveWidget": null,
            "pendingAction": {
                "id": "01997de3-e1b0-4af6-9dc0-ca558bb62686",
                "status": "pending",
                "toolName": "delete_recipe",
                "targetLabel": "Delete",
                "message": "Confirm deletion?",
                "confirmLabel": "Удалить",
                "cancelLabel": "Отмена",
                "confirmValue": "confirm_delete",
                "cancelValue": "cancel_delete",
                "createdAt": "2026-06-15T21:10:58.260Z",
                "expiresAt": "2026-06-15T21:20:58.260Z"
            },
            "actionResolution": null,
            "followUpSuggestions": null
        }
        """.data(using: .utf8)!
        let metadata = try JSONDecoder().decode(AssistantMessageMetadata.self, from: json)

        XCTAssertFalse(
            AssistantMessageFooterPresentation.shouldRenderWidget(
                role: "assistant",
                isStreaming: false,
                isLastMessage: true,
                isSending: false,
                widgetSubmitted: false,
                metadata: metadata
            )
        )
    }

    // MARK: - Attachment fallback still works

    func testUserBubbleShowsRecipeNameWhenOnlyAttachmentPresent() {
        let message = AssistantMessage(
            id: "user-5",
            role: "user",
            text: "a33df68f-b657-47f6-825d-da5ee5c2972a",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: [
                    AssistantRecipeAttachment(
                        recipeId: "a33df68f-b657-47f6-825d-da5ee5c2972a",
                        recipeName: "Борщ",
                        recipeColor: nil
                    )
                ],
                interactiveWidget: nil,
                pendingAction: nil,
                actionResolution: nil,
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertEqual(AssistantMessageCopyText.text(for: message), "Борщ")
    }

    // MARK: - Chips-only presentation (web `userMessageShowsOnlyRecipeAttachmentChips` parity)

    func testChipsOnlyWhenUserTextIsEmptyAndAttachmentsPresent() {
        let message = AssistantMessage(
            id: "user-chips-1",
            role: "user",
            text: "   ",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: [
                    AssistantRecipeAttachment(recipeId: "id-1", recipeName: "Борщ", recipeColor: nil),
                    AssistantRecipeAttachment(recipeId: "id-2", recipeName: "Паста", recipeColor: nil)
                ],
                interactiveWidget: nil,
                pendingAction: nil,
                actionResolution: nil,
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertTrue(AssistantUserBubblePresentation.showsAttachmentChipsOnly(message: message))
        XCTAssertEqual(AssistantMessageCopyText.text(for: message), "Борщ, Паста")
    }

    func testChipsOnlyWhenUserTextEqualsSingleRecipeId() {
        let message = AssistantMessage(
            id: "user-chips-2",
            role: "user",
            text: "a33df68f-b657-47f6-825d-da5ee5c2972a",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: [
                    AssistantRecipeAttachment(
                        recipeId: "a33df68f-b657-47f6-825d-da5ee5c2972a",
                        recipeName: "Борщ",
                        recipeColor: nil
                    )
                ],
                interactiveWidget: nil,
                pendingAction: nil,
                actionResolution: nil,
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertTrue(AssistantUserBubblePresentation.showsAttachmentChipsOnly(message: message))
        XCTAssertEqual(AssistantMessageCopyText.text(for: message), "Борщ")
    }

    func testNotChipsOnlyWhenUserTextIsRealQuestion() {
        let message = AssistantMessage(
            id: "user-chips-3",
            role: "user",
            text: "Как удвоить этот рецепт?",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: [
                    AssistantRecipeAttachment(recipeId: "id-1", recipeName: "Борщ", recipeColor: nil)
                ],
                interactiveWidget: nil,
                pendingAction: nil,
                actionResolution: nil,
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertFalse(AssistantUserBubblePresentation.showsAttachmentChipsOnly(message: message))
        XCTAssertEqual(AssistantMessageCopyText.text(for: message), "Как удвоить этот рецепт?")
    }

    func testNotChipsOnlyForAssistantMessages() {
        let message = AssistantMessage(
            id: "assistant-chips-4",
            role: "assistant",
            text: "",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: [
                    AssistantRecipeAttachment(recipeId: "id-1", recipeName: "Борщ", recipeColor: nil)
                ],
                interactiveWidget: nil,
                pendingAction: nil,
                actionResolution: nil,
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertFalse(AssistantUserBubblePresentation.showsAttachmentChipsOnly(message: message))
    }

    // MARK: - Attachment chip resolver (web `resolveAttachmentRecipeDisplay` parity)

    func testResolverPrefersMetadataNameAndColor() {
        let attachment = AssistantRecipeAttachment(recipeId: "id-1", recipeName: "Борщ", recipeColor: "#FF0000")
        let display = AssistantAttachmentChipResolver.resolve(
            attachment,
            fallbackNameById: ["id-1": "Другой"],
            fallbackColorById: ["id-1": "#00FF00"]
        )

        XCTAssertEqual(display.name, "Борщ")
        XCTAssertEqual(display.color, "#FF0000")
    }

    func testResolverFallsBackToCollectionByNameIgnoringCase() {
        let attachment = AssistantRecipeAttachment(
            recipeId: "CE78C4CC-E292-462B-B548-7EFDCB036AC1",
            recipeName: nil,
            recipeColor: nil
        )
        let display = AssistantAttachmentChipResolver.resolve(
            attachment,
            fallbackNameById: ["ce78c4cc-e292-462b-b548-7efdcb036ac1": "To delete"],
            fallbackColorById: ["ce78c4cc-e292-462b-b548-7efdcb036ac1": "#00FF00"]
        )

        XCTAssertEqual(display.name, "To delete")
        XCTAssertEqual(display.color, "#00FF00")
    }

    func testResolverTreatsWhitespaceOnlyNameAsMissing() {
        let attachment = AssistantRecipeAttachment(recipeId: "id-9", recipeName: "   ", recipeColor: nil)
        let display = AssistantAttachmentChipResolver.resolve(
            attachment,
            fallbackNameById: ["id-9": "Паста"],
            fallbackColorById: [:]
        )

        XCTAssertEqual(display.name, "Паста")
    }

    func testResolverTreatsEmptyFallbackAsMissingAndUsesRecipeId() {
        let attachment = AssistantRecipeAttachment(recipeId: "id-empty", recipeName: nil, recipeColor: "   ")
        let display = AssistantAttachmentChipResolver.resolve(
            attachment,
            fallbackNameById: ["id-empty": ""],
            fallbackColorById: ["id-empty": "   "]
        )

        XCTAssertEqual(display.name, "id-empty")
        XCTAssertNil(display.color)
    }

    func testResolverFallsBackToRecipeIdWhenNothingElseKnown() {
        let attachment = AssistantRecipeAttachment(recipeId: "id-42", recipeName: nil, recipeColor: nil)
        let display = AssistantAttachmentChipResolver.resolve(attachment)

        XCTAssertEqual(display.name, "id-42")
        XCTAssertNil(display.color)
    }

    func testLookupsMapEmptyNameToNoTitleAndOmitEmptyColor() {
        let untitled = Bundle.currentLocalizedString("recipes.no-title")
        let entries = [
            CollectionEntry(
                id: "ID-1",
                name: "   ",
                color: "",
                imageUrl: nil,
                updatedAt: "2026-01-01T00:00:00.000Z",
                deleted: false,
                isPinned: false
            ),
            CollectionEntry(
                id: "id-2",
                name: "Паста",
                color: "#00FF00",
                imageUrl: nil,
                updatedAt: "2026-01-01T00:00:00.000Z",
                deleted: false,
                isPinned: false
            ),
        ]
        let lookups = AssistantAttachableRecipeLookups.build(from: entries)

        XCTAssertEqual(lookups.nameById["ID-1"], untitled)
        XCTAssertEqual(lookups.nameById["id-1"], untitled)
        XCTAssertEqual(lookups.nameById["id-2"], "Паста")
        XCTAssertNil(lookups.colorById["ID-1"])
        XCTAssertNil(lookups.colorById["id-1"])
        XCTAssertEqual(lookups.colorById["id-2"], "#00FF00")
    }

    func testCopyTextUsesFallbackNamesForChipsOnlyMessages() {
        let message = AssistantMessage(
            id: "user-chips-5",
            role: "user",
            text: "",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: [
                    AssistantRecipeAttachment(recipeId: "ID-A", recipeName: nil, recipeColor: nil),
                    AssistantRecipeAttachment(recipeId: "id-b", recipeName: "Паста", recipeColor: nil)
                ],
                interactiveWidget: nil,
                pendingAction: nil,
                actionResolution: nil,
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertEqual(
            AssistantMessageCopyText.text(for: message, fallbackRecipeNameById: ["id-a": "Борщ"]),
            "Борщ, Паста"
        )
    }

    // MARK: - Stream final payload decoding

    func testStreamFinalUserMessageRefDecodesMetadataWithActionResolution() throws {
        // The server returns the persisted user message inside the `final` event with full
        // metadata (including actionResolution). iOS must decode it so applyFinal can copy it
        // onto the optimistic bubble.
        let json = """
        {
            "thread": {"id": "thread-1", "title": "Test"},
            "userMessage": {
                "id": "user-1",
                "content": "confirm_delete",
                "metadata": {
                    "attachments": null,
                    "interactiveWidget": null,
                    "pendingAction": {
                        "id": "01997de3-e1b0-4af6-9dc0-ca558bb62686",
                        "status": "consumed",
                        "toolName": "delete_recipe",
                        "targetLabel": null,
                        "message": null,
                        "confirmLabel": "Удалить",
                        "cancelLabel": "Отмена",
                        "confirmValue": "confirm_delete",
                        "cancelValue": "cancel_delete",
                        "createdAt": "2026-06-15T21:10:58.260Z",
                        "expiresAt": "2026-06-15T21:20:58.260Z"
                    },
                    "actionResolution": {
                        "pendingActionId": "01997de3-e1b0-4af6-9dc0-ca558bb62686",
                        "disposition": "confirmed",
                        "source": "widget",
                        "createdAt": "2026-06-15T21:11:05.000Z"
                    },
                    "followUpSuggestions": null
                },
                "createdAt": "2026-06-15T21:11:05.000Z"
            },
            "assistantMessage": null
        }
        """.data(using: .utf8)!

        let final = try JSONDecoder().decode(AssistantStreamFinalData.self, from: json)

        XCTAssertEqual(final.userMessage?.id, "user-1")
        XCTAssertNotNil(final.userMessage?.metadata)
        XCTAssertEqual(final.userMessage?.metadata?.actionResolution?.source, "widget")
        XCTAssertEqual(final.userMessage?.metadata?.pendingAction?.status, .consumed)
    }

    func testUserBubbleKeepsRawTextWhenActionResolutionIdDoesNotMatchPendingAction() {
        // Guard against stale metadata: if the resolved action id does not match the pending
        // action snapshot, do not substitute the label.
        let pendingActionJson = """
        {
            "id": "01997de3-e1b0-4af6-9dc0-ca558bb62686",
            "status": "consumed",
            "toolName": "delete_recipe",
            "targetLabel": null,
            "message": null,
            "confirmLabel": "Удалить",
            "cancelLabel": "Отмена",
            "confirmValue": "confirm_delete",
            "cancelValue": "cancel_delete",
            "createdAt": "2026-06-15T21:10:58.260Z",
            "expiresAt": "2026-06-15T21:20:58.260Z"
        }
        """.data(using: .utf8)!
        let pendingAction = try! JSONDecoder().decode(AssistantPendingAction.self, from: pendingActionJson)

        let resolutionJson = """
        {
            "pendingActionId": "different-id",
            "disposition": "confirmed",
            "source": "widget",
            "createdAt": "2026-06-15T21:11:05.000Z"
        }
        """.data(using: .utf8)!
        let resolution = try! JSONDecoder().decode(AssistantActionResolution.self, from: resolutionJson)

        let message = AssistantMessage(
            id: "user-mismatch",
            role: "user",
            text: "confirm_delete",
            isStreaming: false,
            metadata: AssistantMessageMetadata(
                attachments: nil,
                interactiveWidget: nil,
                pendingAction: pendingAction,
                actionResolution: resolution,
                followUpSuggestions: nil
            ),
            createdAt: Date()
        )

        XCTAssertEqual(AssistantMessageCopyText.text(for: message), "confirm_delete")
    }

    // MARK: - Helpers

    private func decodeMetadataWithWidgetAndPendingAction() throws -> AssistantMessageMetadata {
        let json = """
        {
            "attachments": null,
            "interactiveWidget": {
                "type": "quick_replies",
                "options": [
                    {"label": "Удалить", "value": "confirm_delete"},
                    {"label": "Отмена", "value": "cancel_delete"}
                ]
            },
            "pendingAction": {
                "id": "01997de3-e1b0-4af6-9dc0-ca558bb62686",
                "status": "pending",
                "toolName": "delete_recipe",
                "targetLabel": "__Тест для нативки",
                "message": "Вы уверены, что хотите навсегда удалить этот рецепт?",
                "confirmLabel": "Удалить",
                "cancelLabel": "Отмена",
                "confirmValue": "confirm_delete",
                "cancelValue": "cancel_delete",
                "createdAt": "2026-06-15T21:10:58.260Z",
                "expiresAt": "2026-06-15T21:20:58.260Z"
            },
            "actionResolution": null,
            "followUpSuggestions": null
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(AssistantMessageMetadata.self, from: json)
    }

    private func makePendingAction() -> AssistantPendingAction {
        // `AssistantPendingAction` is Decodable-only in production; build via JSON round-trip
        // to avoid adding a memberwise initializer just for tests.
        let json = """
        {
            "id": "01997de3-e1b0-4af6-9dc0-ca558bb62686",
            "status": "consumed",
            "toolName": "delete_recipe",
            "targetLabel": null,
            "message": null,
            "confirmLabel": "Удалить",
            "cancelLabel": "Отмена",
            "confirmValue": "confirm_delete",
            "cancelValue": "cancel_delete",
            "createdAt": "2026-06-15T21:10:58.260Z",
            "expiresAt": "2026-06-15T21:20:58.260Z"
        }
        """.data(using: .utf8)!
        // decode is Decodable-only — use try! since the JSON is fixture-tested above.
        let value = try! JSONDecoder().decode(AssistantPendingAction.self, from: json)
        return value
    }

    private func makeResolution(source: String, disposition: String) -> AssistantActionResolution {
        // Direct memberwise init — avoids building JSON literals via string interpolation.
        // The previous raw-string version emitted a literal `\(` into the JSON payload
        // (invalid JSON escape), which made `try!` crash the test host app.
        return AssistantActionResolution(
            pendingActionId: "01997de3-e1b0-4af6-9dc0-ca558bb62686",
            disposition: disposition,
            source: source,
            createdAt: "2026-06-15T21:11:05.000Z"
        )
    }
}
