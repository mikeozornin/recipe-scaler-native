import SwiftUI

struct ProcessTableTimerChipButton: View {
    let chip: ProcessTableTimerChip
    var onStart: ((ProcessTableTimerChip) -> Void)?

    var body: some View {
        Button {
            onStart?(chip)
        } label: {
            HStack(spacing: ProcessTableLayout.timerChipGap) {
                AppSymbol.sizedImage(
                    "alarm",
                    pointSize: ProcessTableLayout.checkboxPointSize,
                    weight: .semibold
                )
                Text(shortLabel)
                    .appBody()
                    .lineLimit(1)
            }
            .padding(.horizontal, ProcessTableLayout.timerChipHorizontalPad)
            .padding(.vertical, ProcessTableLayout.timerChipVerticalPad)
            .overlay(
                Capsule()
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(onStart == nil)
        .accessibilityLabel(Text(chip.name))
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeProcessTableTimerChip)
    }

    private var shortLabel: String {
        let unitKey: String
        switch chip.type {
        case .hours: unitKey = "time.short.hours"
        case .minutes: unitKey = "time.short.minutes"
        case .seconds: unitKey = "time.short.seconds"
        }
        let number = AppNumberFormat.string(chip.value, maximumFractionDigits: 2)
        return "\(number) \(Bundle.currentLocalizedString(unitKey))"
    }
}
