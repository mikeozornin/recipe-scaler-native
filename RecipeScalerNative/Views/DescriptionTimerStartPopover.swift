//
//  DescriptionTimerStartPopover.swift
//  RecipeScalerNative
//
//  Anchored popover — parity with web `TimerDropdown` start row (not a sheet).
//

import SwiftUI

private enum DescriptionTimerStartPopoverMetrics {
    static let width: CGFloat = 240
    static let outerPadding: CGFloat = 4
    static let rowPaddingH: CGFloat = 8
    static let rowPaddingV: CGFloat = 6
    static let titleIconSize: CGFloat = 20
    static let titleIconGap: CGFloat = 8
    /// Web `ml-7` — subtitle aligns under title text, not under icon.
    static let subtitleLeadingInset: CGFloat = 28
    static let cornerRadius: CGFloat = 10
}

struct DescriptionTimerStartPopover: View {
    @Environment(\.colorScheme) private var colorScheme

    let reference: RecipeDescriptionTimerReference
    let accentColor: Color
    let onStart: () -> Void

    var body: some View {
        startRow
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityIdentifiers.descriptionTimerStartPopover)
    }

    private var startRow: some View {
        Button(action: onStart) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DescriptionTimerStartPopoverMetrics.titleIconGap) {
                    AppSymbol.toolbarImage("alarm")
                        .foregroundStyle(.primary)
                        .frame(
                            width: DescriptionTimerStartPopoverMetrics.titleIconSize,
                            height: DescriptionTimerStartPopoverMetrics.titleIconSize
                        )

                    Text(String(localized: "Start timer"))
                        .font(AppTypography.subheadlineSemibold)
                        .foregroundStyle(.primary)
                }

                Text(reference.menuSubtitle)
                    .appFootnote()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, DescriptionTimerStartPopoverMetrics.subtitleLeadingInset)
            }
            .padding(.horizontal, DescriptionTimerStartPopoverMetrics.rowPaddingH)
            .padding(.vertical, DescriptionTimerStartPopoverMetrics.rowPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: DescriptionTimerStartPopoverMetrics.width, alignment: .leading)
        .padding(DescriptionTimerStartPopoverMetrics.outerPadding)
        .background {
            RoundedRectangle(cornerRadius: DescriptionTimerStartPopoverMetrics.cornerRadius, style: .continuous)
                .fill(RecipeDescriptionStyle.timerHighlightSurfaceColor(
                    accent: accentColor,
                    colorScheme: colorScheme
                ))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        }
        .accessibilityLabel(
            "\(String(localized: "Start timer")), \(reference.menuSubtitle)"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(AccessibilityIdentifiers.descriptionTimerStartConfirm)
    }
}

struct DescriptionTimerPopoverOverlay: View {
    let state: DescriptionTimerPopoverState
    let accentColor: Color
    let onStart: () -> Void
    let onDismiss: () -> Void

    @State private var popoverSize = CGSize(
        width: DescriptionTimerStartPopoverMetrics.width + DescriptionTimerStartPopoverMetrics.outerPadding * 2,
        height: 88
    )

    var body: some View {
        GeometryReader { container in
            let origin = container.frame(in: .global).origin
            let anchorLeft = state.anchor.minX - origin.x
            let anchorMinY = state.anchor.minY - origin.y
            let anchorMaxY = state.anchor.maxY - origin.y
            let margin: CGFloat = 16
            let gap: CGFloat = 5
            let posX = clamped(
                anchorLeft + popoverSize.width / 2,
                halfExtent: popoverSize.width / 2,
                in: container.size.width,
                margin: margin
            )
            let belowCenterY = anchorMaxY + popoverSize.height / 2 + gap
            let aboveCenterY = anchorMinY - popoverSize.height / 2 - gap
            let fitsBelow = belowCenterY + popoverSize.height / 2 <= container.size.height - margin
            let rawY = fitsBelow ? belowCenterY : aboveCenterY
            let posY = clamped(
                rawY,
                halfExtent: popoverSize.height / 2,
                in: container.size.height,
                margin: margin
            )

            ZStack {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                DescriptionTimerStartPopover(
                    reference: state.reference,
                    accentColor: accentColor,
                    onStart: {
                        onStart()
                        onDismiss()
                    }
                )
                .fixedSize(horizontal: true, vertical: true)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { popoverSize = proxy.size }
                            .onChange(of: proxy.size) { _, newSize in
                                popoverSize = newSize
                            }
                    }
                )
                .position(x: posX, y: posY)
            }
        }
        .ignoresSafeArea()
    }

    private func clamped(_ center: CGFloat, halfExtent: CGFloat, in width: CGFloat, margin: CGFloat) -> CGFloat {
        min(max(center, halfExtent + margin), width - halfExtent - margin)
    }
}