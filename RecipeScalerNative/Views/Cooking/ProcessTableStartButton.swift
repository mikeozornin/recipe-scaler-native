import SwiftUI

struct ProcessTableStartButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("recipe.process-table.toggle.start")
                .appBody()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: ProcessTableLayout.ctaMinHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .layoutPriority(1)
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeProcessTableStart)
    }
}
