import RecipeScalerCore
import SwiftUI

/// The recipe list as the leading column of `IPadRecipesSplitView` (spec 081, T023).
/// `nil` on the phone and in a compact window: the list owns its `NavigationStack` and pushes.
struct RecipeListColumn {
    /// The recipe open in the panel; its row is highlighted.
    let selectedRecipeId: String?
    /// Owned by the split, outside the column `NavigationStack`: a query survives the
    /// column turning into the list over the recipe and back.
    let searchText: Binding<String>
    /// Opens a recipe in the panel (`RecipesSelection.selectingRecipe`).
    let selectRecipe: (_ recipeId: String, _ folderContext: String?, _ openInEditMode: Bool) -> Void
    /// The «Все рецепты | коллекции» title menu; `nil` next to the sidebar, where the
    /// collections are sidebar rows.
    let collectionMenu: RecipeListCollectionMenu?
}

/// Lists the title menu of the list column switches between.
struct RecipeListCollectionMenu {
    let collections: [RecipeFolder]
    /// `nil` is «Все рецепты».
    let selectedCollectionId: String?
    let select: (_ collectionId: String?) -> Void
}

/// Leading title of the list column: «Все рецепты» or the collection name; in the top
/// bar (sidebar hidden) a menu of «Все рецепты» and the collections with a checkmark.
struct RecipeListColumnTitle: View {
    let title: String
    let menu: RecipeListCollectionMenu?

    var body: some View {
        if let menu {
            Menu {
                Toggle(isOn: isSelected(nil, in: menu)) {
                    Text("collections.all-recipes")
                }
                if !menu.collections.isEmpty {
                    Divider()
                    ForEach(menu.collections, id: \.id) { folder in
                        Toggle(isOn: isSelected(folder.id, in: menu)) {
                            Text(verbatim: Self.name(of: folder))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    titleText
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .fixedSize()
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeListTitleMenu)
        } else {
            titleText
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeListTitle)
        }
    }

    private var titleText: some View {
        Text(verbatim: title)
            .font(AppTypography.title2)
            .foregroundStyle(Color.primary)
            .lineLimit(1)
    }

    private func isSelected(_ collectionId: String?, in menu: RecipeListCollectionMenu) -> Binding<Bool> {
        let selected = menu.selectedCollectionId == CollectionVirtualFolders.allRecipesFolderId
            ? nil
            : menu.selectedCollectionId
        return Binding(
            get: { selected == collectionId },
            set: { _ in
                guard selected != collectionId else { return }
                menu.select(collectionId)
            }
        )
    }

    /// The name as the sidebar shows it: the leading emoji, then the name.
    static func name(of folder: RecipeFolder) -> String {
        let presentation = FolderDisplayName.presentation(forStoredName: folder.name)
        return [presentation.leadingEmoji, presentation.displayName]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

/// The leading title of the list column as a bar item, without the Liquid Glass capsule
/// of bar buttons on iOS 26. `nil` adds nothing. A view modifier, not `ToolbarContent`:
/// `if #available` in a toolbar builder needs iOS 17.5.
struct RecipeListColumnTitleToolbar: ViewModifier {
    let title: RecipeListColumnTitle?

    func body(content: Content) -> some View {
        if let title {
            if #available(iOS 26.0, *) {
                content.toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        title
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            } else {
                content.toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        title
                    }
                }
            }
        } else {
            content
        }
    }
}

/// The open recipe of the iPad list column: an accent row with rounded corners (T023).
/// The phone rows get no modifier at all.
struct RecipeColumnRowSelection: ViewModifier {
    let isColumn: Bool
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isColumn {
            content
                .listRowBackground(
                    isSelected
                        ? RoundedRectangle(cornerRadius: RecipeColumnRowMetrics.selectionCornerRadius, style: .continuous)
                            .fill(Color.accentColor)
                            .padding(.horizontal, RecipeColumnRowMetrics.selectionInset)
                        : nil
                )
                .listRowSeparator(isSelected ? .hidden : .automatic)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            content
        }
    }
}

private enum RecipeColumnRowMetrics {
    static let selectionCornerRadius: CGFloat = 14
    static let selectionInset: CGFloat = 8
}
