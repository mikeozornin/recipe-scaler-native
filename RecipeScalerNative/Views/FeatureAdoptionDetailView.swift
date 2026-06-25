//
//  FeatureAdoptionDetailView.swift
//  RecipeScalerNative
//

import SwiftUI

/// Spec 038 — submenu screen that lists every feature-adoption flag with its
/// current state. Lives behind a `NavigationLink` from `AccountView`, so the
/// main profile page stays compact.
struct FeatureAdoptionDetailView: View {
    @Environment(FeatureAdoptionStore.self) private var store
    @Environment(\.locale) private var locale

    private var totalCount: Int { FeatureAdoptionItem.allCases.count }

    private var doneCount: Int {
        FeatureAdoptionItem.allCases.filter { store.value(for: $0) }.count
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 24) {
                    Text(verbatim: pageTitle)
                        .font(AppTypography.display(34))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityAddTraits(.isHeader)

                    FeatureAdoptionProgressRing(
                        completed: doneCount,
                        total: totalCount
                    )
                }
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
                .listRowBackground(Color(uiColor: .systemGroupedBackground))
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(FeatureAdoptionItem.allCases, id: \.rawValue) { item in
                    FeatureAdoptionRow(item: item, isDone: store.value(for: item))
                }
            }
            .appListSectionHeaderStyle()
        }
        .appListBodyTypography()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.refresh()
        }
        .refreshable {
            await store.refresh()
        }
    }

    private var pageTitle: String {
        _ = locale
        return Bundle.currentLocalizedString("account.feature-adoption.title")
    }
}

private struct FeatureAdoptionProgressRing: View {
    let completed: Int
    let total: Int

    @Environment(\.locale) private var locale

    private let diameter: CGFloat = 152
    private let strokeWidth: CGFloat = 12

    private var progressFraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(completed) / CGFloat(total))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .systemFill), lineWidth: strokeWidth)

            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    Color.primary,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(verbatim: progressLabel)
                .font(AppTypography.sansMedium(40))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .monospacedDigit()
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(Text(verbatim: progressLabel))
    }

    private var progressLabel: String {
        _ = locale
        return String(
            format: Bundle.currentLocalizedString("account.feature-adoption.progress %d %d"),
            locale: AppLanguagePreference.current.locale,
            completed,
            total
        )
    }
}

private struct FeatureAdoptionRow: View {
    let item: FeatureAdoptionItem
    let isDone: Bool

    var body: some View {
        HStack {
            Image(systemName: isDone ? "checkmark" : "circle")
                .font(isDone ? .body.weight(.semibold) : .body)
                .foregroundStyle(isDone ? Color.primary : Color.secondary)
                .frame(width: 22, alignment: .center)
            Text(item.titleKey)
                .appBody()
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: Bundle.currentLocalizedString(
            isDone
                ? "account.feature-adoption.state.done"
                : "account.feature-adoption.state.pending"
        )))
    }
}

// MARK: - Previews

#Preview("All done") {
    let store = FeatureAdoptionStore()
    store.report = FeatureAdoptionReport(
        installedNativeApp: true,
        importedRecipe: true,
        createdRecipe: true,
        createdCollection: true,
        sharedRecipe: true,
        connectedTelegram: true,
        connectedMcpAssistant: true,
        sentAssistantMessage: true
    )
    return NavigationStack {
        FeatureAdoptionDetailView()
            .environment(store)
    }
}

#Preview("Partial") {
    let store = FeatureAdoptionStore()
    store.report = FeatureAdoptionReport(
        installedNativeApp: false,
        importedRecipe: true,
        createdRecipe: true,
        createdCollection: true,
        sharedRecipe: false,
        connectedTelegram: false,
        connectedMcpAssistant: false,
        sentAssistantMessage: true
    )
    return NavigationStack {
        FeatureAdoptionDetailView()
            .environment(store)
    }
}

#Preview("All pending") {
    let store = FeatureAdoptionStore()
    return NavigationStack {
        FeatureAdoptionDetailView()
            .environment(store)
    }
}
