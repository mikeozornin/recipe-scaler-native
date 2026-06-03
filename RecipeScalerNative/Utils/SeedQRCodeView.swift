//
//  SeedQRCodeView.swift
//  RecipeScalerNative
//

import CoreImage.CIFilterBuiltins
import SwiftUI

/// QR for seed phrase (web `QRCodeDisplay`).
struct SeedQRCodeView: View {
    let text: String
    var size: CGFloat = 128

    var body: some View {
        if let image = generateQRImage(from: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel(String(localized: "account.qr.accessibility"))
        }
    }

    private func generateQRImage(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}