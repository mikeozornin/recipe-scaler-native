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

    private var labelMaxWidth: CGFloat { FeatureAdoptionRingLabelLayout.labelMaxWidth }

    /// Largest label for the current `total` — same width whether completed is 1 or total.
    private var worstCaseProgressLabel: String {
        formattedProgressLabel(completed: total, total: total)
    }

    private var labelFontSize: CGFloat {
        _ = locale
        return FeatureAdoptionRingLabelLayout.cachedFontSize(
            for: worstCaseProgressLabel,
            localeIdentifier: AppLanguagePreference.current.locale.identifier
        )
    }

    private var progressFraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(completed) / CGFloat(total))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .systemFill), lineWidth: FeatureAdoptionRingLabelLayout.strokeWidth)

            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    Color.primary,
                    style: StrokeStyle(
                        lineWidth: FeatureAdoptionRingLabelLayout.strokeWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            Text(verbatim: progressLabel)
                .font(AppTypography.sansMedium(labelFontSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(maxWidth: labelMaxWidth)
        }
        .frame(
            width: FeatureAdoptionRingLabelLayout.diameter,
            height: FeatureAdoptionRingLabelLayout.diameter
        )
        .accessibilityLabel(Text(verbatim: progressLabel))
    }

    private var progressLabel: String {
        formattedProgressLabel(completed: completed, total: total)
    }

    private func formattedProgressLabel(completed: Int, total: Int) -> String {
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDone ? "checkmark" : "circle")
                .font(isDone ? .body.weight(.semibold) : .body)
                .foregroundStyle(isDone ? Color.primary : Color.secondary)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.titleKey)
                    .appBody()

                if let footnoteKey = item.footnoteKey {
                    Text(footnoteKey)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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
        installedWatchApp: true,
        importedRecipe: true,
        createdRecipe: true,
        createdCollection: true,
        sharedRecipe: true,
        connectedTelegram: true,
        connectedMcpAssistant: true,
        sentAssistantMessage: true,
        usedShoppingList: true
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
        sentAssistantMessage: true,
        usedShoppingList: false
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

#Preview("Wide digits") {
    VStack(spacing: 24) {
        FeatureAdoptionProgressRing(completed: 9, total: 10)
        FeatureAdoptionProgressRing(completed: 10, total: 10)
        FeatureAdoptionProgressRing(completed: 99, total: 99)
    }
    .padding()
}

#Preview("Wide digits RU") {
    VStack(spacing: 24) {
        FeatureAdoptionProgressRing(completed: 9, total: 10)
        FeatureAdoptionProgressRing(completed: 10, total: 10)
    }
    .padding()
    .environment(\.locale, Locale(identifier: "ru"))
}
