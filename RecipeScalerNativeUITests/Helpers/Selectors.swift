import Foundation

/// Mirrors `RecipeScalerNative/AccessibilityIdentifiers.swift`.
///
/// UI test bundles cannot `@testable import RecipeScalerNative` because the
/// app target transitively depends on C modules (GRDB) that aren't reachable
/// from the UI test bundle's module graph. Keep this file in sync with the
/// app-side catalog by grepping for new identifiers before adding new specs.
enum UIA {
    // MARK: - Root / splash / auth
    static let rootContent = "root_content"
    static let splashView = "splash_view"
    static let authRoot = "auth_root"
    static let authNewUserButton = "auth_new_user_button"
    static let authExistingUserButton = "auth_existing_user_button"
    static let authSeedTextEditor = "auth_seed_text_editor"
    static let authLoginButton = "auth_login_button"
    static let authBackButton = "auth_back_button"
    static let authQRCodeButton = "auth_qr_code_button"

    // MARK: - Tabs
    static let tabDiscover = "tab_discover"
    static let tabImport = "tab_import"
    static let tabRecipes = "tab_recipes"
    static let tabShopping = "tab_shopping"
    static let tabProfile = "tab_profile"

    // MARK: - Discover (011/017)
    static let discoverRoot = "discover_root"
    static let discoverCollectionCard = "discover_collection_card"
    static let discoverProfileCard = "discover_profile_card"
    static let discoverProfileHeader = "discover_profile_header"
    static let discoverRecipeCard = "discover_recipe_card"
    static let discoverRecipeCardPrefix = "discover_recipe_card_"
    static let discoverRecipeCloneButton = "discover_recipe_clone_button"
    static let discoverCollectionSearchField = "discover_collection_search_field"
    static let discoverProfileSearchField = "discover_profile_search_field"
    static let discoverServingsStepper = "discover_servings_stepper"

    static func discoverRecipeCard(id recipeID: String) -> String {
        "\(discoverRecipeCardPrefix)\(recipeID)"
    }

    // MARK: - Shopping list (024)
    static let shoppingList = "shopping_list"
    static let shoppingAddField = "shopping_add_field"
    static let shoppingShareButton = "shopping_share_button"
    static let shoppingRemindersTip = "shopping_reminders_tip"
    static let shoppingRemindersTipEnable = "shopping_reminders_tip_enable"
    static let shoppingRemindersTipDismiss = "shopping_reminders_tip_dismiss"
    static let shoppingCopyAsTextButton = "shopping_copy_as_text_button"

    // MARK: - Import (010/027)
    static let importSheet = "import_sheet"
    static let importFilePickButton = "import_file_pick_button"

    // MARK: - Account (013/020)
    static let accountRoot = "account_root"
    static let accountExportLogsMissing = "account_export_logs_missing"
    static let accountClearLogs = "account_clear_logs"
    static let accountTelegramConnect = "account_telegram_connect"
    static let accountTelegramDisconnect = "account_telegram_disconnect"
    static let accountTelegramCode = "account_telegram_code"
    static let accountTelegramCopy = "account_telegram_copy"
    static let accountTelegramRefresh = "account_telegram_refresh"
    static let accountTimerNotificationsToggle = "account_timer_notifications_toggle"
    static let accountTipsSection = "account_tips_section"
    static let accountTipsMenu = "account_tips_menu"
    static let accountFeedbackMenu = "account_feedback_menu"
    static let accountFeedbackEditor = "account_feedback_editor"
    static let accountFeedbackAttach = "account_feedback_attach"
    static let accountFeedbackSend = "account_feedback_send"
    static let accountTipsRetry = "account_tips_retry"
    static let accountTipsRestore = "account_tips_restore"
    static let accountTipsManage = "account_tips_manage"

    static func accountTipPurchase(productID: String) -> String {
        let slug = productID.replacingOccurrences(of: ".", with: "_")
        return "account_tip_purchase_\(slug)"
    }

    // MARK: - Account deletion (055)
    static let deleteAccountButton = "delete_account_button"
    static let deleteAccountSeedInput = "delete_account_seed_input"
    static let deleteAccountConfirmButton = "delete_account_confirm_button"
    static let deleteAccountCancelButton = "delete_account_cancel_button"
    static let deleteAccountError = "delete_account_error"

