//
//  AppSegmentedControl.swift
//  RecipeScalerNative
//

import SwiftUI

/// Visual style for `AppSegmentedControl`.
enum AppSegmentedControlStyle {
    /// Default: body labels (import sheet and similar).
    case standard
    /// Matches `NutritionModeSegmentedControl` on recipe detail (KBJU mode toggle).
    case subdued
    /// Top-of-list control (shopping sort): borderless, native segmented-control look.
    case listHeader
}

/// Segmented control with uniform labels (avoids UISegmentedControl normal/selected size mismatch).
struct AppSegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: LocalizedStringKey
        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value
    var style: AppSegmentedControlStyle = .standard

    private let trackInset: CGFloat = 2
    private let cornerRadius: CGFloat = 8
    private let segmentCornerRadius: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(trackInset)
        .background(trackBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if style == .subdued {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var trackBackground: Color {
        // Subtle gray track like a native segmented control, not an "active" filled box.
        Color(.tertiarySystemFill)
    }

    @ViewBuilder
    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = selection == segment.value
        Button {
            selection = segment.value
        } label: {
            switch style {
            case .standard:
                standardLabel(segment, isSelected: isSelected)
            case .subdued:
                subduedLabel(segment, isSelected: isSelected)
            case .listHeader:
                listHeaderLabel(segment, isSelected: isSelected)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .zIndex(isSelected ? 1 : 0)
    }

    private func standardLabel(_ segment: Segment, isSelected: Bool) -> some View {
        Text(segment.title)
            .font(AppTypography.body)
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background { selectedPill(isSelected, style: style) }
            .contentShape(Rectangle())
    }

    private func subduedLabel(_ segment: Segment, isSelected: Bool) -> some View {
        Text(segment.title)
            .font(AppTypography.sansMedium(AppTypography.calloutSize))
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background { selectedPill(isSelected, style: style) }
            .contentShape(Rectangle())
    }

    private func listHeaderLabel(_ segment: Segment, isSelected: Bool) -> some View {
        Text(segment.title)
            .font(AppTypography.sansMedium(AppTypography.calloutSize))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background { selectedPill(isSelected, style: style) }
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func selectedPill(_ isSelected: Bool, style: AppSegmentedControlStyle) -> some View {
        if isSelected {
            // White raised pill over the gray track (native segmented-control look).
            RoundedRectangle(cornerRadius: segmentCornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 1, y: 1)
        }
    }
}