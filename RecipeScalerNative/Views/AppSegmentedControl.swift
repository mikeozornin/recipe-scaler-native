//
//  AppSegmentedControl.swift
//  RecipeScalerNative
//

import SwiftUI

/// Segmented control with uniform 17 pt labels (avoids UISegmentedControl normal/selected size mismatch).
struct AppSegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value

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
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = selection == segment.value
        return Button {
            selection = segment.value
        } label: {
            Text(segment.title)
                .font(AppTypography.body)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: segmentCornerRadius, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.06), radius: 1, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(segment.title)
    }
}