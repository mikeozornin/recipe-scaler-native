import Foundation

struct DiscoverRecipeReturnContext: Hashable, Sendable {
    let scope: DiscoverListScope
    let recipeID: String
}

enum DiscoverRoute: Hashable {
    case collection(String)
    case recipe(
        id: String,
        allowDownloads: Bool = true,
        imageSource: DiscoverRecipeImageSource = .curatedDiscover,
        returnContext: DiscoverRecipeReturnContext? = nil
    )
    case profile(String)
}
