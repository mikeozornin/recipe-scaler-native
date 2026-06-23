//
//  DebugLaunchOptions.swift
//  RecipeScalerNative
//

import Foundation

#if DEBUG
enum DebugLaunchOptions {
    /// Skip splash (verify scripts, deep links).
    static var shouldSkipSplash: Bool {
        if ProcessInfo.processInfo.arguments.contains("ui-testing") { return true }
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-SkipSplash=1" || arg == "-SkipSplash" { return true }
        }
        return openRecipeId != nil
            || openTab != nil
            || startDescriptionEdit
            || startInEditMode
            || showRecipeShare
            || showAssistant
            || openShoppingShare
            || shoppingShareAutoCopyText
    }

    /// `-OpenShoppingShare=1` — opens shopping share sheet (verify scripts).
    static var openShoppingShare: Bool {
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-OpenShoppingShare=1" || arg == "-OpenShoppingShare" { return true }
        }
        return false
    }

    /// `-ShoppingShareAutoCopyText=1` — copies list as text from share sheet (verify scripts).
    static var shoppingShareAutoCopyText: Bool {
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-ShoppingShareAutoCopyText=1" || arg == "-ShoppingShareAutoCopyText" { return true }
        }
        return false
    }

    /// `-ShowAssistant=1` — opens assistant sheet on launch (verify 015).
    static var showAssistant: Bool {
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-ShowAssistant=1" || arg == "-ShowAssistant" { return true }
        }
        return false
    }

    /// `-MobileTimerPanelExpanded=1` — timer panel starts expanded (verify scripts).
    static var mobileTimerPanelExpanded: Bool {
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-MobileTimerPanelExpanded=1" || arg == "-MobileTimerPanelExpanded" { return true }
        }
        return false
    }

    /// `-ScrollToNewIngredient=1` — scroll edit grid to the «+» row (verify scripts).
    static var scrollToNewIngredient: Bool {
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-ScrollToNewIngredient=1" || arg == "-ScrollToNewIngredient" { return true }
        }
        return false
    }

    /// `-StartInEditMode=1` — recipe detail opens in edit mode.
    static var startInEditMode: Bool {
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-StartInEditMode=1" || arg == "-StartInEditMode" { return true }
            if arg.hasPrefix("-StartInEditMode=") {
                let value = String(arg.dropFirst("-StartInEditMode=".count))
                return value == "1" || value.lowercased() == "true"
            }
        }
        return startDescriptionEdit
    }

    /// `-ShowRecipeShare=1` — opens system share sheet on recipe detail (verify 012).
    static var showRecipeShare: Bool {
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-ShowRecipeShare=1" || arg == "-ShowRecipeShare" { return true }
        }
        return false
    }

    /// `xcrun simctl launch … -OpenRecipeId=<uuid>` — opens recipe detail after collection loads.
    static var openRecipeId: String? {
        for arg in ProcessInfo.processInfo.arguments {
            guard arg.hasPrefix("-OpenRecipeId=") else { continue }
            let id = String(arg.dropFirst("-OpenRecipeId=".count))
            return id.isEmpty ? nil : id
        }
        return nil
    }

    /// `-StartDescriptionEdit=1` — opens description WKWebView editor (requires edit mode + v3).
    static var startDescriptionEdit: Bool {
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-StartDescriptionEdit=1" || arg == "-StartDescriptionEdit" {
                return true
            }
            if arg.hasPrefix("-StartDescriptionEdit=") {
                let value = String(arg.dropFirst("-StartDescriptionEdit=".count))
                return value == "1" || value.lowercased() == "true"
            }
        }
        return false
    }

    /// `-DescriptionEditorSimulateText=.` — after editor ready, inserts text (verify scripts only).
    static var simulateDescriptionEditorText: String? {
        for arg in ProcessInfo.processInfo.arguments {
            guard arg.hasPrefix("-DescriptionEditorSimulateText=") else { continue }
            let value = String(arg.dropFirst("-DescriptionEditorSimulateText=".count))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// `-DescriptionEditorSimulateCommand=bold|bulletList|...` — after editor ready,
    /// runs a formatting command to exercise the incremental reconcile sync (verify scripts only).
    static var simulateDescriptionEditorCommand: String? {
        for arg in ProcessInfo.processInfo.arguments {
            guard arg.hasPrefix("-DescriptionEditorSimulateCommand=") else { continue }
            let value = String(arg.dropFirst("-DescriptionEditorSimulateCommand=".count))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// `-OpenTab=shopping|discover|recipes|profile|import`
    static var openTab: AppTab? {
        for arg in ProcessInfo.processInfo.arguments {
            guard arg.hasPrefix("-OpenTab=") else { continue }
            let raw = String(arg.dropFirst("-OpenTab=".count))
            switch raw {
            case "discover": return .discover
            case "import": return .importTab
            case "recipes": return .recipes
            case "shopping": return .shopping
            case "profile": return .profile
            default: return nil
            }
        }
        return nil
    }
}
#endif