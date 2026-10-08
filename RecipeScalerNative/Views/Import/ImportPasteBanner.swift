//
//  ImportPasteBanner.swift
//  RecipeScalerNative
//
//  Spec 080 — «Paste» row on the Text tab of `ImportRecipeSheet`, shown while the
//  clipboard holds a link (same check and wording as the spec 076 banner). The
//  content comes through the system `PasteButton`, so no paste prompt shows.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportPasteBanner: View {
    let isDisabled: Bool
    let onPaste: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("import.clipboard-banner.message")
                .appBody()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            PasteButton(supportedContentTypes: [.url, .plainText]) { providers in
                Task { @MainActor in
                    if let text = await Self.loadText(from: providers) {
                        onPaste(text)
                    }
                }
            }
            // The system titles it in the device language, not the in-app one.
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .disabled(isDisabled)
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.importPasteBanner)
    }

    /// Links from Safari come as a URL; everything else as plain text. Several items join line by line,
    /// the way the text field takes several links.
    private static func loadText(from providers: [NSItemProvider]) async -> String? {
        var lines: [String] = []
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self),
               let url = await load(URL.self, from: provider) {
                lines.append(url.absoluteString)
            } else if provider.canLoadObject(ofClass: String.self),
                      let text = await load(String.self, from: provider) {
                lines.append(text)
            }
        }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func load<T: _ObjectiveCBridgeable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
        where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { object, _ in
                continuation.resume(returning: object)
            }
        }
    }
}
