import SwiftUI

struct AwakeScrollCameraPreview: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.45))
            AppSymbol.sizedImage("camera.fill", pointSize: 16, weight: .semibold)
                .foregroundStyle(.white)
        }
        .frame(
            width: AwakeScrollLayout.cameraPreviewDiameter,
            height: AwakeScrollLayout.cameraPreviewDiameter
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
