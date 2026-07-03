import RecipeScalerCore
import SwiftUI

struct IngredientIllustrationPickerSheet: View {
    let ingredientName: String
    let selectedId: String?
    let onSelect: (String?) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @Environment(\.locale) private var locale

    private var catalogLocale: IngredientIllustrationCatalogLocale {
        IngredientIllustrationCatalogLocale.from(languageCode: locale.language.languageCode?.identifier)
    }

    private var entries: [IngredientIllustrationPickerEntry] {
        IngredientIllustrationCatalog.shared.search(query: searchText, locale: catalogLocale)
    }

    private var searchTokens: [String] {
        RecipeSearchUtils.tokenizeQuery(searchText)
    }

    private var pickerTitle: String {
        String(
            format: Bundle.currentLocalizedString("recipes.ingredient-icon.picker-title"),
            locale: locale,
            ingredientName
        )
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8, alignment: .top),
        GridItem(.flexible(), spacing: 8, alignment: .top),
        GridItem(.flexible(), spacing: 8, alignment: .top),
        GridItem(.flexible(), spacing: 8, alignment: .top),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(entries, id: \.id) { entry in
                        pickerCell(entry)
                    }
                }
                .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
                .padding(.vertical, 4)
            }
            .navigationTitle(Text(verbatim: pickerTitle))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("recipes.ingredient-icon.picker-search-placeholder")
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.ingredientPickerSearch)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("recipes.ingredient-icon.picker-clear") {
                        onSelect(nil)
                        onDismiss()
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.ingredientPickerClear)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("edit.done") {
                        onDismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.ingredientIllustrationPicker)
        .appOpaqueSheetPresentation(detents: [.medium, .large])
    }

    private func pickerCell(_ entry: IngredientIllustrationPickerEntry) -> some View {
        Button {
            onSelect(entry.id)
            onDismiss()
        } label: {
            VStack(spacing: 4) {
                IngredientIllustrationThumb(illustrationId: entry.id)
                entryLabel(entry.primaryLabel)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        .overlay {
            if selectedId == entry.id {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.ingredientPickerOption(id: entry.id))
    }

    @ViewBuilder
    private func entryLabel(_ label: String) -> some View {
        if searchTokens.isEmpty {
            Text(label)
                .appFootnote()
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        } else {
            Text(
                RecipeSearchUtils.highlightedAttributedString(
                    label,
                    tokens: searchTokens,
                    font: AppTypography.footnoteUIFont,
                    foregroundColor: .label
                )
            )
            .multilineTextAlignment(.center)
        }
    }
}