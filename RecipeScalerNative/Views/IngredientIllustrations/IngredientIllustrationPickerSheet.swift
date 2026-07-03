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

    private var pickerTitle: String {
        String(
            format: Bundle.currentLocalizedString("recipes.ingredient-icon.picker-title"),
            locale: locale,
            ingredientName
        )
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("recipes.ingredient-icon.picker-search-placeholder", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(AccessibilityIdentifiers.ingredientPickerSearch)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(entries, id: \.id) { entry in
                            Button {
                                onSelect(entry.id)
                                onDismiss()
                            } label: {
                                VStack(spacing: 4) {
                                    IngredientIllustrationThumb(illustrationId: entry.id)
                                    Text(entry.primaryLabel)
                                        .appFootnote()
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.primary)
                                }
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
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
            .navigationTitle(Text(verbatim: pickerTitle))
            .navigationBarTitleDisplayMode(.inline)
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
}