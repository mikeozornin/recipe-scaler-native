import SwiftUI

/// Placeholder when no `illustrationId` (web `Bowl` icon).
struct IngredientBowlIcon: View {
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvasSize in
            let stroke = Color.secondary
            let lineWidth: CGFloat = 1.5
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let bowlW = size * 0.85
            let bowlH = size * 0.35
            let bowlRect = CGRect(
                x: cx - bowlW / 2,
                y: cy - bowlH * 0.2,
                width: bowlW,
                height: bowlH
            )
            var bowl = Path()
            bowl.addEllipse(in: bowlRect)
            context.stroke(bowl, with: .color(stroke), lineWidth: lineWidth)

            var steam = Path()
            let steamY = bowlRect.minY - size * 0.12
            steam.move(to: CGPoint(x: cx - size * 0.15, y: steamY + size * 0.08))
            steam.addQuadCurve(
                to: CGPoint(x: cx - size * 0.15, y: steamY - size * 0.05),
                control: CGPoint(x: cx - size * 0.28, y: steamY)
            )
            steam.move(to: CGPoint(x: cx, y: steamY + size * 0.1))
            steam.addQuadCurve(
                to: CGPoint(x: cx, y: steamY - size * 0.08),
                control: CGPoint(x: cx + size * 0.12, y: steamY + size * 0.02)
            )
            context.stroke(steam, with: .color(stroke), lineWidth: lineWidth)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}