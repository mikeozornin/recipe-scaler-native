import SwiftUI

/// iOS 26 zoom-morph transition helpers for recipe detail navigation.
///
/// On iOS 26+ SwiftUI can morph a row thumbnail into the detail screen via
/// `.navigationTransition(.zoom(sourceID:in:))` paired with
/// `.matchedTransitionSource(id:in:)` on the source view. Pre-iOS 26 falls back
/// to the default navigation push transition.
///
/// Centralized here so every recipe-detail entry point can adopt the transition
/// with a single source of truth for the `#available(iOS 26.0, *)` guard and the
/// namespace handling. Use `RecipeZoomTransition.namespace()` once per navigation
/// root and pass the same namespace both to `.recipeZoomTransitionSource(id:)`
/// on the row anchor and to `.recipeZoomTransitionDestination(id:)` on the
/// detail content.
enum RecipeZoomTransition {
    /// Stable id for the zoom source anchor of a given recipe. Equal on source
    /// and destination so SwiftUI can pair them inside one namespace.
    static func sourceID(for recipeId: String) -> String {
        "recipe-zoom-\(recipeId)"
    }
}

extension View {
    /// Anchors this view as the zoom-morph source for a recipe detail open.
    /// Apply to the row thumbnail (or the whole row) inside a `NavigationStack`
    /// that owns `namespace`. No-op on iOS < 26.
    func recipeZoomTransitionSource(recipeId: String, in namespace: Namespace.ID) -> some View {
        modifier(RecipeZoomTransitionSourceModifier(
            recipeId: recipeId,
            namespace: namespace
        ))
    }

    /// Applies the zoom-morph navigation transition to a recipe detail root,
    /// paired with a source anchored via `.recipeZoomTransitionSource(recipeId:)`.
    /// No-op on iOS < 26 (default push transition is used).
    func recipeZoomTransitionDestination(recipeId: String, in namespace: Namespace.ID) -> some View {
        modifier(RecipeZoomTransitionDestinationModifier(
            recipeId: recipeId,
            namespace: namespace
        ))
    }
}

private struct RecipeZoomTransitionSourceModifier: ViewModifier {
    let recipeId: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.matchedTransitionSource(
                id: RecipeZoomTransition.sourceID(for: recipeId),
                in: namespace
            )
        } else {
            content
        }
    }
}

private struct RecipeZoomTransitionDestinationModifier: ViewModifier {
    let recipeId: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationTransition(
                .zoom(
                    sourceID: RecipeZoomTransition.sourceID(for: recipeId),
                    in: namespace
                )
            )
        } else {
            content
        }
    }
}

/// Row-side anchor for the zoom-morph transition. Internal — use
/// `.recipeZoomTransitionSource(recipeId:in:)` for non-optional cases. This
/// modifier accepts an optional namespace so rows that are reused outside the
/// main list (no zoom support) compile without conditional view trees.
struct RecipeRowZoomSourceModifier: ViewModifier {
    let recipeId: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), let namespace {
            content.matchedTransitionSource(
                id: RecipeZoomTransition.sourceID(for: recipeId),
                in: namespace
            )
        } else {
            content
        }
    }
}
