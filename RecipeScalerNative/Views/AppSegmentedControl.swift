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
///
/// `selection` invariant: the caller is responsible for keeping the bound
/// `selection` on an enabled segment. This control only guards taps — it does
/// not auto-correct `selection` when a segment becomes disabled. If the binding
/// ever holds a disabled segment's value, the UI will render a dimmed,
/// unselectable, but visually-"selected" tab. Callers that toggle
/// `Segment.isDisabled` at runtime MUST also reconcile `selection` themselves
/// (see `ImportRecipeSheet.onChange(of: isOnline)` + `resetState()` for the
/// reference pattern).
struct AppSegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: LocalizedStringKey
        /// When `true` the segment is rendered dimmed, ignores taps, and gains
        /// the `.notEnabled` accessibility trait. Caller owns the
        /// `selection ∈ enabled segments` invariant — see type headerdoc.
        var isDisabled: Bool = false
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
        .onAppear {
            #if DEBUG
            if let violation = selectionContractViolation() {
                assertionFailure(
                    "AppSegmentedControl: selection is bound to a disabled segment (\(violation.value)). Caller must keep selection on an enabled segment — see type headerdoc."
                )
            }
            #endif
        }
    }

    /// DEBUG-only trap for the contract documented at the type level: the bound
    /// `selection` must never point at a disabled segment. Returns the
    /// offending segment for a clearer `assertionFailure` message.
    private func selectionContractViolation() -> Segment? {
        guard let selected = segments.first(where: { $0.value == selection }) else {
            return nil
        }
        return selected.isDisabled ? selected : nil
    }

    private var trackBackground: Color {
        // Subtle gray track like a native segmented control, not an "active" filled box.
        Color(.tertiarySystemFill)
    }

    @ViewBuilder
    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = selection == segment.value
        Button {
            guard !segment.isDisabled else { return }
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
        .disabled(segment.isDisabled)
        .opacity(segment.isDisabled ? 0.35 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .zIndex(isSelected ? 1 : 0)
    }

    private func standardLabel(_ segment: Segment, isSelected: Bool) -> some View {
        Text(segment.title)
            .font(AppTypography.body)
            .foregroundStyle(segmentForeground(segment, isSelected: isSelected))
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
            .foregroundStyle(segmentForeground(segment, isSelected: isSelected))
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
            .foregroundStyle(segmentForeground(segment, isSelected: isSelected))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background { selectedPill(isSelected, style: style) }
            .contentShape(Rectangle())
    }

    /// Disabled segments dim to `.secondary`; selected segments stay primary;
    /// unselected enabled segments use the per-style default (`listHeader` uses
    /// `.secondary`, others `.primary`).
    private func segmentForeground(_ segment: Segment, isSelected: Bool) -> Color {
        if segment.isDisabled { return .secondary }
        if isSelected { return .primary }
        return style == .listHeader ? .secondary : .primary
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