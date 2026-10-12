import Foundation

/// Spec 081 (plan.md Р2a; FR-004a, FR-004b): in a wide iPad window «Моё всё» is a form
/// sheet over the current section, never a selected tab. Same rule as Scrapp
/// (`RootView.swift:113-137`), kept pure so every entry point shares it.
enum IPadProfileSheetPolicy {
    /// `.profile` in `.padRegular` → the previous section (`.recipes` without one) and the
    /// sheet; anything else stays as it is. Only a real section counts as previous:
    /// «Импорт» and «Ассистент» open sheets and are never selected.
    static func resolve(
        selected: AppTab,
        previous: AppTab?,
        layoutMode: AppLayoutMode
    ) -> (selected: AppTab, presentsSheet: Bool) {
        guard selected == .profile, layoutMode == .padRegular else {
            return (selected, false)
        }
        switch previous {
        case .discover, .recipes, .shopping:
            return (previous ?? .recipes, true)
        case .profile, .assistant, .importTab, nil:
            return (.recipes, true)
        }
    }
}