    // MARK: - Assistant (015/021)
    static let assistantFab = "assistant_fab"
    static let assistantSheet = "assistant_sheet"
    static let assistantComposerShell = "assistant_composer_shell"
    static let assistantMessageInput = "assistant_message_input"
    static let assistantKeyboardDone = "assistant_keyboard_done"
    static let assistantAttachmentButton = "assistant_attachment_button"
    static let assistantVoiceRecordButton = "assistant_voice_record_button"
    static let assistantSendButton = "assistant_send_button"
    static let assistantFollowUps = "assistant_follow_ups"
    static let assistantMarkdownContent = "assistant_markdown_content"
    static let assistantContextRecipeTag = "assistant_context_recipe_tag"
    static let assistantNewThreadButton = "assistant_new_thread_button"
    static let assistantHistoryButton = "assistant_history_button"
    static let assistantOfflineFootnote = "assistant_offline_footnote"
    static let assistantThreadPanel = "assistant_thread_panel"
    static let assistantThreadSearchInput = "assistant_thread_search_input"

    static func assistantThreadItem(threadId: String) -> String {
        "assistant_thread_item_\(threadId)"
    }

    static func assistantThreadDeleteButton(threadId: String) -> String {
        "assistant_thread_delete_button_\(threadId)"
    }

    // MARK: - Recipe list / detail (002)
    static let recipeList = "recipe_list"
    static let recipeListAdd = "recipe_list_add"
    static let recipeRowPrefix = "recipe_row_"
    static let profileButton = "profile_button"
    static let scaleMinusButton = "scale_minus_button"
    static let scalePlusButton = "scale_plus_button"
    static let scaleSlider = "scale_slider"
    static let ingredientsSection = "ingredients_section"
    static let ingredientIcon = "ingredient_icon"
    static let ingredientIllustrationPicker = "ingredient_illustration_picker"
    static let ingredientPickerSearch = "ingredient_picker_search"
    static let ingredientPickerClear = "ingredient_picker_clear"

    static func ingredientPickerOption(id: String) -> String {
        "ingredient_picker_option_\(id)"
    }

    static let ingredientDragHandle = "ingredient_drag_handle"
    static let recipeEditServingsRow = "recipe_edit_servings_row"
    static let recipeEditIngredientReorderToggle = "recipe_edit_ingredient_reorder_toggle"
    static let recipeEditNewIngredientRow = "recipe_edit_new_ingredient_row"
    static let recipeEditNewIngredientSubmit = "recipe_edit_new_ingredient_submit"
    static let stepsSection = "steps_section"
    static let descriptionEditor = "description_editor"
    static let recipeDetailMenu = "recipe_detail_menu"
    static let recipeDetailEdit = "recipe_detail_edit"
    static let recipeDetailDone = "recipe_detail_done"
    static let recipeTitleField = "recipe_title_field"
    static let recipeDetailMenuAddAllToShopping = "recipe_detail_menu_add_all_to_shopping"
    static let ingredientSwipeAddToShopping = "ingredient_swipe_add_to_shopping"
    static let importSubmitButton = "import_submit_button"
    static let screenAwakeToggle = "screen_awake_toggle"
    static let screenAwakeBanner = "screen_awake_banner"
    static let transientStatusBanner = "transient_status_banner"
    static let transientStatusMessage = "transient_status_message"
    static let recipeImageUpload = "recipe_image_upload"
    static let recipeTitleKeyboardDone = "recipe_title_keyboard_done"
    static let descriptionEditorKeyboardDone = "description_editor_keyboard_done"
    static let syncStatusTransport = "sync_status_transport"

    // MARK: - Timers (014/036)
    static let mobileTimerPanel = "mobile_timer_panel"
    static let mobileTimerPanelHeader = "mobile_timer_panel_header"
    static let descriptionTimerStartPopover = "description_timer_start_popover"
    static let descriptionTimerStartConfirm = "description_timer_start_confirm"

    static func mobileTimerChip(timerId: String) -> String {
        "mobile_timer_chip_\(timerId)"
    }

    static func mobileTimerToggle(timerId: String) -> String {
        "mobile_timer_toggle_\(timerId)"
    }

    static func mobileTimerDelete(timerId: String) -> String {
        "mobile_timer_delete_\(timerId)"
    }

    // MARK: - Collections (008/026)
    static let collectionsRoot = "collections_root"
    static let collectionsRootRowPrefix = "collection_row_"
    static let collectionsRootGridTilePrefix = "collection_grid_"
    static let collectionsNewRow = "collection_new_row"
    static let collectionsViewModeToggle = "collections_view_mode_toggle"
    static let collectionAssignSheet = "collection_assign_sheet"
    static let manageCollectionRecipesSheet = "manage_collection_recipes_sheet"

    static func collectionsRootRow(folderId: String) -> String {
        "\(collectionsRootRowPrefix)\(folderId)"
    }

    static func collectionsRootGridTile(folderId: String) -> String {
        "\(collectionsRootGridTilePrefix)\(folderId)"
    }

    static func recipeRow(id: String) -> String {
        "\(recipeRowPrefix)\(id)"
    }
}
