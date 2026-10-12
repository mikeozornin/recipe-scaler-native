import Foundation

/// Spec 081 (plan.md Р2a; FR-004a, FR-004b): in a wide iPad window «Моё всё» is a form
/// sheet over the current section, never a selected tab. Same rule as Scrapp
/// (`RootView.swift:113-137`), kept pure so every entry point shares it.
enum IPadProfileSheetPolicy {
    /// `.profile` in `.padRegular` → the previous section (`.recipes` without one) and the
    /// sheet; anything else stays as it is. Only a real section counts as previous:
    /// «Импорт» and «Ассистент» open sheets and are never selected.
    ///
    /// The sheet survives narrowing (the system shows it full width), so `.profile` with
    /// the sheet already up keeps it in any mode: one `AccountView`, never a second page
    /// under the sheet. On the iPhone the sheet is never presented.
    static func resolve(
        selected: AppTab,
        previous: AppTab?,
        layoutMode: AppLayoutMode,
        isSheetPresented: Bool = false
    ) -> (selected: AppTab, presentsSheet: Bool) {
        guard selected == .profile, layoutMode == .padRegular || isSheetPresented else {
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
